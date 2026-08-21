import AVFoundation
import BFishCore
import Foundation
import WhisperKit

public enum WhisperKitStatus: Equatable, Sendable {
    case resolving
    case downloading(percent: Int)
    case filesReady
    case loading
    case loaded
    case alreadyResident
}

public extension WhisperKitStatus {
    var diagnosticModelStatus: ModelStatus {
        switch self {
        case .resolving: .resolving
        case .downloading: .downloading
        case .filesReady: .filesReady
        case .loading: .loading
        case .loaded: .loaded
        case .alreadyResident: .alreadyResident
        }
    }

    var progressPercentage: Int? {
        guard case let .downloading(percent) = self else { return nil }
        return percent
    }
}

public typealias WhisperKitStatusHandler = @Sendable (WhisperKitStatus) -> Void

public struct WhisperKitRecognizerConfiguration: Sendable {
    public let model: String
    public let modelFolder: URL?
    public let downloadBase: URL
    public let incrementalLoading: Bool
    public let statusHandler: WhisperKitStatusHandler?

    public init(
        model: String = "tiny",
        modelFolder: URL? = nil,
        downloadBase: URL? = nil,
        incrementalLoading: Bool = false,
        statusHandler: WhisperKitStatusHandler? = nil
    ) {
        self.model = model
        self.modelFolder = modelFolder
        self.downloadBase = downloadBase ?? Self.defaultDownloadBase
        self.incrementalLoading = incrementalLoading
        self.statusHandler = statusHandler
    }

    public static var defaultDownloadBase: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "bfish/Models", directoryHint: .isDirectory)
    }
}

