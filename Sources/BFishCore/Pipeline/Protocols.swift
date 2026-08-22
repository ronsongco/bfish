import Foundation

public protocol AudioCapturing: Sendable {
    /// Implementations must use bounded buffering and report dropped chunks.
    func chunks(from input: AudioInput, buffering: AudioBufferingPolicy) -> CapturedAudioStream
}

public struct AudioBufferingPolicy: Equatable, Sendable {
    public let newestChunkLimit: Int

    public init(newestChunkLimit: Int = 32) {
        self.newestChunkLimit = max(1, newestChunkLimit)
    }
}

public struct CapturedAudioStream: Sendable {
    public let chunks: AsyncThrowingStream<AudioChunk, Error>
    public let diagnostics: AsyncStream<DiagnosticEvent>

    public init(chunks: AsyncThrowingStream<AudioChunk, Error>, diagnostics: AsyncStream<DiagnosticEvent>) {
        self.chunks = chunks
        self.diagnostics = diagnostics
    }
}

public protocol SpeechSegmenting: Sendable {
    func segments(from chunks: AsyncThrowingStream<AudioChunk, Error>) -> AsyncThrowingStream<SpeechSegment, Error>
}

public protocol SpeechRecognizing: Sendable {
    func transcribe(_ input: AudioInput, language: WhisperLanguage) async throws -> SpeechRecognitionOutput
    func events(
        for input: AudioInput,
        language: WhisperLanguage
    ) async -> AsyncThrowingStream<SpeechRecognitionEvent, Error>
}

public enum SpeechRecognitionEvent: Sendable {
    case segment(RecognizedSegment)
    case diagnostic(DiagnosticEvent)
    case completed(timings: [StageTiming], metrics: SpeechRecognitionMetrics?)
}

public extension SpeechRecognizing {
    func events(
        for input: AudioInput,
        language: WhisperLanguage
    ) async -> AsyncThrowingStream<SpeechRecognitionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let output = try await transcribe(input, language: language)
                    for diagnostic in output.diagnostics { continuation.yield(.diagnostic(diagnostic)) }
                    for segment in output.segments { continuation.yield(.segment(segment)) }
                    continuation.yield(.completed(timings: output.timings, metrics: output.metrics))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public struct SpeechRecognitionOutput: Sendable {
    public let segments: [RecognizedSegment]
    public let diagnostics: [DiagnosticEvent]
    public let timings: [StageTiming]
    public let metrics: SpeechRecognitionMetrics?

    public init(
        segments: [RecognizedSegment],
        diagnostics: [DiagnosticEvent] = [],
        timings: [StageTiming] = [],
        metrics: SpeechRecognitionMetrics? = nil
    ) {
        self.segments = segments
        self.diagnostics = diagnostics
        self.timings = timings
        self.metrics = metrics
    }
}

public struct SpeechRecognitionMetrics: Equatable, Sendable {
    public let audioDurationSeconds: Double
    public let sdkInputAudioSeconds: Double
    public let realTimeFactor: Double
    public let selectedLanguage: WhisperLanguage
    public let languageConfidence: Double?
    public let automaticLanguageDetection: Bool
    public let segmentCount: Int
    public let lastSegmentEndSeconds: Double?
    public let confidenceDistribution: ProbabilityDistributionSummary?
    public let noSpeechProbabilityDistribution: ProbabilityDistributionSummary?
    public let compressionRatioDistribution: ProbabilityDistributionSummary?
    public let peakResidentMemoryBytes: UInt64?
    public let physicalFootprintBytes: UInt64?
    public let segmentsBeyondAudioDurationCount: Int
    public let maximumTimestampOverflowSeconds: Double?

    public init(
        audioDurationSeconds: Double,
        sdkInputAudioSeconds: Double,
        realTimeFactor: Double,
        selectedLanguage: WhisperLanguage,
        languageConfidence: Double?,
        automaticLanguageDetection: Bool,
        segmentCount: Int = 0,
        lastSegmentEndSeconds: Double? = nil,
        confidenceDistribution: ProbabilityDistributionSummary? = nil,
        noSpeechProbabilityDistribution: ProbabilityDistributionSummary? = nil,
        compressionRatioDistribution: ProbabilityDistributionSummary? = nil,
        peakResidentMemoryBytes: UInt64? = nil,
        physicalFootprintBytes: UInt64? = nil,
        segmentsBeyondAudioDurationCount: Int = 0,
        maximumTimestampOverflowSeconds: Double? = nil
    ) {
        self.audioDurationSeconds = audioDurationSeconds
        self.sdkInputAudioSeconds = sdkInputAudioSeconds
        self.realTimeFactor = realTimeFactor
        self.selectedLanguage = selectedLanguage
        self.languageConfidence = languageConfidence
        self.automaticLanguageDetection = automaticLanguageDetection
        self.segmentCount = segmentCount
        self.lastSegmentEndSeconds = lastSegmentEndSeconds
        self.confidenceDistribution = confidenceDistribution
        self.noSpeechProbabilityDistribution = noSpeechProbabilityDistribution
        self.compressionRatioDistribution = compressionRatioDistribution
        self.peakResidentMemoryBytes = peakResidentMemoryBytes
        self.physicalFootprintBytes = physicalFootprintBytes
        self.segmentsBeyondAudioDurationCount = segmentsBeyondAudioDurationCount
        self.maximumTimestampOverflowSeconds = maximumTimestampOverflowSeconds
    }

    public var diagnosticDetails: DiagnosticDetails {
        DiagnosticDetails(
            audioDurationSeconds: audioDurationSeconds,
            realTimeFactor: realTimeFactor,
            sdkInputAudioSeconds: sdkInputAudioSeconds,
            selectedLanguage: selectedLanguage,
            languageConfidence: languageConfidence,
            automaticLanguageDetection: automaticLanguageDetection,
            segmentCount: segmentCount,
            lastSegmentEndSeconds: lastSegmentEndSeconds,
            confidenceDistribution: confidenceDistribution,
            noSpeechProbabilityDistribution: noSpeechProbabilityDistribution,
            compressionRatioDistribution: compressionRatioDistribution,
            peakResidentMemoryBytes: peakResidentMemoryBytes,
            physicalFootprintBytes: physicalFootprintBytes,
            segmentsBeyondAudioDurationCount: segmentsBeyondAudioDurationCount,
            maximumTimestampOverflowSeconds: maximumTimestampOverflowSeconds
        )
    }
}

public struct TranslationRequest: Sendable {
    public let segment: RecognizedSegment
    public let recentContext: [TranscriptTurn]

    public init(segment: RecognizedSegment, recentContext: [TranscriptTurn]) {
        self.segment = segment
        self.recentContext = recentContext
    }
}

public protocol TextTranslating: Sendable {
    func translate(_ request: TranslationRequest) async throws -> TranslationResponse
}

/// Keeps source-only commands on the production pipeline without introducing
/// an external translation dependency. Callers may intentionally omit the
/// returned identity text from presentation.
public struct PassThroughTranslator: TextTranslating {
    public init() {}

    public func translate(_ request: TranslationRequest) async throws -> TranslationResponse {
        TranslationResponse(englishText: request.segment.sourceText)
    }
}

public protocol SpeakerDiarizing: Sendable {
    func assignSpeakers(
        to segments: [RecognizedSegment],
        in audioFile: URL,
        expectedSpeakerCount: Int?
    ) async throws -> [RecognizedSegment]
}

public protocol TranscriptFormatting: Sendable {
    func format(_ turn: TranscriptTurn) -> String
}
