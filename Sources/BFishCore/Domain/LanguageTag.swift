public struct SessionLocale: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        let components = rawValue.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard let language = components.first,
              (2...3).contains(language.count),
              Self.isASCIILetters(language),
              components.dropFirst().allSatisfy(Self.isValidSubtag)
        else { return nil }

        var normalized = [language.lowercased()]
        for component in components.dropFirst() {
            if component.count == 2, Self.isASCIILetters(component) {
                normalized.append(component.uppercased())
            } else if component.count == 4, Self.isASCIILetters(component) {
                normalized.append(component.prefix(1).uppercased() + component.dropFirst().lowercased())
            } else {
                normalized.append(component.lowercased())
            }
        }
        self.rawValue = normalized.joined(separator: "-")
    }

    public init?(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let locale = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid session locale: \(value)")
        }
        self = locale
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    public static let english = SessionLocale("en")!
    public static let japanese = SessionLocale("ja")!
    public static let korean = SessionLocale("ko")!
    public static let mandarin = SessionLocale("zh")!
    public static let portuguese = SessionLocale("pt")!
    public static let brazilianPortuguese = SessionLocale("pt-BR")!
    public static let tagalog = SessionLocale("tl")!
    public static let spanish = SessionLocale("es")!
    public static let italian = SessionLocale("it")!

    private static func isValidSubtag(_ value: String) -> Bool {
        switch value.count {
        case 2, 4:
            return isASCIILetters(value)
        case 3:
            return isASCIILetters(value) || value.allSatisfy { $0.isASCII && $0.isNumber }
        case 5...8:
            return value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        default:
            return false
        }
    }

    private static func isASCIILetters(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isASCII && $0.isLetter }
    }
}

/// A normalized language token accepted by Whisper. Locale-specific choices,
/// such as Brazilian Portuguese, remain separate in `SessionLocale`.
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
