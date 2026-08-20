import BFishCore
import Foundation
import WhisperKit

public struct WhisperKitRecognizerConfiguration: Sendable {
    public let model: String
    public let modelFolder: URL?
    public let downloadBase: URL
    public let incrementalLoading: Bool

    public init(
        model: String = "tiny",
        modelFolder: URL? = nil,
        downloadBase: URL? = nil,
        incrementalLoading: Bool = false
    ) {
        self.model = model
        self.modelFolder = modelFolder
        self.downloadBase = downloadBase ?? Self.defaultDownloadBase
        self.incrementalLoading = incrementalLoading
    }

    public static var defaultDownloadBase: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "bfish/Models", directoryHint: .isDirectory)
    }
}

public enum WhisperKitRecognizerError: Error, LocalizedError, Sendable {
    case unsupportedInput
    case fileNotFound(String)
    case unsupportedLanguage(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedInput:
            "WhisperKit recognition currently supports audio files only."
        case let .fileNotFound(path):
            "Audio file not found: \(path)"
        case let .unsupportedLanguage(language):
            "WhisperKit detected unsupported language token: \(language)"
        }
    }
}

public actor WhisperKitRecognizer: SpeechRecognizing {
    private let configuration: WhisperKitRecognizerConfiguration
    private var whisperKit: WhisperKit?

    public init(configuration: WhisperKitRecognizerConfiguration = .init()) {
        self.configuration = configuration
    }

    public func transcribe(
        _ input: AudioInput,
        language requestedLanguage: WhisperLanguage
    ) async throws -> SpeechRecognitionOutput {
        guard case let .file(audioURL) = input else {
            throw WhisperKitRecognizerError.unsupportedInput
        }
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw WhisperKitRecognizerError.fileNotFound(audioURL.path)
        }

        let timeline = CaptureTimeline(startedAt: Date())
        let engine = try await loadEngine()
        let language: WhisperLanguage
        let languageConfidence: Double?
        if requestedLanguage == .automatic {
            let detection = try await engine.detectLanguage(audioPath: audioURL.path)
            guard let detected = WhisperLanguage(rawValue: detection.language), detected != .automatic else {
                throw WhisperKitRecognizerError.unsupportedLanguage(detection.language)
            }
            language = detected
            languageConfidence = detection.langProbs[detection.language].map(Double.init)
        } else {
            language = requestedLanguage
            languageConfidence = 1
        }

        let decodingOptions = DecodingOptions(
            task: .transcribe,
            language: language.rawValue,
            detectLanguage: false,
            wordTimestamps: true,
            chunkingStrategy: .vad
        )
        let loadingMode: AudioInputOptions.AudioLoadingMode = configuration.incrementalLoading ? .incremental : .fullFile
        let results = try await engine.transcribe(
            audioPath: audioURL.path,
            audioInputOptions: AudioInputOptions(audioLoadingMode: loadingMode),
            decodeOptions: decodingOptions
        )

        return WhisperKitResultMapper.map(
            results: results,
            language: language,
            languageConfidence: languageConfidence,
            timeline: timeline
        )
    }

    private func loadEngine() async throws -> WhisperKit {
        if let whisperKit { return whisperKit }
        try FileManager.default.createDirectory(
            at: configuration.downloadBase,
            withIntermediateDirectories: true
        )
        let config = WhisperKitConfig(
            model: configuration.model,
            downloadBase: configuration.downloadBase,
            modelFolder: configuration.modelFolder?.path
        )
        let loaded = try await WhisperKit(config)
        whisperKit = loaded
        return loaded
    }
}

enum WhisperKitResultMapper {
    static func map(
        results: [TranscriptionResult],
        language: WhisperLanguage,
        languageConfidence: Double?,
        timeline: CaptureTimeline
    ) -> SpeechRecognitionOutput {
        var segments: [RecognizedSegment] = []
        var diagnostics: [DiagnosticEvent] = []
        var fallbackStart: TimeInterval = 0

        for result in results {
            for rawSegment in result.segments {
                let mapped = mapSegment(
                    start: Double(rawSegment.start),
                    end: Double(rawSegment.end),
                    text: rawSegment.text,
                    averageLogProbability: Double(rawSegment.avgLogprob),
                    noSpeechProbability: Double(rawSegment.noSpeechProb),
                    language: language,
                    languageConfidence: languageConfidence,
                    timeline: timeline,
                    fallbackStart: fallbackStart
                )
                let segment = mapped.segment
                segments.append(segment)
                fallbackStart = segment.timeRange.end
                if let diagnostic = mapped.diagnostic { diagnostics.append(diagnostic) }
            }
        }

        return SpeechRecognitionOutput(
            segments: segments,
            diagnostics: diagnostics,
            timings: timingSummary(results)
        )
    }

    static func mapSegment(
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        averageLogProbability: Double,
        noSpeechProbability: Double,
        language: WhisperLanguage,
        languageConfidence: Double?,
        timeline: CaptureTimeline,
        fallbackStart: TimeInterval
    ) -> (segment: RecognizedSegment, diagnostic: DiagnosticEvent?) {
        let repaired = AudioTimeRange.repairing(start: start, end: end, fallbackStart: fallbackStart)
        let segment = RecognizedSegment(
            timeRange: repaired.timeRange,
            timeline: timeline,
            language: language,
            sourceText: text.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: min(1, max(0, exp(averageLogProbability))),
            languageConfidence: languageConfidence,
            noSpeechProbability: min(1, max(0, noSpeechProbability))
        )
        let diagnostic = repaired.reason.map { reason in
            DiagnosticEvent(
                event: .timestampRepaired,
                segmentID: segment.id,
                details: DiagnosticDetails(timestampRepairReason: reason)
            )
        }
        return (segment, diagnostic)
    }

    private static func timingSummary(_ results: [TranscriptionResult]) -> [StageTiming] {
        guard !results.isEmpty else { return [] }
        return [
            StageTiming(stage: "whisper_full_pipeline", milliseconds: results.reduce(0) { $0 + $1.timings.fullPipeline } * 1_000),
            StageTiming(stage: "whisper_audio_loading", milliseconds: results.reduce(0) { $0 + $1.timings.audioLoading } * 1_000),
            StageTiming(stage: "whisper_audio_processing", milliseconds: results.reduce(0) { $0 + $1.timings.audioProcessing } * 1_000),
            StageTiming(stage: "whisper_encoding", milliseconds: results.reduce(0) { $0 + $1.timings.encoding } * 1_000),
            StageTiming(stage: "whisper_decoding", milliseconds: results.reduce(0) { $0 + $1.timings.decodingLoop } * 1_000),
        ]
    }
}
