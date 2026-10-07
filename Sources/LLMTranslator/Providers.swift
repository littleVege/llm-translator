import Foundation

/// A preset LLM provider. `models` empty means the provider has no fixed model
/// list (local runtimes, aggregators) — the UI shows a free-text model field.
struct Provider: Identifiable, Hashable {
    let id: String
    let name: String
    let baseURL: String
    let models: [String]

    var isCustom: Bool { id == Providers.customID }
    var hasModelPresets: Bool { !models.isEmpty }
    var isLocal: Bool {
        baseURL.contains("localhost") || baseURL.contains("127.0.0.1")
    }
}

enum Providers {
    static let customID = "custom"

    /// Ordered list shown in the Provider picker. Base URLs are the
    /// OpenAI-compatible roots; the client appends `/chat/completions`.
    static let all: [Provider] = [
        Provider(
            id: "anthropic",
            name: "Anthropic (Claude)",
            baseURL: "https://api.anthropic.com/v1",
            models: ["claude-haiku-4-5", "claude-sonnet-5", "claude-opus-4-8", "claude-fable-5"]
        ),
        Provider(
            id: "openai",
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            models: ["gpt-4o-mini", "gpt-4o", "gpt-5.5", "gpt-5.4"]
        ),
        Provider(
            id: "gemini",
            name: "Google Gemini",
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
            models: ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"]
        ),
        Provider(
            id: "deepseek",
            name: "DeepSeek",
            baseURL: "https://api.deepseek.com",
            models: ["deepseek-v4-flash", "deepseek-v4-pro"]
        ),
        Provider(
            id: "mistral",
            name: "Mistral",
            baseURL: "https://api.mistral.ai/v1",
            models: ["mistral-small-latest", "mistral-large-latest"]
        ),
        Provider(
            id: "openrouter",
            name: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            models: []
        ),
        Provider(
            id: "ollama",
            name: "Ollama (local)",
            baseURL: "http://localhost:11434/v1",
            models: []
        ),
        Provider(
            id: "lmstudio",
            name: "LM Studio (local)",
            baseURL: "http://localhost:1234/v1",
            models: []
        ),
    ]

    static let custom = Provider(id: customID, name: "Custom…", baseURL: "", models: [])

    static func byID(_ id: String) -> Provider {
        all.first { $0.id == id } ?? custom
    }

    /// Derives the provider from a stored base URL — used to migrate existing
    /// users who have a saved URL but no `providerID` yet.
    static func matching(baseURL: String) -> Provider {
        let target = normalize(baseURL)
        return all.first { normalize($0.baseURL) == target } ?? custom
    }

    private static func normalize(_ url: String) -> String {
        var value = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }
}
