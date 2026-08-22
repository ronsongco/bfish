import Foundation

public struct AudioTimeRange: Codable, Equatable, Sendable {
    public let start: TimeInterval
    public let end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) throws {
        guard start.isFinite, end.isFinite else {
            throw AudioTimeRangeError.nonFinite
        }
        guard start >= 0 else {
            throw AudioTimeRangeError.negativeStart(start)
        }
        guard end >= start else {
            throw AudioTimeRangeError.endPrecedesStart(start: start, end: end)
        }
        self.start = start
        self.end = end
    }

    private init(validatedStart start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end - start }

    private enum CodingKeys: String, CodingKey { case start, end }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            start: values.decode(TimeInterval.self, forKey: .start),
            end: values.decode(TimeInterval.self, forKey: .end)
        )
    }
}

public enum AudioTimeRangeError: Error, Equatable, Sendable {
    case nonFinite
    case negativeStart(TimeInterval)
    case endPrecedesStart(start: TimeInterval, end: TimeInterval)
}

public enum TimestampRepairReason: String, Codable, Sendable {
    case nonFinite
    case negativeStart
    case reversedRange
}

public struct RepairedAudioTimeRange: Sendable {
    public let timeRange: AudioTimeRange
    public let reason: TimestampRepairReason?
}

public extension AudioTimeRange {
    /// Repairs untrusted model timestamps at an adapter boundary. Non-finite
    /// values collapse to the last known valid position; reversed or negative
    /// ranges are clamped while preserving finite duration where possible.
    static func repairing(
        start: TimeInterval,
        end: TimeInterval,
        fallbackStart: TimeInterval = 0
    ) -> RepairedAudioTimeRange {
        let safeFallback = fallbackStart.isFinite ? max(0, fallbackStart) : 0
        guard start.isFinite, end.isFinite else {
            return RepairedAudioTimeRange(
                timeRange: AudioTimeRange(validatedStart: safeFallback, end: safeFallback),
                reason: .nonFinite
            )
        }
        let repairedStart = max(0, start)
        let repairedEnd = max(repairedStart, end)
        let reason: TimestampRepairReason? = if start < 0 {
            .negativeStart
        } else if end < start {
            .reversedRange
        } else {
            nil
        }
        return RepairedAudioTimeRange(
            timeRange: AudioTimeRange(validatedStart: repairedStart, end: repairedEnd),
            reason: reason
        )
    }
}

public struct SpeakerID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public var description: String { rawValue }
}

public struct RecognizedSegment: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let timeRange: AudioTimeRange
    public let timeline: CaptureTimeline
    public let language: WhisperLanguage
    public let sourceText: String
    public let speaker: SpeakerID?
    public let confidence: Double?
    public let languageConfidence: Double?
    public let noSpeechProbability: Double?
    public let compressionRatio: Double?
    public let containsMixedLanguages: Bool

    public init(
        id: UUID = UUID(),
        timeRange: AudioTimeRange,
        timeline: CaptureTimeline,
        language: WhisperLanguage,
        sourceText: String,
        speaker: SpeakerID? = nil,
        confidence: Double? = nil,
        languageConfidence: Double? = nil,
        noSpeechProbability: Double? = nil,
        compressionRatio: Double? = nil,
        containsMixedLanguages: Bool = false
    ) {
        self.id = id
        self.timeRange = timeRange
        self.timeline = timeline
        self.language = language
        self.sourceText = sourceText
        self.speaker = speaker
        self.confidence = confidence
        self.languageConfidence = languageConfidence
        self.noSpeechProbability = noSpeechProbability
        self.compressionRatio = compressionRatio
        self.containsMixedLanguages = containsMixedLanguages
    }
}

public struct TranscriptTurn: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let timeRange: AudioTimeRange
    public let timeline: CaptureTimeline
    public let language: WhisperLanguage
    public let sessionLocale: SessionLocale?
    public let sourceText: String
    public let englishText: String?
    public let speaker: SpeakerID?

    public init(segment: RecognizedSegment, englishText: String?, sessionLocale: SessionLocale?) {
        self.id = segment.id
        self.timeRange = segment.timeRange
        self.timeline = segment.timeline
        self.language = segment.language
        self.sessionLocale = sessionLocale
        self.sourceText = segment.sourceText
        self.englishText = englishText
        self.speaker = segment.speaker
    }
}

public struct TranslationResponse: Codable, Equatable, Sendable {
    /// Translation-owned output only. Source text remains authoritative in the caller.
    public let englishText: String
    public let promptTokenCount: Int?

    public init(englishText: String, promptTokenCount: Int? = nil) {
        self.englishText = englishText
        self.promptTokenCount = promptTokenCount
    }
}
