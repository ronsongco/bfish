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

/// A normalized language token accepted by Whisper. Locale-specific choices,
/// such as Brazilian Portuguese, remain separate in `LanguageTag`.
public struct WhisperLanguage: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        let normalized = rawValue.lowercased()
        guard Self.supportedTokens.contains(normalized) else { return nil }
        self.rawValue = normalized
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let language = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported Whisper language token: \(value)")
        }
        self = language
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    public static let supportedTokens: Set<String> = [
        "auto", "af", "am", "ar", "as", "az", "ba", "be", "bg", "bn", "bo", "br", "bs",
        "ca", "cs", "cy", "da", "de", "el", "en", "es", "et", "eu", "fa", "fi", "fo", "fr",
        "gl", "gu", "ha", "haw", "he", "hi", "hr", "ht", "hu", "hy", "id", "is", "it", "ja",
        "jw", "ka", "kk", "km", "kn", "ko", "la", "lb", "ln", "lo", "lt", "lv", "mg", "mi",
        "mk", "ml", "mn", "mr", "ms", "mt", "my", "ne", "nl", "nn", "no", "oc", "pa", "pl",
        "ps", "pt", "ro", "ru", "sa", "sd", "si", "sk", "sl", "sn", "so", "sq", "sr", "su",
        "sv", "sw", "ta", "te", "tg", "th", "tk", "tl", "tr", "tt", "uk", "ur", "uz", "vi",
        "yi", "yo", "zh",
    ]

    public static let automatic = Self(rawValue: "auto")!
    public static let english = Self(rawValue: "en")!
    public static let japanese = Self(rawValue: "ja")!
    public static let korean = Self(rawValue: "ko")!
    public static let mandarin = Self(rawValue: "zh")!
    public static let portuguese = Self(rawValue: "pt")!
    public static let tagalog = Self(rawValue: "tl")!
    public static let spanish = Self(rawValue: "es")!
    public static let italian = Self(rawValue: "it")!
}
