import Foundation

public enum AudioInput: Equatable, Sendable {
    case file(URL)
    case device(uid: String)
    case system
    case application(bundleIdentifier: String)
}

public struct CaptureTimeline: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let startedAt: Date?

    public init(id: UUID = UUID(), startedAt: Date? = nil) {
        self.id = id
        self.startedAt = startedAt
    }
}

/// An owned, consumer-side chunk. Core Audio callbacks must write into a
/// preallocated ring buffer and must not construct this value.
public struct AudioChunk: Sendable {
    public let samples: [Float]
    public let timeRange: AudioTimeRange
    public let timeline: CaptureTimeline
    public let sampleRate: Double
    public let channelCount: Int

    public init(
        samples: [Float],
        timeRange: AudioTimeRange,
        timeline: CaptureTimeline,
        sampleRate: Double,
        channelCount: Int
    ) {
        self.samples = samples
        self.timeRange = timeRange
        self.timeline = timeline
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}


public enum SegmentBoundaryReason: String, Codable, Sendable {
    case voiceActivity
    case maximumDuration
    case endOfInput
    case discontinuity
}

public struct SpeechSegment: Sendable {
    public let samples: [Float]
    public let timeRange: AudioTimeRange
    public let timeline: CaptureTimeline
    public let sampleRate: Double
    public let channelCount: Int
    public let boundaryReason: SegmentBoundaryReason
    public let noSpeechProbability: Double?

    public init(
        samples: [Float],
        timeRange: AudioTimeRange,
        timeline: CaptureTimeline,
        sampleRate: Double = 16_000,
        channelCount: Int = 1,
        boundaryReason: SegmentBoundaryReason,
        noSpeechProbability: Double? = nil
    ) {
        self.samples = samples
        self.timeRange = timeRange
        self.timeline = timeline
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.boundaryReason = boundaryReason
        self.noSpeechProbability = noSpeechProbability
    }
}
