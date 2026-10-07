import Foundation

/// A decoded update from an OpenAI-compatible streaming response.
public enum ChatStreamEvent: Equatable, Sendable {
    case content(String)
    case done
}

public enum ChatStreamDecodingError: LocalizedError, Equatable, Sendable {
    case invalidJSON(String)
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let value):
            return "Invalid streaming response: \(value.prefix(300))"
        case .server(let message):
            return "Streaming response error: \(message)"
        }
    }
}

/// Splits a byte stream into UTF-8 lines without dropping empty lines. Empty
/// lines carry the event boundary in SSE, while Foundation's AsyncBytes.lines
/// intentionally omits them.
public struct EventStreamLineDecoder: Sendable {
    private var buffer: [UInt8] = []
    private var ignoresNextLineFeed = false

    public init() {}

    public mutating func consume(byte: UInt8) -> String? {
        if ignoresNextLineFeed {
            ignoresNextLineFeed = false
            if byte == 0x0A { return nil }
        }

        switch byte {
        case 0x0A: // LF
            return takeLine()
        case 0x0D: // CR, possibly followed by LF
            ignoresNextLineFeed = true
            return takeLine()
        default:
            buffer.append(byte)
            return nil
        }
    }

    public mutating func finish() -> String? {
        ignoresNextLineFeed = false
        guard !buffer.isEmpty else { return nil }
        return takeLine()
    }

    private mutating func takeLine() -> String {
        defer { buffer.removeAll(keepingCapacity: true) }
        return String(decoding: buffer, as: UTF8.self)
    }
}

/// Incrementally decodes both standards-compliant Server-Sent Events and a
/// plain JSON response. Keeping protocol parsing outside the UI/network layer
/// makes provider quirks testable without making live API calls.
public struct OpenAIStreamDecoder: Sendable {
    private enum Format: Sendable {
        case unknown
        case serverSentEvents
        case json
    }

    private var format: Format = .unknown
    private var sseParser = ServerSentEventParser()
    private var jsonBuffer = ""

    public init() {}

    /// Feeds one response line, without its line terminator.
    public mutating func consume(line rawLine: String) throws -> [ChatStreamEvent] {
        let line = stripByteOrderMark(from: rawLine)

        if format == .unknown {
            if isSSELine(line) {
                format = .serverSentEvents
            } else if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return []
            } else {
                format = .json
            }
        }

