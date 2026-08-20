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

@Test func mapperPreservesTimelineAndReportsNonMonotonicResults() {
    let timeline = CaptureTimeline()
    let timings = TranscriptionTimings(fullPipeline: 1)
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
    #expect(output.diagnostics.contains { diagnostic in
        diagnostic.event == .timelineDiscontinuity
            && diagnostic.details?.errorCode == "non_monotonic_segment_start"
    })
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
