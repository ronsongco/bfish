public struct LanguageTag: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public var description: String { rawValue }

    public static let automatic = LanguageTag("auto")
    public static let english = LanguageTag("en")
    public static let japanese = LanguageTag("ja")
    public static let korean = LanguageTag("ko")
    public static let mandarin = LanguageTag("zh")
    public static let portuguese = LanguageTag("pt")
    public static let brazilianPortuguese = LanguageTag("pt-BR")
    public static let tagalog = LanguageTag("tl")
    public static let spanish = LanguageTag("es")
    public static let italian = LanguageTag("it")
}

/// A language value accepted by Whisper. Locale-specific presentation choices,
/// such as Brazilian Portuguese, remain separate in `LanguageTag`.
public enum WhisperLanguage: String, Codable, CaseIterable, Sendable {
    case automatic = "auto"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case mandarin = "zh"
    case portuguese = "pt"
    case tagalog = "tl"
    case spanish = "es"
    case italian = "it"
}
