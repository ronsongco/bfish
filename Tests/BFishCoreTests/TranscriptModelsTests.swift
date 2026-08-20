import Foundation
import Testing
@testable import BFishCore

@Test func transcriptTurnPreservesAuthoritativeSourceAndSpeaker() throws {
    let timeline = CaptureTimeline(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
        startedAt: Date(timeIntervalSince1970: 1_000)
    )
    let segment = RecognizedSegment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        timeRange: try AudioTimeRange(start: 62, end: 68),
        timeline: timeline,
        language: .japanese,
        sourceText: "今日は天気がいいですね。",
        speaker: SpeakerID("Speaker 2")
    )

    let turn = TranscriptTurn(segment: segment, englishText: "The weather is nice today.")

    #expect(turn.sourceText == segment.sourceText)
    #expect(turn.timeline == timeline)
    #expect(turn.speaker == SpeakerID("Speaker 2"))
    #expect(turn.englishText == "The weather is nice today.")
}

@Test func terminalFormatterIncludesSourceEnglishLanguageAndSpeaker() throws {
    let segment = RecognizedSegment(
        timeRange: try AudioTimeRange(start: 62, end: 68),
        language: .japanese,
        sourceText: "こんにちは。",
        speaker: SpeakerID("Host")
    )
    let turn = TranscriptTurn(segment: segment, englishText: "Hello.")

    let output = TerminalTranscriptFormatter().format(turn)

    #expect(output == "[00:01:02] [ja] [Host]\nSource: こんにちは。\nEnglish: Hello.")
}

@Test func diagnosticEventProducesOneJSONLine() throws {
    let event = DiagnosticEvent(
        timestamp: Date(timeIntervalSince1970: 0),
        event: .segmentCompleted,
        timings: [StageTiming(stage: "translation", milliseconds: 12.5)]
    )

    let data = try event.jsonLine()
    let text = String(decoding: data, as: UTF8.self)

    #expect(text.hasSuffix("\n"))
    #expect(text.contains("\"event\":\"segment_completed\""))
    #expect(text.contains("\"schemaVersion\":2"))
    #expect(text.contains("\"stage\":\"translation\""))
}

@Test func audioTimeRangeRejectsInvalidInferenceAndDecodedValues() throws {
    #expect(throws: AudioTimeRangeError.self) {
        try AudioTimeRange(start: .nan, end: 1)
    }
    #expect(throws: AudioTimeRangeError.self) {
        try AudioTimeRange(start: 2, end: 1)
    }
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(AudioTimeRange.self, from: Data(#"{"start":2,"end":1}"#.utf8))
    }
}

@Test func timestampRepairProducesValidRangesAndReasons() {
    let nonFinite = AudioTimeRange.repairing(start: .nan, end: 4, fallbackStart: 3)
    #expect(nonFinite.timeRange.start == 3)
    #expect(nonFinite.timeRange.end == 3)
    #expect(nonFinite.reason == .nonFinite)

    let reversed = AudioTimeRange.repairing(start: 5, end: 4)
    #expect(reversed.timeRange.start == 5)
    #expect(reversed.timeRange.end == 5)
    #expect(reversed.reason == .reversedRange)
}

@Test func whisperLanguageNormalizesAndValidatesFullSetTokens() throws {
    #expect(WhisperLanguage(rawValue: "DE")?.rawValue == "de")
    #expect(WhisperLanguage(rawValue: "ar") != nil)
    #expect(WhisperLanguage(rawValue: "pt-BR") == nil)
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(WhisperLanguage.self, from: Data(#""not-a-language""#.utf8))
    }
}
