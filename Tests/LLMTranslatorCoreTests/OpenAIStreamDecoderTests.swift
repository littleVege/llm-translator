import Testing
@testable import LLMTranslatorCore

@Suite("OpenAI stream decoder")
struct OpenAIStreamDecoderTests {
    @Test("preserves empty lines across LF, CRLF, and CR")
    func preservesEventBoundaryLines() {
        var decoder = EventStreamLineDecoder()
        let bytes = Array("data: one\r\n\r\ndata: 二\n\ndata: three\r\r".utf8)
        var lines: [String] = []

        for byte in bytes {
            if let line = decoder.consume(byte: byte) {
                lines.append(line)
            }
        }

        #expect(lines == ["data: one", "", "data: 二", "", "data: three", ""])
        #expect(decoder.finish() == nil)
    }

    @Test("decodes OpenAI SSE incrementally")
    func decodesOpenAIServerSentEventsIncrementally() throws {
        var decoder = OpenAIStreamDecoder()

        #expect(try decoder.consume(line: ": keep-alive") == [])
        #expect(
            try decoder.consume(
                line: "data: {\"choices\":[{\"delta\":{\"content\":\"你\"}}]}"
            ) == []
        )
        #expect(try decoder.consume(line: "") == [.content("你")])
        #expect(try decoder.consume(line: "data:[DONE]") == [])
        #expect(try decoder.consume(line: "") == [.done])
    }

    @Test("joins data fields and flushes the last event")
    func joinsMultipleDataFieldsAndFlushesAtEndOfFile() throws {
        var decoder = OpenAIStreamDecoder()
        #expect(try decoder.consume(line: "event: message") == [])
        #expect(try decoder.consume(line: "data: {\"choices\":[") == [])
        #expect(
            try decoder.consume(
                line: "data: {\"delta\":{\"content\":\"hello\"}}]}"
            ) == []
        )
        #expect(try decoder.finish() == [.content("hello")])
    }

    @Test("supports content parts and Responses API events")
    func supportsContentPartsAndResponsesAPIEvents() throws {
        var chatDecoder = OpenAIStreamDecoder()
        _ = try chatDecoder.consume(
            line: "data: {\"choices\":[{\"delta\":{\"content\":[{\"type\":\"text\",\"text\":\"A\"},{\"type\":\"text\",\"text\":\"B\"}]}}]}"
        )
        #expect(try chatDecoder.consume(line: "") == [.content("AB")])

        var responsesDecoder = OpenAIStreamDecoder()
        _ = try responsesDecoder.consume(line: "event: response.output_text.delta")
        _ = try responsesDecoder.consume(
            line: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"chunk\"}"
        )
        #expect(try responsesDecoder.consume(line: "") == [.content("chunk")])
        _ = try responsesDecoder.consume(line: "event: response.completed")
        _ = try responsesDecoder.consume(line: "data: {}")
        #expect(try responsesDecoder.consume(line: "") == [.done])
    }

    @Test("decodes a plain JSON fallback")
    func decodesPlainJSONFallback() throws {
        var decoder = OpenAIStreamDecoder()
        #expect(try decoder.consume(line: "{") == [])
        #expect(
            try decoder.consume(
                line: "\"choices\":[{\"message\":{\"content\":\"complete response\"}}]}"
            ) == [.content("complete response")]
        )
        #expect(try decoder.finish() == [])
    }

    @Test("surfaces errors sent inside a stream")
    func surfacesErrorsSentInsideAStream() throws {
        var decoder = OpenAIStreamDecoder()
        _ = try decoder.consume(line: "event: error")
        _ = try decoder.consume(line: "data: {\"error\":{\"message\":\"quota exceeded\"}}")

        do {
            _ = try decoder.consume(line: "")
            Issue.record("Expected a stream error")
        } catch {
            #expect(error as? ChatStreamDecodingError == .server("quota exceeded"))
        }
    }

    @Test("surfaces an SSE error event with a message payload")
    func surfacesErrorEventMessage() throws {
        var decoder = OpenAIStreamDecoder()
        _ = try decoder.consume(line: "event: error")
        _ = try decoder.consume(line: "data: {\"message\":\"model unavailable\"}")

        do {
            _ = try decoder.consume(line: "")
            Issue.record("Expected a stream error")
        } catch {
            #expect(error as? ChatStreamDecodingError == .server("model unavailable"))
        }
    }

    @Test("rejects truncated JSON at end of stream")
    func rejectsTruncatedJSONWhenConnectionCloses() throws {
        var decoder = OpenAIStreamDecoder()
        #expect(try decoder.consume(line: "{\"choices\":[") == [])

        do {
            _ = try decoder.finish()
            Issue.record("Expected invalid JSON")
        } catch {
            guard case .invalidJSON = error as? ChatStreamDecodingError else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }
}
