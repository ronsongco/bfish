import Testing
import BFishCore
import Foundation
import WhisperKit
@testable import BFishWhisperKit

@Test func configurationHasStableApplicationSupportDefault() {
    let path = WhisperKitRecognizerConfiguration.defaultDownloadBase.path
    #expect(path.hasSuffix("/Application Support/bfish/Models"))
}

@Test func mapperRepairsModelTimestampsAndPreservesRecognitionMetadata() {
    let timeline = CaptureTimeline()
    let mapped = WhisperKitResultMapper.mapSegment(
        start: .nan,
        end: 8,
        text: "  こんにちは  ",
        averageLogProbability: -0.5,
        noSpeechProbability: 1.2,
        language: .japanese,
        languageConfidence: 0.91,
        timeline: timeline,
        fallbackStart: 7
    )

    #expect(mapped.segment.timeRange.start == 7)
    #expect(mapped.segment.timeRange.end == 7)
    #expect(mapped.segment.sourceText == "こんにちは")
    #expect(mapped.segment.language == .japanese)
    #expect(mapped.segment.languageConfidence == 0.91)
    #expect(mapped.segment.noSpeechProbability == 1)
    #expect(mapped.diagnostics.map(\.event) == [.timestampRepaired, .probabilityRepaired])
    #expect(mapped.diagnostics[0].details?.timestampRepairReason == .nonFinite)
    #expect(mapped.diagnostics[1].details?.probabilityRepairField == .noSpeechProbability)
}

@Test func mapperPreservesTimelineAndOrdersNonMonotonicResults() {
    let timeline = CaptureTimeline()
    var timings = TranscriptionTimings(fullPipeline: 1)
    timings.inputAudioSeconds = 20
    let results = [
        TranscriptionResult(
            text: "first",
            segments: [TranscriptionSegment(start: 10, end: 11, text: "first")],
            language: "ja",
            timings: timings
        ),
        TranscriptionResult(
            text: "second",
            segments: [TranscriptionSegment(start: 2, end: 3, text: "second")],
            language: "ja",
            timings: timings
        ),
    ]

    let output = WhisperKitResultMapper.map(
        results: results,
        language: .japanese,
        languageConfidence: 0.9,
        timeline: timeline
    )

    #expect(output.segments.count == 2)
    #expect(output.segments.allSatisfy { $0.timeline == timeline })
    #expect(output.segments.map(\.timeRange.start) == [2, 10])
    #expect(!output.diagnostics.contains { $0.event == .timelineDiscontinuity })
}

@Test func probabilityDistributionProvidesStableCalibrationSummary() {
    let summary = WhisperKitRecognizer.distribution([0.1, 0.3, 0.2, 0.9, .nan])

    #expect(summary == ProbabilityDistributionSummary(
        count: 4,
        minimum: 0.1,
        median: 0.3,
        percentile90: 0.9,
        maximum: 0.9
    ))
    #expect(WhisperKitRecognizer.distribution([]) == nil)
}

@Test func mapperReportsNonFiniteConfidenceRepair() {
    let mapped = WhisperKitResultMapper.mapSegment(
        start: 0,
        end: 1,
        text: "test",
        averageLogProbability: .nan,
        noSpeechProbability: 0.1,
        language: .english,
        languageConfidence: 1,
        timeline: CaptureTimeline(),
        fallbackStart: 0
    )

    #expect(mapped.segment.confidence == 0)
    #expect(mapped.diagnostics.contains {
        $0.event == .probabilityRepaired && $0.details?.probabilityRepairField == .confidence
    })
}

@Test func windowDiagnosticExposesChunkExtentWithoutTranscriptContent() throws {
    var timings = TranscriptionTimings(fullPipeline: 1)
    timings.inputAudioSeconds = 20
    let result = TranscriptionResult(
        text: "private aggregate text",
        segments: [TranscriptionSegment(start: 100, end: 123, text: "private segment")],
        language: "ja",
        timings: timings,
        seekTime: 100
    )

    let diagnostic = WhisperKitResultMapper.windowDiagnostic(for: result, index: 4)
    let json = String(decoding: try diagnostic.jsonLine(), as: UTF8.self)

    #expect(diagnostic.event == .recognitionWindow)
    #expect(diagnostic.details?.windowIndex == 4)
    #expect(diagnostic.details?.windowStartSeconds == 100)
    #expect(diagnostic.details?.windowEndSeconds == 120)
    #expect(diagnostic.details?.windowTimestampOverflowSeconds == 3)
    #expect(!json.contains("private"))
}