public enum WhisperKitRecognizerError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedInput
    case fileNotFound(String)
    case unsupportedLanguage(String)
    case invalidAudioDuration(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedInput:
            "WhisperKit recognition currently supports audio files only."
        case let .fileNotFound(path):
            "Audio file not found: \(path)"
        case let .unsupportedLanguage(language):
            "WhisperKit detected unsupported language token '\(language)'. The SDK or model language table may have changed; update bfish or use --language as a temporary override."
        case let .invalidAudioDuration(path):
            "Unable to determine a positive audio duration for: \(path)"
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
        let audioDuration = try Self.audioDuration(for: audioURL)
        let loadedEngine = try await loadEngine()
        let engine = loadedEngine.engine
        let recognitionStart = ContinuousClock.now
        let language: WhisperLanguage
        let languageConfidence: Double?
        if requestedLanguage == .automatic {
            let detection = try await engine.detectLanguage(audioPath: audioURL.path)
            let detected = try Self.validatedDetectedLanguage(detection.language)
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
        let transcriptionStart = ContinuousClock.now
        let results = try await engine.transcribe(
            audioPath: audioURL.path,
            audioInputOptions: AudioInputOptions(audioLoadingMode: loadingMode),
            decodeOptions: decodingOptions
        )
        let transcriptionMilliseconds = Self.milliseconds(since: transcriptionStart)
        let recognitionMilliseconds = Self.milliseconds(since: recognitionStart)

        let mapped = WhisperKitResultMapper.map(
            results: results,
            language: language,
            languageConfidence: languageConfidence,
            timeline: timeline
        )
        let sdkInputAudioSeconds = results.reduce(0) { $0 + $1.timings.inputAudioSeconds }
        let metrics = SpeechRecognitionMetrics(
            audioDurationSeconds: audioDuration,
            sdkInputAudioSeconds: sdkInputAudioSeconds,
            realTimeFactor: recognitionMilliseconds / 1_000 / audioDuration
        )
        var timings = [
            StageTiming(stage: "whisper_recognition_wall", milliseconds: recognitionMilliseconds),
            StageTiming(stage: "whisper_transcription_wall", milliseconds: transcriptionMilliseconds),
            StageTiming(stage: "input_audio", milliseconds: audioDuration * 1_000),
            StageTiming(stage: "whisper_sdk_input_audio", milliseconds: sdkInputAudioSeconds * 1_000),
        ]
        if let acquisition = loadedEngine.acquisitionMilliseconds {
            timings.insert(StageTiming(stage: "whisper_model_acquisition", milliseconds: acquisition), at: 0)
        }
        if let load = loadedEngine.loadMilliseconds {
            timings.insert(StageTiming(stage: "whisper_model_load_wall", milliseconds: load), at: 1)
        }
        return SpeechRecognitionOutput(
            segments: mapped.segments,
            diagnostics: mapped.diagnostics,
            timings: timings + mapped.timings,
            metrics: metrics
        )
    }

    private func loadEngine() async throws -> (
        engine: WhisperKit,
        acquisitionMilliseconds: Double?,
        loadMilliseconds: Double?
    ) {
        if let whisperKit {
            configuration.statusHandler?(.alreadyResident)
            return (whisperKit, nil, nil)
        }
        try FileManager.default.createDirectory(
            at: configuration.downloadBase,
            withIntermediateDirectories: true
        )
        let acquisitionStart = ContinuousClock.now
        let modelFolder: URL
        if let configuredFolder = configuration.modelFolder {
            configuration.statusHandler?(.filesReady)
            modelFolder = configuredFolder
        } else {
            configuration.statusHandler?(.resolving)
            let statusHandler = configuration.statusHandler
            let progressReporter = ProgressReporter(statusHandler: statusHandler)
            modelFolder = try await WhisperKit.download(
                variant: configuration.model,
                downloadBase: configuration.downloadBase
            ) { progress in
                progressReporter.report(progress)
            }
            configuration.statusHandler?(.filesReady)
        }
        let acquisitionMilliseconds = Self.milliseconds(since: acquisitionStart)
        configuration.statusHandler?(.loading)
        let loadStart = ContinuousClock.now
        let config = WhisperKitConfig(
            downloadBase: configuration.downloadBase,
            modelFolder: modelFolder.path,
            download: false
        )
        let loaded = try await WhisperKit(config)
        let loadMilliseconds = Self.milliseconds(since: loadStart)
        configuration.statusHandler?(.loaded)
        whisperKit = loaded
        return (loaded, acquisitionMilliseconds, loadMilliseconds)
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let components = start.duration(to: .now).components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    static func validatedDetectedLanguage(_ rawValue: String) throws -> WhisperLanguage {
        guard let language = WhisperLanguage(rawValue: rawValue), language != .automatic else {
            throw WhisperKitRecognizerError.unsupportedLanguage(rawValue)
        }
        return language
    }

    static func audioDuration(for url: URL) throws -> Double {
        let audioFile = try AVAudioFile(forReading: url)
        let sampleRate = audioFile.fileFormat.sampleRate
        let duration = sampleRate > 0 ? Double(audioFile.length) / sampleRate : 0
        guard duration.isFinite, duration > 0 else {
            throw WhisperKitRecognizerError.invalidAudioDuration(url.path)
        }
        return duration
    }
}

final class ProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastPercentage: Int?
    private let statusHandler: WhisperKitStatusHandler?

    init(statusHandler: WhisperKitStatusHandler?) {
        self.statusHandler = statusHandler
    }

    func report(_ progress: Progress) {
        let percentage = min(100, max(0, Int((progress.fractionCompleted * 100).rounded())))
        lock.lock()
        guard percentage != lastPercentage else {
            lock.unlock()
            return
        }
        lastPercentage = percentage
        lock.unlock()
        statusHandler?(.downloading(percent: percentage))
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
        var previousStart: TimeInterval?

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
                diagnostics.append(contentsOf: mapped.diagnostics)
                if let previousStart, segment.timeRange.start < previousStart {
                    diagnostics.append(DiagnosticEvent(
                        event: .timelineDiscontinuity,
                        segmentID: segment.id,
                        details: DiagnosticDetails(errorCode: "non_monotonic_segment_start")
                    ))
                }
                previousStart = segment.timeRange.start
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
    ) -> (segment: RecognizedSegment, diagnostics: [DiagnosticEvent]) {
        let repaired = AudioTimeRange.repairing(start: start, end: end, fallbackStart: fallbackStart)
        let rawConfidence = exp(averageLogProbability)
        let repairedConfidence: Double
        let confidenceWasRepaired: Bool
        if averageLogProbability.isFinite, rawConfidence.isFinite, (0...1).contains(rawConfidence) {
            repairedConfidence = rawConfidence
            confidenceWasRepaired = false
        } else {
            repairedConfidence = rawConfidence.isNaN ? 0 : min(1, max(0, rawConfidence))
            confidenceWasRepaired = true
        }
        let repairedNoSpeechProbability: Double
        let probabilityWasRepaired: Bool
        if noSpeechProbability.isFinite, (0...1).contains(noSpeechProbability) {
            repairedNoSpeechProbability = noSpeechProbability
            probabilityWasRepaired = false
        } else {
            repairedNoSpeechProbability = noSpeechProbability.isFinite
                ? min(1, max(0, noSpeechProbability))
                : 1
            probabilityWasRepaired = true
        }
        let segment = RecognizedSegment(
            timeRange: repaired.timeRange,
            timeline: timeline,
            language: language,
            sourceText: text.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: repairedConfidence,
            languageConfidence: languageConfidence,
            noSpeechProbability: repairedNoSpeechProbability
        )
        var diagnostics: [DiagnosticEvent] = []
        if let reason = repaired.reason {
            diagnostics.append(DiagnosticEvent(
                event: .timestampRepaired,
                segmentID: segment.id,
                details: DiagnosticDetails(timestampRepairReason: reason)
            ))
        }
        if probabilityWasRepaired {
            diagnostics.append(DiagnosticEvent(
                event: .probabilityRepaired,
                segmentID: segment.id,
                details: DiagnosticDetails(probabilityRepairField: .noSpeechProbability)
            ))
        }
        if confidenceWasRepaired {
            diagnostics.append(DiagnosticEvent(
                event: .probabilityRepaired,
                segmentID: segment.id,
                details: DiagnosticDetails(probabilityRepairField: .confidence)
            ))
        }
        return (segment, diagnostics)
    }

    private static func timingSummary(_ results: [TranscriptionResult]) -> [StageTiming] {
        guard !results.isEmpty else { return [] }
        return [
            StageTiming(stage: "whisper_full_pipeline", milliseconds: results.reduce(0) { $0 + $1.timings.fullPipeline } * 1_000),
            StageTiming(stage: "whisper_audio_loading", milliseconds: results.reduce(0) { $0 + $1.timings.audioLoading } * 1_000),
            StageTiming(stage: "whisper_audio_processing", milliseconds: results.reduce(0) { $0 + $1.timings.audioProcessing } * 1_000),
            StageTiming(stage: "whisper_encoding", milliseconds: results.reduce(0) { $0 + $1.timings.encoding } * 1_000),
            StageTiming(stage: "whisper_decoding", milliseconds: results.reduce(0) { $0 + $1.timings.decodingLoop } * 1_000),
            StageTiming(stage: "whisper_sdk_model_loading", milliseconds: results.map(\.timings.modelLoading).max()! * 1_000),
        ]
    }
}
