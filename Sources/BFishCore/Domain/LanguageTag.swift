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
