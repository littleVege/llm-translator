import Foundation
import LLMTranslatorCore

enum LLMError: LocalizedError {
    case invalidBaseURL
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Invalid API base URL — check Settings."
        case .http(let status, let body):
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return "HTTP \(status)\(detail.isEmpty ? "" : ": \(detail.prefix(300))")"
        }
    }
}

/// Minimal streaming client for any OpenAI-compatible chat completions
/// endpoint (Anthropic compat, OpenAI, DeepSeek, Ollama, LM Studio, …).
enum LLMClient {
    static func stream(system: String, user: String) -> AsyncThrowingStream<String, Error> {
        let settings = AppSettings.shared
        let baseURL = settings.baseURL
        let apiKey = settings.apiKey
        let model = settings.model

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = endpoint(baseURL) else { throw LLMError.invalidBaseURL }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 120
                    request.cachePolicy = .reloadIgnoringLocalCacheData
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                    if !apiKey.isEmpty {
                        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    }
                    let payload: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": [
                            ["role": "system", "content": system],
                            ["role": "user", "content": user],
                        ],
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count > 2048 { break }
                        }
                        throw LLMError.http(http.statusCode, String(data: body, encoding: .utf8) ?? "")
                    }

                    var decoder = OpenAIStreamDecoder()
                    var lineDecoder = EventStreamLineDecoder()
                    var reachedEnd = false

                    streamBytes: for try await byte in bytes {
                        try Task.checkCancellation()
                        guard let line = lineDecoder.consume(byte: byte) else { continue }
                        for event in try decoder.consume(line: line) {
                            switch event {
                            case .content(let delta):
                                continuation.yield(delta)
                            case .done:
                                reachedEnd = true
                                break streamBytes
                            }
                        }
                    }

                    if !reachedEnd {
                        if let line = lineDecoder.finish() {
                            for event in try decoder.consume(line: line) {
                                switch event {
                                case .content(let delta):
                                    continuation.yield(delta)
                                case .done:
                                    reachedEnd = true
                                }
                            }
                        }
                    }

                    if !reachedEnd {
                        for event in try decoder.finish() {
                            switch event {
                            case .content(let delta):
                                continuation.yield(delta)
                            case .done:
                                break
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Accepts "https://host/v1", "https://host/v1/" or a full
    /// ".../chat/completions" URL.
    static func endpoint(_ base: String) -> URL? {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if !trimmed.hasSuffix("/chat/completions") {
            trimmed += "/chat/completions"
        }
        return URL(string: trimmed)
    }

}
