import Foundation
import NaturalLanguage

struct Language: Hashable, Identifiable {
    let code: String
    let englishName: String
    let displayName: String

    var id: String { code }

    static let auto = Language(code: "auto", englishName: "Auto", displayName: "Auto Detect")

    static let all: [Language] = [
        Language(code: "en", englishName: "English", displayName: "English"),
        Language(code: "zh-Hans", englishName: "Simplified Chinese", displayName: "简体中文"),
        Language(code: "zh-Hant", englishName: "Traditional Chinese", displayName: "繁體中文"),
        Language(code: "ja", englishName: "Japanese", displayName: "日本語"),
        Language(code: "ko", englishName: "Korean", displayName: "한국어"),
        Language(code: "es", englishName: "Spanish", displayName: "Español"),
        Language(code: "fr", englishName: "French", displayName: "Français"),
        Language(code: "de", englishName: "German", displayName: "Deutsch"),
        Language(code: "it", englishName: "Italian", displayName: "Italiano"),
        Language(code: "pt", englishName: "Portuguese", displayName: "Português"),
        Language(code: "ru", englishName: "Russian", displayName: "Русский"),
        Language(code: "ar", englishName: "Arabic", displayName: "العربية"),
        Language(code: "hi", englishName: "Hindi", displayName: "हिन्दी"),
        Language(code: "th", englishName: "Thai", displayName: "ไทย"),
        Language(code: "vi", englishName: "Vietnamese", displayName: "Tiếng Việt"),
        Language(code: "id", englishName: "Indonesian", displayName: "Bahasa Indonesia"),
        Language(code: "nl", englishName: "Dutch", displayName: "Nederlands"),
        Language(code: "pl", englishName: "Polish", displayName: "Polski"),
        Language(code: "tr", englishName: "Turkish", displayName: "Türkçe"),
        Language(code: "uk", englishName: "Ukrainian", displayName: "Українська"),
    ]

    static func byCode(_ code: String) -> Language? {
        if code == auto.code { return auto }
        return all.first { $0.code == code }
    }

    /// Maps codes like "zh-Hans", "zh-Hans-CN" or "en-US" to a known language.
    static func fromLocaleCode(_ raw: String) -> Language? {
        let parts = raw.split(separator: "-").map(String.init)
        var n = parts.count
        while n >= 1 {
            let candidate = parts.prefix(n).joined(separator: "-")
            if let match = all.first(where: { $0.code == candidate }) { return match }
            n -= 1
        }
        if let first = parts.first,
           let match = all.first(where: { $0.code.hasPrefix(first) }) {
            return match
        }
        return nil
    }

    static func systemDefault() -> Language {
        for preferred in Locale.preferredLanguages {
            if let match = fromLocaleCode(preferred) { return match }
        }
        return byCode("en") ?? all[0]
    }
}

enum LanguageDetector {
    static func detect(_ text: String) -> Language? {
        let sample = String(text.prefix(400))
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        return Language.fromLocaleCode(dominant.rawValue)
    }
}
