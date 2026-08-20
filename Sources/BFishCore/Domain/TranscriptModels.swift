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
    public let language: LanguageTag
    public let sourceText: String
    public let speaker: SpeakerID?
    public let confidence: Double?

    public init(
        id: UUID = UUID(),
        timeRange: AudioTimeRange,
        language: LanguageTag,
        sourceText: String,
        speaker: SpeakerID? = nil,
        confidence: Double? = nil
    ) {
        self.id = id
        self.timeRange = timeRange
        self.language = language
        self.sourceText = sourceText
        self.speaker = speaker
        self.confidence = confidence
    }
}

public struct TranscriptTurn: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let timeRange: AudioTimeRange
    public let language: LanguageTag
    public let sourceText: String
    public let englishText: String?
    public let speaker: SpeakerID?

    public init(segment: RecognizedSegment, englishText: String?) {
        self.id = segment.id
        self.timeRange = segment.timeRange
        self.language = segment.language
        self.sourceText = segment.sourceText
        self.englishText = englishText
        self.speaker = segment.speaker
    }
}

public struct TranslationResponse: Codable, Equatable, Sendable {
    /// Translation-owned output only. Source text remains authoritative in the caller.
    public let englishText: String

    public init(englishText: String) {
        self.englishText = englishText
    }
}
