import AVFoundation
import BFishCore
import Darwin
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
    case incrementalStreamStalled

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
        case .incrementalStreamStalled:
            "Incremental audio chunking made no forward progress."
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
            languageConfidence = detection.langProbs[detection.language]
                .flatMap(Self.languageConfidence(fromLogProbability:))
        } else {
            language = requestedLanguage
            languageConfidence = 1
        }

        let decodingOptions = DecodingOptions(
            task: .transcribe,
            language: language.rawValue,
            detectLanguage: false,
            skipSpecialTokens: true,
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
        let timestampOverflows = mapped.segments
            .map { $0.timeRange.end - audioDuration }
            .filter { $0 > 0 }
        let metrics = SpeechRecognitionMetrics(
            audioDurationSeconds: audioDuration,
            sdkInputAudioSeconds: sdkInputAudioSeconds,
            realTimeFactor: recognitionMilliseconds / 1_000 / audioDuration,
            selectedLanguage: language,
            languageConfidence: languageConfidence,
            automaticLanguageDetection: requestedLanguage == .automatic,
            segmentCount: mapped.segments.count,
            lastSegmentEndSeconds: mapped.segments.map(\.timeRange.end).max(),
            confidenceDistribution: Self.distribution(mapped.segments.compactMap(\.confidence)),
            noSpeechProbabilityDistribution: Self.distribution(mapped.segments.compactMap(\.noSpeechProbability)),
            compressionRatioDistribution: Self.distribution(mapped.segments.compactMap(\.compressionRatio)),
            peakResidentMemoryBytes: Self.peakResidentMemoryBytes(),
            physicalFootprintBytes: Self.physicalFootprintBytes(),
            segmentsBeyondAudioDurationCount: timestampOverflows.count,
            maximumTimestampOverflowSeconds: timestampOverflows.max()
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

    public func events(
        for input: AudioInput,
        language requestedLanguage: WhisperLanguage
    ) async -> AsyncThrowingStream<SpeechRecognitionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.produceFinalizedEvents(
                        input: input,
                        requestedLanguage: requestedLanguage,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func produceFinalizedEvents(
        input: AudioInput,
        requestedLanguage: WhisperLanguage,
        continuation: AsyncThrowingStream<SpeechRecognitionEvent, Error>.Continuation
    ) async throws {
        guard case let .file(audioURL) = input else { throw WhisperKitRecognizerError.unsupportedInput }
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
            language = try Self.validatedDetectedLanguage(detection.language)
            languageConfidence = detection.langProbs[detection.language]
                .flatMap(Self.languageConfidence(fromLogProbability:))
        } else {
            language = requestedLanguage
            languageConfidence = 1
        }

        let decodingOptions = DecodingOptions(
            task: .transcribe,
            language: language.rawValue,
            detectLanguage: false,
            skipSpecialTokens: true,
            wordTimestamps: true,
            chunkingStrategy: ChunkingStrategy.none
        )
        let transcriptionStart = ContinuousClock.now
        let audioFile = try AVAudioFile(
            forReading: audioURL,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let inputDuration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
        let maxChunkLength = engine.featureExtractor.windowSamples ?? Constants.defaultWindowSamples
        let chunker = VADAudioChunker(vad: engine.voiceActivityDetector ?? EnergyVAD())
        var currentTime = 0.0
        var audioBuffer: [Float] = []
        var bufferStartSample = 0
        var sdkInputAudioSeconds = 0.0
        var sdkFullPipeline = 0.0
        var sdkAudioLoading = 0.0
        var sdkAudioProcessing = 0.0
        var sdkEncoding = 0.0
        var sdkDecoding = 0.0
        var sdkModelLoading = 0.0
        var segmentCount = 0
        var lastSegmentEnd: Double?
        var timestampOverflows: [Double] = []
        var confidences: [Double] = []
        var noSpeechProbabilities: [Double] = []
        var compressionRatios: [Double] = []
        var windowIndex = 0

        while true {
            try Task.checkCancellation()
            while audioBuffer.count <= maxChunkLength && currentTime < inputDuration {
                let chunkEnd = min(currentTime + 30, inputDuration)
                try autoreleasepool {
                    let buffer = try AudioProcessor.loadAudio(
                        fromFile: audioFile,
                        channelMode: .sumChannels(nil),
                        startTime: currentTime,
                        endTime: chunkEnd
                    )
                    audioBuffer.append(contentsOf: AudioProcessor.convertBufferToArray(buffer: buffer))
                }
                currentTime = chunkEnd
            }

            if audioBuffer.isEmpty { break }
            let atEOF = currentTime >= inputDuration
            let chunks = try await chunker.chunkAll(
                audioArray: audioBuffer,
                maxChunkLength: maxChunkLength,
                decodeOptions: nil
            )
            let finalizedChunks = atEOF
                ? Array(chunks)
                : chunks.filter { $0.seekOffsetIndex + maxChunkLength <= audioBuffer.count }
            var consumed = 0

            for chunk in finalizedChunks {
                try Task.checkCancellation()
                let absoluteOffset = bufferStartSample + chunk.seekOffsetIndex
                let seekTime = Float(absoluteOffset) / Float(WhisperKit.sampleRate)
                let rawResults = try await engine.transcribe(
                    audioArray: chunk.audioSamples,
                    audioArrayOffset: 0,
                    decodeOptions: decodingOptions
                )
                for result in rawResults {
                    result.segments = result.segments.map {
                        TranscriptionUtilities.updateSegmentTimings(
                            segment: $0,
                            seekOffsetIndex: absoluteOffset
                        )
                    }
                    result.seekTime = seekTime
                }
                let mapped = WhisperKitResultMapper.map(
                    results: rawResults,
                    language: language,
                    languageConfidence: languageConfidence,
                    timeline: timeline,
                    windowIndexBase: windowIndex
                )
                for diagnostic in mapped.diagnostics { continuation.yield(.diagnostic(diagnostic)) }
                for segment in mapped.segments {
                    segmentCount += 1
                    lastSegmentEnd = max(lastSegmentEnd ?? 0, segment.timeRange.end)
                    if segment.timeRange.end > audioDuration {
                        timestampOverflows.append(segment.timeRange.end - audioDuration)
                    }
                    if let confidence = segment.confidence { confidences.append(confidence) }
                    if let probability = segment.noSpeechProbability { noSpeechProbabilities.append(probability) }
                    if let ratio = segment.compressionRatio { compressionRatios.append(ratio) }
                    continuation.yield(.segment(segment))
                }
                for result in rawResults {
                    sdkInputAudioSeconds += result.timings.inputAudioSeconds
                    sdkFullPipeline += result.timings.fullPipeline
                    sdkAudioLoading += result.timings.audioLoading
                    sdkAudioProcessing += result.timings.audioProcessing
                    sdkEncoding += result.timings.encoding
                    sdkDecoding += result.timings.decodingLoop
                    sdkModelLoading = max(sdkModelLoading, result.timings.modelLoading)
                }
                windowIndex += rawResults.count
                consumed = chunk.seekOffsetIndex + chunk.audioSamples.count
            }

            if atEOF { break }
            guard consumed > 0 else { throw WhisperKitRecognizerError.incrementalStreamStalled }
            bufferStartSample += consumed
            audioBuffer = Array(audioBuffer[consumed...])
        }

        let transcriptionMilliseconds = Self.milliseconds(since: transcriptionStart)
        let recognitionMilliseconds = Self.milliseconds(since: recognitionStart)
        let metrics = SpeechRecognitionMetrics(
            audioDurationSeconds: audioDuration,
            sdkInputAudioSeconds: sdkInputAudioSeconds,
            realTimeFactor: recognitionMilliseconds / 1_000 / audioDuration,
            selectedLanguage: language,
            languageConfidence: languageConfidence,
            automaticLanguageDetection: requestedLanguage == .automatic,
            segmentCount: segmentCount,
            lastSegmentEndSeconds: lastSegmentEnd,
            confidenceDistribution: Self.distribution(confidences),
            noSpeechProbabilityDistribution: Self.distribution(noSpeechProbabilities),
            compressionRatioDistribution: Self.distribution(compressionRatios),
            peakResidentMemoryBytes: Self.peakResidentMemoryBytes(),
            physicalFootprintBytes: Self.physicalFootprintBytes(),
            segmentsBeyondAudioDurationCount: timestampOverflows.count,
            maximumTimestampOverflowSeconds: timestampOverflows.max()
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
        timings.append(contentsOf: [
            StageTiming(stage: "whisper_full_pipeline", milliseconds: sdkFullPipeline * 1_000),
            StageTiming(stage: "whisper_audio_loading", milliseconds: sdkAudioLoading * 1_000),
            StageTiming(stage: "whisper_audio_processing", milliseconds: sdkAudioProcessing * 1_000),
            StageTiming(stage: "whisper_encoding", milliseconds: sdkEncoding * 1_000),
            StageTiming(stage: "whisper_decoding", milliseconds: sdkDecoding * 1_000),
            StageTiming(stage: "whisper_sdk_model_loading", milliseconds: sdkModelLoading * 1_000),
        ])
        continuation.yield(.completed(timings: timings, metrics: metrics))
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

    static func languageConfidence(fromLogProbability logProbability: Float) -> Double? {
        guard logProbability.isFinite else { return nil }
        return min(1, max(0, exp(Double(logProbability))))
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

    static func distribution(_ values: [Double]) -> ProbabilityDistributionSummary? {
        let sorted = values.filter(\.isFinite).sorted()
        guard let minimum = sorted.first, let maximum = sorted.last else { return nil }
        func percentile(_ fraction: Double) -> Double {
            let index = Int((Double(sorted.count - 1) * fraction).rounded())
            return sorted[index]
        }
        return ProbabilityDistributionSummary(
            count: sorted.count,
            minimum: minimum,
            median: percentile(0.5),
            percentile90: percentile(0.9),
            maximum: maximum
        )
    }

    static func peakResidentMemoryBytes() -> UInt64? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0, usage.ru_maxrss >= 0 else { return nil }
        return UInt64(usage.ru_maxrss)
    }

    static func physicalFootprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info.phys_footprint
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
        timeline: CaptureTimeline,
        windowIndexBase: Int = 0
    ) -> SpeechRecognitionOutput {
        var segments: [RecognizedSegment] = []
        var diagnostics: [DiagnosticEvent] = []
        let reconciled = reconcile(results: results)
        diagnostics.append(contentsOf: reconciled.diagnostics)
        var fallbackStart: TimeInterval = 0
        var previousStart: TimeInterval?

        for (windowIndex, result) in results.enumerated() {
            diagnostics.append(windowDiagnostic(for: result, index: windowIndexBase + windowIndex))
        }
        for rawSegment in reconciled.segments {
            let mapped = mapSegment(
                start: Double(rawSegment.segment.start),
                end: Double(rawSegment.segment.end),
                text: rawSegment.segment.text,
                averageLogProbability: Double(rawSegment.segment.avgLogprob),
                noSpeechProbability: Double(rawSegment.segment.noSpeechProb),
                compressionRatio: Double(rawSegment.segment.compressionRatio),
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
                let currentStart = segment.timeRange.start
                diagnostics.append(DiagnosticEvent(
                    event: .timelineDiscontinuity,
                    segmentID: segment.id,
                    details: DiagnosticDetails(
                        errorCode: "non_monotonic_segment_start",
                        previousSegmentStartSeconds: previousStart,
                        currentSegmentStartSeconds: currentStart,
                        segmentStartDeltaSeconds: currentStart - previousStart
                    )
                ))
            }
            previousStart = segment.timeRange.start
        }

        return SpeechRecognitionOutput(
            segments: segments,
            diagnostics: diagnostics,
            timings: timingSummary(results)
        )
    }

    struct WindowedSegment {
        var segment: TranscriptionSegment
        let windowIndex: Int
    }

    static func reconcile(results: [TranscriptionResult]) -> (
        segments: [WindowedSegment],
        diagnostics: [DiagnosticEvent]
    ) {
        let tolerance = 0.001
        var candidates: [WindowedSegment] = []
        var diagnostics: [DiagnosticEvent] = []

        for (windowIndex, result) in results.enumerated() {
            let windowStart = Double(result.seekTime ?? 0)
            let windowEnd = windowStart + result.timings.inputAudioSeconds
            for source in result.segments {
                var segment = source
                let originalStart = Double(segment.start)
                let originalEnd = Double(segment.end)
                guard originalStart < windowEnd + tolerance, originalEnd > windowStart - tolerance else {
                    diagnostics.append(reconciliationDiagnostic(
                        reason: .outsideWindow,
                        originalStart: originalStart,
                        originalEnd: originalEnd
                    ))
                    continue
                }

                if let words = segment.words, !words.isEmpty {
                    let retained = words.filter {
                        Double($0.start) < windowEnd + tolerance && Double($0.end) > windowStart - tolerance
                    }
                    let removedCount = words.count - retained.count
                    if removedCount > 0 {
                        guard !retained.isEmpty else {
                            diagnostics.append(reconciliationDiagnostic(
                                reason: .outsideWindow,
                                removedWordCount: removedCount,
                                originalStart: originalStart,
                                originalEnd: originalEnd
                            ))
                            continue
                        }
                        segment.words = retained
                        segment.text = retained.map(\.word).joined()
                        segment.start = Float(max(windowStart, Double(retained.first!.start)))
                        segment.end = Float(min(windowEnd, Double(retained.last!.end)))
                        diagnostics.append(reconciliationDiagnostic(
                            reason: .wordsOutsideWindow,
                            removedWordCount: removedCount,
                            originalStart: originalStart,
                            originalEnd: originalEnd,
                            reconciledStart: Double(segment.start),
                            reconciledEnd: Double(segment.end)
                        ))
                    }
                }

                let clippedStart = max(windowStart, Double(segment.start))
                let clippedEnd = min(windowEnd, Double(segment.end))
                guard clippedEnd > clippedStart else {
                    diagnostics.append(reconciliationDiagnostic(
                        reason: .outsideWindow,
                        originalStart: originalStart,
                        originalEnd: originalEnd
                    ))
                    continue
                }
                if abs(clippedStart - Double(segment.start)) > tolerance
                    || abs(clippedEnd - Double(segment.end)) > tolerance
                {
                    segment.start = Float(clippedStart)
                    segment.end = Float(clippedEnd)
                    diagnostics.append(reconciliationDiagnostic(
                        reason: .timestampClipped,
                        originalStart: originalStart,
                        originalEnd: originalEnd,
                        reconciledStart: clippedStart,
                        reconciledEnd: clippedEnd
                    ))
                }
                candidates.append(WindowedSegment(segment: segment, windowIndex: windowIndex))
            }
        }

        candidates.sort {
            if $0.segment.start == $1.segment.start { return $0.windowIndex < $1.windowIndex }
            return $0.segment.start < $1.segment.start
        }
        var accepted: [WindowedSegment] = []
        for candidate in candidates {
            if let duplicate = accepted.last(where: {
                $0.windowIndex != candidate.windowIndex
                    && normalizedText($0.segment.text) == normalizedText(candidate.segment.text)
                    && candidate.segment.start < $0.segment.end
                    && candidate.segment.end > $0.segment.start
            }) {
                diagnostics.append(reconciliationDiagnostic(
                    reason: .duplicateOverlap,
                    removedWordCount: candidate.segment.words?.count,
                    originalStart: Double(candidate.segment.start),
                    originalEnd: Double(candidate.segment.end),
                    reconciledStart: Double(duplicate.segment.start),
                    reconciledEnd: Double(duplicate.segment.end)
                ))
                continue
            }
            accepted.append(candidate)
        }
        return (accepted, diagnostics)
    }

    private static func normalizedText(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping
            .lowercased()
            .filter { !$0.isWhitespace && !$0.isPunctuation }
    }

    private static func reconciliationDiagnostic(
        reason: SegmentReconciliationReason,
        removedWordCount: Int? = nil,
        originalStart: Double,
        originalEnd: Double,
        reconciledStart: Double? = nil,
        reconciledEnd: Double? = nil
    ) -> DiagnosticEvent {
        DiagnosticEvent(
            event: .segmentReconciled,
            details: DiagnosticDetails(
                reconciliationReason: reason,
                removedWordCount: removedWordCount,
                originalSegmentStartSeconds: originalStart,
                originalSegmentEndSeconds: originalEnd,
                reconciledSegmentStartSeconds: reconciledStart,
                reconciledSegmentEndSeconds: reconciledEnd
            )
        )
    }

    static func windowDiagnostic(for result: TranscriptionResult, index: Int) -> DiagnosticEvent {
        let windowStart = Double(result.seekTime ?? 0)
        let windowDuration = result.timings.inputAudioSeconds
        let windowEnd = windowStart + windowDuration
        let firstSegmentStart = result.segments.map { Double($0.start) }.min()
        let lastSegmentEnd = result.segments.map { Double($0.end) }.max()
        let overflow = lastSegmentEnd.map { max(0, $0 - windowEnd) }
        return DiagnosticEvent(
            event: .recognitionWindow,
            details: DiagnosticDetails(
                windowIndex: index,
                windowStartSeconds: windowStart,
                windowDurationSeconds: windowDuration,
                windowEndSeconds: windowEnd,
                firstSegmentStartSeconds: firstSegmentStart,
                lastSegmentEndSecondsInWindow: lastSegmentEnd,
                windowTimestampOverflowSeconds: overflow
            )
        )
    }

    static func mapSegment(
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        averageLogProbability: Double,
        noSpeechProbability: Double,
        compressionRatio: Double = 1,
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
            noSpeechProbability: repairedNoSpeechProbability,
            compressionRatio: compressionRatio.isFinite ? max(0, compressionRatio) : nil
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

    static func timingSummary(_ results: [TranscriptionResult]) -> [StageTiming] {
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
