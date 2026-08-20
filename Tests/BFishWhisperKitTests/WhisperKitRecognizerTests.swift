import Testing
import BFishCore
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
    #expect(mapped.diagnostic?.event == .timestampRepaired)
    #expect(mapped.diagnostic?.details?.timestampRepairReason == .nonFinite)
}
