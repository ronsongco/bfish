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

    public init(
        audioDurationSeconds: Double,
        sdkInputAudioSeconds: Double,
        realTimeFactor: Double,
        selectedLanguage: WhisperLanguage,
        languageConfidence: Double?,
        automaticLanguageDetection: Bool
    ) {
        self.audioDurationSeconds = audioDurationSeconds
        self.sdkInputAudioSeconds = sdkInputAudioSeconds
        self.realTimeFactor = realTimeFactor
        self.selectedLanguage = selectedLanguage
        self.languageConfidence = languageConfidence
        self.automaticLanguageDetection = automaticLanguageDetection
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
