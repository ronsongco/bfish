import Foundation
import Testing
@testable import BFishCore

@Test func transcriptTurnPreservesAuthoritativeSourceAndSpeaker() {
    let segment = RecognizedSegment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        timeRange: AudioTimeRange(start: 62, end: 68),
        language: .japanese,
        sourceText: "今日は天気がいいですね。",
        speaker: SpeakerID("Speaker 2")
    )

    let turn = TranscriptTurn(segment: segment, englishText: "The weather is nice today.")

    #expect(turn.sourceText == segment.sourceText)
    #expect(turn.speaker == SpeakerID("Speaker 2"))
    #expect(turn.englishText == "The weather is nice today.")
}

@Test func terminalFormatterIncludesSourceEnglishLanguageAndSpeaker() {
    let segment = RecognizedSegment(
        timeRange: AudioTimeRange(start: 62, end: 68),
        language: .japanese,
        sourceText: "こんにちは。",
        speaker: SpeakerID("Host")
    )
    let turn = TranscriptTurn(segment: segment, englishText: "Hello.")

    let output = TerminalTranscriptFormatter().format(turn)

    #expect(output == "[01:02] [ja] [Host]\nSource: こんにちは。\nEnglish: Hello.")
}

@Test func diagnosticEventProducesOneJSONLine() throws {
    let event = DiagnosticEvent(
        timestamp: Date(timeIntervalSince1970: 0),
        event: "segment_complete",
        timings: [StageTiming(stage: "translation", milliseconds: 12.5)]
    )

    let data = try event.jsonLine()
    let text = String(decoding: data, as: UTF8.self)

    #expect(text.hasSuffix("\n"))
    #expect(text.contains("\"event\":\"segment_complete\""))
    #expect(text.contains("\"stage\":\"translation\""))
}
