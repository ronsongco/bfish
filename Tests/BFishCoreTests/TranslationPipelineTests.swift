import Foundation
import Testing
@testable import BFishCore

@Test func pipelineTranslatesNonEmptySegmentsAndPassesBoundedContext() async throws {
    let segments = [
        RecognizedSegment(
            timeRange: try AudioTimeRange(start: 0, end: 2),
            language: .japanese,
            sourceText: "こんにちは。",
            speaker: SpeakerID("Speaker 1")
        ),
        RecognizedSegment(
            timeRange: try AudioTimeRange(start: 2, end: 3),
            language: .japanese,
            sourceText: "   "
        ),
        RecognizedSegment(
            timeRange: try AudioTimeRange(start: 3, end: 5),
            language: .japanese,
            sourceText: "元気ですか。",
            speaker: SpeakerID("Speaker 2")
        ),
    ]
    let recognizer = RecognizerStub(segments: segments)
    let translator = TranslatorStub()
    let pipeline = TranslationPipeline(recognizer: recognizer, translator: translator, contextLimit: 1)

    let turns = try await pipeline.process(.file(URL(fileURLWithPath: "/tmp/example.wav")))

    #expect(turns.count == 2)
    #expect(turns[0].englishText == "English: こんにちは。")
    #expect(turns[1].englishText == "English: 元気ですか。")
    #expect(await translator.contextCounts == [0, 1])
}

@Test func pipelinePreservesSourceAndContinuesAfterTranslationFailure() async throws {
    let segments = [
        RecognizedSegment(
            timeRange: try AudioTimeRange(start: 0, end: 1),
            language: .japanese,
            sourceText: "失敗"
        ),
        RecognizedSegment(
            timeRange: try AudioTimeRange(start: 1, end: 2),
            language: .japanese,
            sourceText: "続行"
        ),
    ]
    let pipeline = TranslationPipeline(
        recognizer: RecognizerStub(segments: segments),
        translator: RecoveringTranslatorStub()
    )

    var turns: [TranscriptTurn] = []
    var diagnostics: [DiagnosticEvent] = []
    for try await event in await pipeline.events(for: .file(URL(fileURLWithPath: "/tmp/example.wav"))) {
        switch event {
        case let .transcript(turn): turns.append(turn)
        case let .diagnostic(event): diagnostics.append(event)
        }
    }

    #expect(turns.count == 2)
    #expect(turns[0].sourceText == "失敗")
    #expect(turns[0].englishText == nil)
    #expect(turns[1].englishText == "continued")
    #expect(diagnostics.filter { $0.event == .translationUnavailable }.count == 1)
}

@Test func pipelineSkipsNonSpeechLabelsAndBypassesEnglishTranslation() async throws {
    let segments = [
        RecognizedSegment(
            timeRange: try AudioTimeRange(start: 0, end: 1),
            language: .japanese,
            sourceText: "[Music]"
        ),
        RecognizedSegment(
            timeRange: try AudioTimeRange(start: 1, end: 2),
            language: .english,
            sourceText: "Already English",
            languageConfidence: 0.99
        ),
    ]
    let translator = TranslatorStub()
    let pipeline = TranslationPipeline(recognizer: RecognizerStub(segments: segments), translator: translator)

    let turns = try await pipeline.process(.file(URL(fileURLWithPath: "/tmp/example.wav")))

    #expect(turns.count == 1)
    #expect(turns[0].englishText == "Already English")
    #expect(await translator.contextCounts.isEmpty)
}

@Test func contextDoesNotSkipAnOversizedMostRecentTurn() throws {
    let older = TranscriptTurn(
        segment: RecognizedSegment(
            timeRange: try AudioTimeRange(start: 0, end: 1),
            language: .japanese,
            sourceText: "older"
        ),
        englishText: "old"
    )
    let newest = TranscriptTurn(
        segment: RecognizedSegment(
            timeRange: try AudioTimeRange(start: 1, end: 2),
            language: .japanese,
            sourceText: String(repeating: "長", count: 101)
        ),
        englishText: nil
    )

    let context = TranslationPipeline.boundedContext(
        [older, newest],
        turnLimit: 4,
        characterLimit: 100
    )

    #expect(context.isEmpty)
}

@Test func timeoutIsClassifiedAndProducesSourceOnlyTurn() async throws {
    let segment = RecognizedSegment(
        timeRange: try AudioTimeRange(start: 0, end: 1),
        language: .japanese,
        sourceText: "待って"
    )
    let pipeline = TranslationPipeline(
        recognizer: RecognizerStub(segments: [segment]),
        translator: SlowTranslatorStub(),
        translationTimeout: .milliseconds(10)
    )

    var events: [PipelineEvent] = []
    for try await event in await pipeline.events(for: .file(URL(fileURLWithPath: "/tmp/example.wav"))) {
        events.append(event)
    }

    let turns = events.compactMap { event -> TranscriptTurn? in
        if case let .transcript(turn) = event { return turn }
        return nil
    }
    let diagnostics = events.compactMap { event -> DiagnosticEvent? in
        if case let .diagnostic(diagnostic) = event { return diagnostic }
        return nil
    }
    #expect(turns.first?.englishText == nil)
    #expect(diagnostics.first?.details?.errorCode == "translation_timeout")
}

@Test func mixedEnglishDoesNotBypassTranslation() async throws {
    let segment = RecognizedSegment(
        timeRange: try AudioTimeRange(start: 0, end: 1),
        language: .english,
        sourceText: "English at Tagalog",
        languageConfidence: 0.99,
        containsMixedLanguages: true
    )
    let translator = TranslatorStub()
    let pipeline = TranslationPipeline(recognizer: RecognizerStub(segments: [segment]), translator: translator)

    let turns = try await pipeline.process(.file(URL(fileURLWithPath: "/tmp/example.wav")))

    #expect(turns.first?.englishText == "English: English at Tagalog")
    #expect(await translator.contextCounts.count == 1)
}

private struct RecognizerStub: SpeechRecognizing {
    let segments: [RecognizedSegment]

    func transcribe(_ input: AudioInput, language: WhisperLanguage) async throws -> [RecognizedSegment] {
        segments
    }
}

private actor TranslatorStub: TextTranslating {
    private(set) var contextCounts: [Int] = []

    func translate(_ request: TranslationRequest) async throws -> TranslationResponse {
        contextCounts.append(request.recentContext.count)
        return TranslationResponse(englishText: "English: \(request.segment.sourceText)")
    }
}

private actor RecoveringTranslatorStub: TextTranslating {
    private var callCount = 0

    func translate(_ request: TranslationRequest) async throws -> TranslationResponse {
        callCount += 1
        if callCount == 1 { throw StubError.expected }
        return TranslationResponse(englishText: "continued")
    }

    private enum StubError: Error { case expected }
}

private struct SlowTranslatorStub: TextTranslating {
    func translate(_ request: TranslationRequest) async throws -> TranslationResponse {
        try await Task.sleep(for: .seconds(1))
        return TranslationResponse(englishText: "late")
    }
}
