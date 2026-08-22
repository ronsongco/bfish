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
    case modelStatus = "model_status"
    case recognitionCompleted = "recognition_completed"
    case recognitionWindow = "recognition_window"
    case segmentCompleted = "segment_completed"
    case translationUnavailable = "translation_unavailable"
    case translationSuppressed = "translation_suppressed"
    case audioChunksDropped = "audio_chunks_dropped"
    case timelineDiscontinuity = "timeline_discontinuity"
    case timestampRepaired = "timestamp_repaired"
    case probabilityRepaired = "probability_repaired"
    case segmentFiltered = "segment_filtered"
}

public enum SegmentFilterReason: String, Codable, Sendable {
    case empty
    case annotation
    case noContent
}

public enum ProbabilityRepairField: String, Codable, Sendable {
    case confidence
    case noSpeechProbability = "no_speech_probability"
}

public enum ModelStatus: String, Codable, Sendable {
    case resolving
    case downloading
    case filesReady = "files_ready"
    case loading
    case loaded
    case alreadyResident = "already_resident"
}

public struct ProbabilityDistributionSummary: Codable, Equatable, Sendable {
    public let count: Int
    public let minimum: Double
    public let median: Double
    public let percentile90: Double
    public let maximum: Double

    public init(count: Int, minimum: Double, median: Double, percentile90: Double, maximum: Double) {
        self.count = count
        self.minimum = minimum
        self.median = median
        self.percentile90 = percentile90
        self.maximum = maximum
    }
}

/// Typed diagnostic details intentionally exclude audio and transcript text.
public struct DiagnosticDetails: Codable, Equatable, Sendable {
    public let errorCode: String?
    public let droppedChunkCount: Int?
    public let promptTokenCount: Int?
    public let contextCharacterCount: Int?
    public let timestampRepairReason: TimestampRepairReason?
    public let segmentFilterReason: SegmentFilterReason?
    public let probabilityRepairField: ProbabilityRepairField?
    public let audioDurationSeconds: Double?
    public let realTimeFactor: Double?
    public let sdkInputAudioSeconds: Double?
    public let modelStatus: ModelStatus?
    public let progressPercentage: Int?
    public let selectedLanguage: WhisperLanguage?
    public let languageConfidence: Double?
    public let automaticLanguageDetection: Bool?
    public let segmentCount: Int?
    public let lastSegmentEndSeconds: Double?
    public let confidenceDistribution: ProbabilityDistributionSummary?
    public let noSpeechProbabilityDistribution: ProbabilityDistributionSummary?
    public let peakResidentMemoryBytes: UInt64?
    public let physicalFootprintBytes: UInt64?
    public let segmentsBeyondAudioDurationCount: Int?
    public let maximumTimestampOverflowSeconds: Double?
    public let previousSegmentStartSeconds: Double?
    public let currentSegmentStartSeconds: Double?
    public let segmentStartDeltaSeconds: Double?
    public let windowIndex: Int?
    public let windowStartSeconds: Double?
    public let windowDurationSeconds: Double?
    public let windowEndSeconds: Double?
    public let firstSegmentStartSeconds: Double?
    public let lastSegmentEndSecondsInWindow: Double?
    public let windowTimestampOverflowSeconds: Double?

    public init(
        errorCode: String? = nil,
        droppedChunkCount: Int? = nil,
        promptTokenCount: Int? = nil,
        contextCharacterCount: Int? = nil,
        timestampRepairReason: TimestampRepairReason? = nil,
        segmentFilterReason: SegmentFilterReason? = nil,
        probabilityRepairField: ProbabilityRepairField? = nil,
        audioDurationSeconds: Double? = nil,
        realTimeFactor: Double? = nil,
        sdkInputAudioSeconds: Double? = nil,
        modelStatus: ModelStatus? = nil,
        progressPercentage: Int? = nil,
        selectedLanguage: WhisperLanguage? = nil,
        languageConfidence: Double? = nil,
        automaticLanguageDetection: Bool? = nil,
        segmentCount: Int? = nil,
        lastSegmentEndSeconds: Double? = nil,
        confidenceDistribution: ProbabilityDistributionSummary? = nil,
        noSpeechProbabilityDistribution: ProbabilityDistributionSummary? = nil,
        peakResidentMemoryBytes: UInt64? = nil,
        physicalFootprintBytes: UInt64? = nil,
        segmentsBeyondAudioDurationCount: Int? = nil,
        maximumTimestampOverflowSeconds: Double? = nil,
        previousSegmentStartSeconds: Double? = nil,
        currentSegmentStartSeconds: Double? = nil,
        segmentStartDeltaSeconds: Double? = nil,
        windowIndex: Int? = nil,
        windowStartSeconds: Double? = nil,
        windowDurationSeconds: Double? = nil,
        windowEndSeconds: Double? = nil,
        firstSegmentStartSeconds: Double? = nil,
        lastSegmentEndSecondsInWindow: Double? = nil,
        windowTimestampOverflowSeconds: Double? = nil
    ) {
        self.errorCode = errorCode
        self.droppedChunkCount = droppedChunkCount
        self.promptTokenCount = promptTokenCount
        self.contextCharacterCount = contextCharacterCount
        self.timestampRepairReason = timestampRepairReason
        self.segmentFilterReason = segmentFilterReason
        self.probabilityRepairField = probabilityRepairField
        self.audioDurationSeconds = audioDurationSeconds
        self.realTimeFactor = realTimeFactor
        self.sdkInputAudioSeconds = sdkInputAudioSeconds
        self.modelStatus = modelStatus
        self.progressPercentage = progressPercentage
        self.selectedLanguage = selectedLanguage
        self.languageConfidence = languageConfidence
        self.automaticLanguageDetection = automaticLanguageDetection
        self.segmentCount = segmentCount
        self.lastSegmentEndSeconds = lastSegmentEndSeconds
        self.confidenceDistribution = confidenceDistribution
        self.noSpeechProbabilityDistribution = noSpeechProbabilityDistribution
        self.peakResidentMemoryBytes = peakResidentMemoryBytes
        self.physicalFootprintBytes = physicalFootprintBytes
        self.segmentsBeyondAudioDurationCount = segmentsBeyondAudioDurationCount
        self.maximumTimestampOverflowSeconds = maximumTimestampOverflowSeconds
        self.previousSegmentStartSeconds = previousSegmentStartSeconds
        self.currentSegmentStartSeconds = currentSegmentStartSeconds
        self.segmentStartDeltaSeconds = segmentStartDeltaSeconds
        self.windowIndex = windowIndex
        self.windowStartSeconds = windowStartSeconds
        self.windowDurationSeconds = windowDurationSeconds
        self.windowEndSeconds = windowEndSeconds
        self.firstSegmentStartSeconds = firstSegmentStartSeconds
        self.lastSegmentEndSecondsInWindow = lastSegmentEndSecondsInWindow
        self.windowTimestampOverflowSeconds = windowTimestampOverflowSeconds
    }
}

public struct DiagnosticEvent: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 11

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
