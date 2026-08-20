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
    #expect(diagnostics.map(\.event) == [.translationUnavailable])
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
            sourceText: "Already English"
        ),
    ]
    let translator = TranslatorStub()
    let pipeline = TranslationPipeline(recognizer: RecognizerStub(segments: segments), translator: translator)

    let turns = try await pipeline.process(.file(URL(fileURLWithPath: "/tmp/example.wav")))

    #expect(turns.count == 1)
    #expect(turns[0].englishText == "Already English")
    #expect(await translator.contextCounts.isEmpty)
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
