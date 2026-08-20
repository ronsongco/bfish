import Foundation
import Testing
@testable import BFishCore

@Test func transcriptTurnPreservesAuthoritativeSourceAndSpeaker() throws {
    let segment = RecognizedSegment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        timeRange: try AudioTimeRange(start: 62, end: 68),
        language: .japanese,
        sourceText: "今日は天気がいいですね。",
        speaker: SpeakerID("Speaker 2")
    )

    let turn = TranscriptTurn(segment: segment, englishText: "The weather is nice today.")

    #expect(turn.sourceText == segment.sourceText)
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
    #expect(text.contains("\"schemaVersion\":1"))
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