@Test func reconciliationUsesWindowAndWordExtentsToRemoveOverflow() {
    var firstTimings = TranscriptionTimings(fullPipeline: 1)
    firstTimings.inputAudioSeconds = 10
    var secondTimings = TranscriptionTimings(fullPipeline: 1)
    secondTimings.inputAudioSeconds = 10
    let results = [
        TranscriptionResult(
            text: "kept duplicate",
            segments: [TranscriptionSegment(
                start: 8,
                end: 12,
                text: "kept duplicate",
                words: [
                    WordTiming(word: "kept", tokens: [1], start: 8, end: 9, probability: 0.9),
                    WordTiming(word: "duplicate", tokens: [2], start: 10.5, end: 11.5, probability: 0.9),
                ]
            )],
            language: "en",
            timings: firstTimings,
            seekTime: 0
        ),
        TranscriptionResult(
            text: "duplicate next",
            segments: [TranscriptionSegment(
                start: 10.5,
                end: 13,
                text: "duplicate next",
                words: [
                    WordTiming(word: "duplicate", tokens: [2], start: 10.5, end: 11.5, probability: 0.9),
                    WordTiming(word: "next", tokens: [3], start: 12, end: 13, probability: 0.9),
                ]
            )],
            language: "en",
            timings: secondTimings,
            seekTime: 10
        ),
    ]

    let reconciled = WhisperKitResultMapper.reconcile(results: results)

    #expect(reconciled.segments.count == 2)
    #expect(reconciled.segments[0].segment.text == "kept")
    #expect(reconciled.segments[0].segment.end == 9)
    #expect(reconciled.segments[1].segment.text == "duplicate next")
    #expect(reconciled.diagnostics.contains {
        $0.details?.reconciliationReason == .wordsOutsideWindow
            && $0.details?.removedWordCount == 1
    })
}

@Test func reconciliationDropsSegmentsWhollyOutsideTheirWindow() {
    var timings = TranscriptionTimings(fullPipeline: 1)
    timings.inputAudioSeconds = 10
    let result = TranscriptionResult(
        text: "overflow",
        segments: [TranscriptionSegment(start: 11, end: 12, text: "overflow")],
        language: "en",
        timings: timings,
        seekTime: 0
    )

    let reconciled = WhisperKitResultMapper.reconcile(results: [result])

    #expect(reconciled.segments.isEmpty)
    #expect(reconciled.diagnostics.first?.details?.reconciliationReason == .outsideWindow)
}

@Test func fileRecognizerRejectsNonFileInputBeforeLoadingAModel() async {
    let recognizer = WhisperKitRecognizer()
    await #expect(throws: WhisperKitRecognizerError.unsupportedInput) {
        try await recognizer.transcribe(.system, language: .automatic)
    }
}

@Test func cantoneseMatchesTheResolvedWhisperKitLanguageTable() {
    #expect(WhisperLanguage(rawValue: "yue")?.rawValue == "yue")
}

@Test func unknownDetectedLanguageProducesTypedError() {
    #expect(throws: WhisperKitRecognizerError.unsupportedLanguage("future-token")) {
        try WhisperKitRecognizer.validatedDetectedLanguage("future-token")
    }
}

@Test func languageLogProbabilityIsConvertedToConfidence() {
    let confidence = WhisperKitRecognizer.languageConfidence(fromLogProbability: -0.0033057074)
    #expect(confidence != nil)
    #expect(abs(confidence! - 0.9967) < 0.0001)
    #expect(WhisperKitRecognizer.languageConfidence(fromLogProbability: .nan) == nil)
}

@Test func fileRecognizerRejectsMissingFileBeforeLoadingAModel() async {
    let recognizer = WhisperKitRecognizer()
    let path = "/tmp/bfish-missing-audio-fixture.wav"
    await #expect(throws: WhisperKitRecognizerError.fileNotFound(path)) {
        try await recognizer.transcribe(
            .file(URL(fileURLWithPath: path)),
            language: .automatic
        )
    }
}

@Test func modelStatusesProduceParseablePrivacySafeJSONL() throws {
    let statuses: [WhisperKitStatus] = [
        .resolving, .downloading(percent: 42), .filesReady, .loading, .loaded, .alreadyResident,
    ]

    for status in statuses {
        let event = DiagnosticEvent(
            event: .modelStatus,
            details: DiagnosticDetails(
                modelStatus: status.diagnosticModelStatus,
                progressPercentage: status.progressPercentage
            )
        )
        let line = try event.jsonLine()
        #expect(line.last == 0x0A)
        _ = try JSONSerialization.jsonObject(with: line.dropLast())
    }
}

@Test func downloadProgressSuppressesDuplicateIntegerPercentages() {
    let received = LockedStatuses()
    let reporter = ProgressReporter { received.append($0) }
    let progress = Progress(totalUnitCount: 1_000)

    progress.completedUnitCount = 101
    reporter.report(progress)
    progress.completedUnitCount = 102
    reporter.report(progress)
    progress.completedUnitCount = 111
    reporter.report(progress)

    #expect(received.values == [.downloading(percent: 10), .downloading(percent: 11)])
}

private final class LockedStatuses: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [WhisperKitStatus] = []

    var values: [WhisperKitStatus] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ status: WhisperKitStatus) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(status)
    }
}
