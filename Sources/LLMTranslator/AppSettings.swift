import Combine
import Foundation
import Security

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var providerID: String { didSet { defaults.set(providerID, forKey: "providerID") } }
    @Published var baseURL: String { didSet { defaults.set(baseURL, forKey: "baseURL") } }
    @Published var model: String { didSet { defaults.set(model, forKey: "model") } }
    @Published var apiKey: String { didSet { Keychain.setAPIKey(apiKey) } }
    @Published var promptTemplate: String { didSet { defaults.set(promptTemplate, forKey: "promptTemplate") } }
    @Published var sourceCode: String { didSet { defaults.set(sourceCode, forKey: "sourceCode") } }
    @Published var targetCode: String { didSet { defaults.set(targetCode, forKey: "targetCode") } }
    @Published var altTargetCode: String { didSet { defaults.set(altTargetCode, forKey: "altTargetCode") } }
    @Published var hotkeyID: String { didSet { defaults.set(hotkeyID, forKey: "hotkeyID") } }

    var hotkeyOption: HotkeyOption {
        HotkeyOption(rawValue: hotkeyID) ?? .optT
    }

    static let defaultPrompt = """
    You are a professional translation engine.
    Translate the text from {from} to {to}.
    Rules:
    - Output only the translation, with no explanations, notes, or surrounding quotes.
    - Preserve the original formatting, line breaks, numbers, code, and proper nouns.
    - Use natural, idiomatic phrasing in {to}.
    """

    private init() {
        let systemTarget = Language.systemDefault()
        let storedBaseURL = defaults.string(forKey: "baseURL") ?? "https://api.anthropic.com/v1"
        baseURL = storedBaseURL
        model = defaults.string(forKey: "model") ?? "claude-haiku-4-5"
        // Migrate existing installs: derive the provider from the saved URL.
        providerID = defaults.string(forKey: "providerID") ?? Providers.matching(baseURL: storedBaseURL).id
        apiKey = Keychain.apiKey() ?? ""
        promptTemplate = defaults.string(forKey: "promptTemplate") ?? Self.defaultPrompt
        sourceCode = defaults.string(forKey: "sourceCode") ?? Language.auto.code
        targetCode = defaults.string(forKey: "targetCode") ?? systemTarget.code
        altTargetCode = defaults.string(forKey: "altTargetCode")
            ?? (systemTarget.code == "en" ? "zh-Hans" : "en")
        hotkeyID = defaults.string(forKey: "hotkeyID") ?? HotkeyOption.optT.rawValue
    }
}

enum Keychain {
    private static let service = "com.dicai.llm-translator"
    private static let account = "api-key"

    static func apiKey() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setAPIKey(_ value: String) {
        if value.isEmpty {
            SecItemDelete(baseQuery() as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var query = baseQuery()
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