        switch format {
        case .serverSentEvents:
            guard let event = sseParser.consume(line: line) else { return [] }
            return try Self.decode(event)
        case .json:
            return try consumeJSONLine(line)
        case .unknown:
            return []
        }
    }

    /// Flushes a final SSE event or JSON object when the connection closes
    /// without a trailing blank line/newline.
    public mutating func finish() throws -> [ChatStreamEvent] {
        switch format {
        case .serverSentEvents:
            guard let event = sseParser.finish() else { return [] }
            return try Self.decode(event)
        case .json:
            let pending = jsonBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pending.isEmpty else { return [] }
            jsonBuffer = ""
            return try Self.decodeJSON(pending, eventName: nil)
        case .unknown:
            return []
        }
    }

    private mutating func consumeJSONLine(_ line: String) throws -> [ChatStreamEvent] {
        if !jsonBuffer.isEmpty { jsonBuffer.append("\n") }
        jsonBuffer.append(line)

        // A compact JSON/NDJSON response can be emitted immediately. Pretty
        // printed JSON stays buffered until its closing delimiter arrives.
        guard Self.isCompleteJSON(jsonBuffer) else { return [] }
        let value = jsonBuffer
        jsonBuffer = ""
        return try Self.decodeJSON(value, eventName: nil)
    }

    private static func decode(_ event: ServerSentEvent) throws -> [ChatStreamEvent] {
        let data = event.data.trimmingCharacters(in: .whitespacesAndNewlines)
        if data == "[DONE]" || isCompletionEvent(event.name) {
            return [.done]
        }
        if event.name?.lowercased() == "error", data.isEmpty {
            throw ChatStreamDecodingError.server("The provider ended the stream with an error.")
        }
        guard !data.isEmpty else { return [] }

        do {
            return try decodeJSON(data, eventName: event.name)
        } catch ChatStreamDecodingError.invalidJSON where event.name?.lowercased() == "error" {
            throw ChatStreamDecodingError.server(data)
        }
    }

    private static func decodeJSON(
        _ source: String,
        eventName: String?
    ) throws -> [ChatStreamEvent] {
        guard let data = source.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw ChatStreamDecodingError.invalidJSON(source)
        }
        guard let object = value as? [String: Any] else { return [] }

        if let message = errorMessage(in: object) {
            throw ChatStreamDecodingError.server(message)
        }
        if eventName?.lowercased() == "error" {
            let message = (object["message"] as? String) ?? source
            throw ChatStreamDecodingError.server(message)
        }

        let type = object["type"] as? String
        var updates: [ChatStreamEvent] = []

        if let content = choiceContent(in: object), !content.isEmpty {
            updates.append(.content(content))
        } else if type == "response.output_text.delta",
                  let delta = object["delta"] as? String,
                  !delta.isEmpty {
            updates.append(.content(delta))
        } else if type == "content_block_delta",
                  let delta = object["delta"] as? [String: Any],
                  let text = delta["text"] as? String,
                  !text.isEmpty {
            updates.append(.content(text))
        } else if let message = object["message"] as? [String: Any],
                  let content = textContent(message["content"]),
                  !content.isEmpty {
            // Also accepts the line-delimited shape returned by Ollama's
            // native chat endpoint when it sits behind a compatibility proxy.
            updates.append(.content(content))
        }

        if isCompletionEvent(eventName)
            || isCompletionEvent(type)
            || object["done"] as? Bool == true
            || firstChoice(in: object)?["finish_reason"] is String {
            updates.append(.done)
        }

        return updates
    }

    private static func choiceContent(in object: [String: Any]) -> String? {
        guard let choice = firstChoice(in: object) else { return nil }
        if let delta = choice["delta"] as? [String: Any] {
            if let content = textContent(delta["content"]) { return content }
            if let text = delta["text"] as? String { return text }
        }
        if let message = choice["message"] as? [String: Any],
           let content = textContent(message["content"]) {
            return content
        }
        return choice["text"] as? String
    }

    private static func firstChoice(in object: [String: Any]) -> [String: Any]? {
        (object["choices"] as? [[String: Any]])?.first
    }

    private static func textContent(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        guard let parts = value as? [Any] else { return nil }
        let strings = parts.compactMap { part -> String? in
            if let string = part as? String { return string }
            guard let object = part as? [String: Any] else { return nil }
            if let text = object["text"] as? String { return text }
            if let text = object["text"] as? [String: Any] {
                return text["value"] as? String
            }
            return nil
        }
        return strings.isEmpty ? nil : strings.joined()
    }

    private static func errorMessage(in object: [String: Any]) -> String? {
        if let error = object["error"] as? [String: Any] {
            return (error["message"] as? String)
                ?? (error["detail"] as? String)
                ?? String(describing: error)
        }
        if object["type"] as? String == "error" {
            if let message = object["message"] as? String { return message }
            if let error = object["error"] as? String { return error }
        }
        return nil
    }

    private static func isCompleteJSON(_ source: String) -> Bool {
        guard let data = source.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    private static func isCompletionEvent(_ value: String?) -> Bool {
        guard let value = value?.lowercased() else { return false }
        return value == "done"
            || value == "message_stop"
            || value == "response.completed"
            || value == "response.done"
    }

    private func isSSELine(_ line: String) -> Bool {
        if line.hasPrefix(":") { return true }
        let field = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first
        return field == "data" || field == "event" || field == "id" || field == "retry"
    }

    private mutating func stripByteOrderMark(from line: String) -> String {
        guard format == .unknown, line.first == "\u{feff}" else { return line }
        return String(line.dropFirst())
    }
}

private struct ServerSentEvent: Sendable {
    let name: String?
    let data: String
}

/// Implements the event framing rules from the SSE specification: comments
/// are ignored, multiple data fields are joined with a newline, and a blank
/// line dispatches the event.
private struct ServerSentEventParser: Sendable {
    private var eventName: String?
    private var dataLines: [String] = []

    mutating func consume(line rawLine: String) -> ServerSentEvent? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty { return dispatch() }
        if line.hasPrefix(":") { return nil }

        let pieces = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(pieces[0])
        var value = pieces.count == 2 ? String(pieces[1]) : ""
        if value.hasPrefix(" ") { value.removeFirst() }

        switch field {
        case "event":
            eventName = value
        case "data":
            dataLines.append(value)
        default:
            break
        }
        return nil
    }

    mutating func finish() -> ServerSentEvent? {
        dispatch()
    }

    private mutating func dispatch() -> ServerSentEvent? {
        defer {
            eventName = nil
            dataLines.removeAll(keepingCapacity: true)
        }
        guard !dataLines.isEmpty else { return nil }
        return ServerSentEvent(name: eventName, data: dataLines.joined(separator: "\n"))
    }
}
