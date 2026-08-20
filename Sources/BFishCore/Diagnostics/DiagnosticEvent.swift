import Foundation

public struct StageTiming: Codable, Equatable, Sendable {
    public let stage: String
    public let milliseconds: Double

    public init(stage: String, milliseconds: Double) {
        self.stage = stage
        self.milliseconds = milliseconds
    }
}

public enum DiagnosticEventKind: String, Codable, Sendable {
    case segmentCompleted = "segment_completed"
    case translationUnavailable = "translation_unavailable"
    case translationSuppressed = "translation_suppressed"
    case audioChunksDropped = "audio_chunks_dropped"
    case timelineDiscontinuity = "timeline_discontinuity"
    case timestampRepaired = "timestamp_repaired"
    case segmentFiltered = "segment_filtered"
}

public enum SegmentFilterReason: String, Codable, Sendable {
    case empty
    case annotation
    case noLetters
}

/// Typed diagnostic details intentionally exclude audio and transcript text.
public struct DiagnosticDetails: Codable, Equatable, Sendable {
    public let errorCode: String?
    public let droppedChunkCount: Int?
    public let promptTokenCount: Int?
    public let contextCharacterCount: Int?
    public let timestampRepairReason: TimestampRepairReason?
    public let segmentFilterReason: SegmentFilterReason?

    public init(
        errorCode: String? = nil,
        droppedChunkCount: Int? = nil,
        promptTokenCount: Int? = nil,
        contextCharacterCount: Int? = nil,
        timestampRepairReason: TimestampRepairReason? = nil,
        segmentFilterReason: SegmentFilterReason? = nil
    ) {
        self.errorCode = errorCode
        self.droppedChunkCount = droppedChunkCount
        self.promptTokenCount = promptTokenCount
        self.contextCharacterCount = contextCharacterCount
        self.timestampRepairReason = timestampRepairReason
        self.segmentFilterReason = segmentFilterReason
    }
}

public struct DiagnosticEvent: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public let timestamp: Date
    public let event: DiagnosticEventKind
    public let segmentID: UUID?
    public let timings: [StageTiming]
    public let details: DiagnosticDetails?

    public init(
        timestamp: Date = Date(),
        schemaVersion: Int = DiagnosticEvent.currentSchemaVersion,
        event: DiagnosticEventKind,
        segmentID: UUID? = nil,
        timings: [StageTiming] = [],
        details: DiagnosticDetails? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.timestamp = timestamp
        self.event = event
        self.segmentID = segmentID
        self.timings = timings
        self.details = details
    }

    public func jsonLine() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }
}
