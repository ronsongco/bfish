import Foundation

public struct TerminalTranscriptFormatter: TranscriptFormatting {
    public init() {}

    public func format(_ turn: TranscriptTurn) -> String {
        var header = "[\( Self.timestamp(turn.timeRange.start))] [\(turn.language.rawValue)]"
        if let speaker = turn.speaker {
            header += " [\(speaker.rawValue)]"
        }

        let english = turn.englishText ?? "<translation unavailable>"
        return "\(header)\nSource: \(turn.sourceText)\nEnglish: \(english)"
    }

    private static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainingSeconds = total % 60

        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }
}
