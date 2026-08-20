import Foundation
import Testing
@testable import BFishCore

@Test func pipelineTranslatesNonEmptySegmentsAndPassesBoundedContext() async throws {
    let segments = [
        RecognizedSegment(
            timeRange: AudioTimeRange(start: 0, end: 2),
            language: .japanese,
            sourceText: "こんにちは。",
            speaker: SpeakerID("Speaker 1")
        ),
        RecognizedSegment(
            timeRange: AudioTimeRange(start: 2, end: 3),
            language: .japanese,
            sourceText: "   "
        ),
        RecognizedSegment(
            timeRange: AudioTimeRange(start: 3, end: 5),
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

private struct RecognizerStub: SpeechRecognizing {
    let segments: [RecognizedSegment]

    func transcribe(_ input: AudioInput, language: LanguageTag) async throws -> [RecognizedSegment] {
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
