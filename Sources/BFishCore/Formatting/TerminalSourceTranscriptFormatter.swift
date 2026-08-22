import Foundation

public struct TerminalSourceTranscriptFormatter: Sendable {
    public init() {}

    public func format(_ segment: RecognizedSegment, sessionLocale: SessionLocale? = nil) -> String {
        let displayedLanguage = sessionLocale?.rawValue ?? segment.language.rawValue
        var header = "[\(Self.timestamp(segment.timeRange.start))] [\(displayedLanguage)]"
        if let speaker = segment.speaker {
            header += " [\(speaker.rawValue)]"
        }
        return "\(header)\nSource: \(segment.sourceText)"
    }

    public func format(_ turn: TranscriptTurn) -> String {
        let displayedLanguage = turn.sessionLocale?.rawValue ?? turn.language.rawValue
        var header = "[\(Self.timestamp(turn.timeRange.start))] [\(displayedLanguage)]"
        if let speaker = turn.speaker {
            header += " [\(speaker.rawValue)]"
        }
        return "\(header)\nSource: \(turn.sourceText)"
    }

    private static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(
            format: "%02d:%02d:%02d",
            total / 3_600,
            (total % 3_600) / 60,
            total % 60
        )
    }
}
