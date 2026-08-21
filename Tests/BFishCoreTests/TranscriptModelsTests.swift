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

    let turn = TranscriptTurn(segment: segment, englishText: "The weather is nice today.", sessionLocale: nil)

    #expect(turn.sourceText == segment.sourceText)
    #expect(turn.timeline == timeline)
    #expect(turn.speaker == SpeakerID("Speaker 2"))
    #expect(turn.englishText == "The weather is nice today.")
}

@Test func terminalFormatterIncludesSourceEnglishLanguageAndSpeaker() throws {
    let segment = RecognizedSegment(
        timeRange: try AudioTimeRange(start: 62, end: 68),
        timeline: CaptureTimeline(id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!),
        language: .japanese,
        sourceText: "こんにちは。",
        speaker: SpeakerID("Host")
    )
    let turn = TranscriptTurn(segment: segment, englishText: "Hello.", sessionLocale: nil)

    let output = TerminalTranscriptFormatter().format(turn)

    #expect(output == "[00:01:02] [ja] [Host]\nSource: こんにちは。\nEnglish: Hello.")
}

@Test func terminalFormatterPrefersConfiguredSessionLocale() throws {
    let segment = RecognizedSegment(
        timeRange: try AudioTimeRange(start: 1, end: 2),
        timeline: CaptureTimeline(id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!),
        language: .portuguese,
        sourceText: "Olá"
    )

    let output = TerminalTranscriptFormatter().format(
        TranscriptTurn(segment: segment, englishText: "Hello", sessionLocale: .brazilianPortuguese)
    )

    #expect(output.contains("[pt-BR]"))
}

@Test func sessionLocaleNormalizesAndRejectsInvalidIdentifiers() throws {
    #expect(SessionLocale("PT-br")?.rawValue == "pt-BR")
    #expect(SessionLocale("zh-hans-cn")?.rawValue == "zh-Hans-CN")
    #expect(SessionLocale("nonsense") == nil)
    #expect(SessionLocale("pt-") == nil)
    #expect(SessionLocale("pt-٣٣٣") == nil)
    #expect(SessionLocale("pt-ⅢⅢⅢ") == nil)
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(SessionLocale.self, from: Data(#""invalid-locale-name""#.utf8))
    }
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
    #expect(text.contains("\"schemaVersion\":8"))
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
