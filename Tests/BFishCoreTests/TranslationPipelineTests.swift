import Foundation
import Testing
@testable import BFishCore

private let testTimeline = CaptureTimeline(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
    startedAt: Date(timeIntervalSince1970: 1_000)
)

@Test func pipelineTranslatesNonEmptySegmentsAndPassesBoundedContext() async throws {
    let segments = [
        RecognizedSegment(
            timeRange: try AudioTimeRange(start: 0, end: 2),
            timeline: testTimeline,
            language: .japanese,
            sourceText: "こんにちは。",
            speaker: SpeakerID("Speaker 1")
        ),
        RecognizedSegment(
            timeRange: try AudioTimeRange(start: 2, end: 3),
            timeline: testTimeline,
            language: .japanese,
            sourceText: "   "
        ),
        RecognizedSegment(
            timeRange: try AudioTimeRange(start: 3, end: 5),
            timeline: testTimeline,
            language: .japanese,
            sourceText: "元気ですか。",
            speaker: SpeakerID("Speaker 2")
        ),
    ]
    let recognizer = RecognizerStub(segments: segments)
    let translator = TranslatorStub()
    let pipeline = TranslationPipeline(recognizer: recognizer, translator: translator, profile: .offline, contextLimit: 1)

    let turns = try await pipeline.process(.file(URL(fileURLWithPath: "/tmp/example.wav")))

    #expect(turns.count == 2)
    #expect(turns[0].englishText == "English: こんにちは。")
    #expect(turns[1].englishText == "English: 元気ですか。")
    #expect(turns.allSatisfy { $0.timeline == testTimeline })
    #expect(await translator.contextCounts == [0, 1])
}

@Test(arguments: ["[Music]", "（笑）", "［音楽］", "【拍手】", "〔音楽〕"])
func bracketedAnnotationsAreFilteredWithDiagnostics(_ sourceText: String) async throws {
    let segment = RecognizedSegment(
        timeRange: try AudioTimeRange(start: 0, end: 1),
        timeline: testTimeline,
        language: .japanese,
        sourceText: sourceText
    )
    let translator = TranslatorStub()
    let pipeline = TranslationPipeline(
        recognizer: RecognizerStub(segments: [segment]),
        translator: translator,
        profile: .offline
    )

    var diagnostics: [DiagnosticEvent] = []
    for try await event in await pipeline.events(for: .file(URL(fileURLWithPath: "/tmp/example.wav"))) {
        if case let .diagnostic(diagnostic) = event { diagnostics.append(diagnostic) }
    }

    #expect(diagnostics.count == 1)
    #expect(diagnostics[0].event == .segmentFiltered)
    #expect(diagnostics[0].details?.segmentFilterReason == .annotation)
    #expect(await translator.contextCounts.isEmpty)
}

@Test(arguments: ["2026", "42", "3.14", "50%", "$100", "７８９"])
func numericSegmentsAreMeaningfulContent(_ sourceText: String) {
    #expect(TranslationPipeline.filterReason(for: sourceText) == nil)
}

@Test(arguments: ["。。。", "♪", "...", "!!!"])
func punctuationOnlySegmentsAreFiltered(_ sourceText: String) {
    #expect(TranslationPipeline.filterReason(for: sourceText) == .noContent)
}

@Test func pipelineAppliesSessionLocaleCentrally() async throws {
    let segment = RecognizedSegment(
        timeRange: try AudioTimeRange(start: 0, end: 1),
        timeline: testTimeline,
        language: .portuguese,
        sourceText: "Olá"
    )
    let pipeline = TranslationPipeline(
        recognizer: RecognizerStub(segments: [segment]),
        translator: TranslatorStub(),
        profile: .offline,
        sessionLocale: .brazilianPortuguese
    )

    let turns = try await pipeline.process(.file(URL(fileURLWithPath: "/tmp/example.wav")))

    #expect(turns.first?.sessionLocale == .brazilianPortuguese)
}

@Test func suppressedNoSpeechTurnDoesNotEnterTranslationContext() async throws {
    let segments = [
        RecognizedSegment(
            timeRange: try AudioTimeRange(start: 0, end: 1),
            timeline: testTimeline,
            language: .japanese,
            sourceText: "最初"
        ),
        RecognizedSegment(
            timeRange: try AudioTimeRange(start: 1, end: 2),
            timeline: testTimeline,
            language: .japanese,
            sourceText: "不明な音声",
            noSpeechProbability: 0.95
        ),
        RecognizedSegment(
            timeRange: try AudioTimeRange(start: 2, end: 3),
            timeline: testTimeline,
            language: .japanese,
            sourceText: "次"
        ),
    ]
    let translator = TranslatorStub()
    let pipeline = TranslationPipeline(
        recognizer: RecognizerStub(segments: segments),
        translator: translator,
        profile: .offline
    )

    _ = try await pipeline.process(.file(URL(fileURLWithPath: "/tmp/example.wav")))

    #expect(await translator.contextSources == [[], ["最初"]])
}

@Test func knownSilenceHallucinationsAndRepetitionAreFiltered() async throws {
    let segments = [
        RecognizedSegment(
            timeRange: try AudioTimeRange(start: 0, end: 1),
            timeline: testTimeline,
            language: .japanese,
            sourceText: "ご視聴ありがとうございました"
        ),
        RecognizedSegment(
            timeRange: try AudioTimeRange(start: 1, end: 2),
            timeline: testTimeline,
            language: .japanese,
            sourceText: "繰り返し",
            compressionRatio: 3
        ),
    ]
    let pipeline = TranslationPipeline(
        recognizer: RecognizerStub(segments: segments),
        translator: TranslatorStub(),
        profile: .offline
    )

    var reasons: [SegmentFilterReason] = []
    var quarantinedTurns: [TranscriptTurn] = []
    var suppressionCodes: [String] = []
    for try await event in await pipeline.events(for: .file(URL(fileURLWithPath: "/tmp/example.wav"))) {
        switch event {
        case let .transcript(turn) where turn.qualityDisposition == .suspectedHallucination:
            quarantinedTurns.append(turn)
        case let .diagnostic(diagnostic):
            if let reason = diagnostic.details?.segmentFilterReason { reasons.append(reason) }
            if diagnostic.event == .translationSuppressed,
               let code = diagnostic.details?.errorCode
            {
                suppressionCodes.append(code)
            }
        default:
            break
        }
    }

    #expect(reasons == [.repetitive])
    #expect(quarantinedTurns.count == 1)
    #expect(quarantinedTurns[0].englishText == nil)
    #expect(suppressionCodes == ["suspected_hallucination"])
}

@Test func retainedContextHistoryIsBounded() throws {
    let turns = try (0..<20).map { index in
        TranscriptTurn(
            segment: RecognizedSegment(
                timeRange: try AudioTimeRange(start: Double(index), end: Double(index + 1)),
                timeline: testTimeline,
                language: .japanese,
                sourceText: "turn-\(index)"
            ),
            englishText: "english-\(index)",
            sessionLocale: nil
        )
    }

    let retained = TranslationPipeline.trimmedContextHistory(turns, limit: 4)

    #expect(retained.count == 4)
    #expect(retained.first?.sourceText == "turn-16")
    #expect(retained.last?.sourceText == "turn-19")
}

@Test func pipelinePreservesSourceAndContinuesAfterTranslationFailure() async throws {
    let segments = [
        RecognizedSegment(
            timeRange: try AudioTimeRange(start: 0, end: 1),
            timeline: testTimeline,
            language: .japanese,
            sourceText: "失敗"
        ),
        RecognizedSegment(
            timeRange: try AudioTimeRange(start: 1, end: 2),
            timeline: testTimeline,
            language: .japanese,
            sourceText: "続行"
        ),
    ]
    let pipeline = TranslationPipeline(
        recognizer: RecognizerStub(segments: segments),
        translator: RecoveringTranslatorStub(),
        profile: .offline
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
            timeline: testTimeline,
            language: .japanese,
            sourceText: "[Music]"
        ),
        RecognizedSegment(
            timeRange: try AudioTimeRange(start: 1, end: 2),
            timeline: testTimeline,
            language: .english,
            sourceText: "Already English",
            languageConfidence: 0.99
        ),
    ]
    let translator = TranslatorStub()
    let pipeline = TranslationPipeline(recognizer: RecognizerStub(segments: segments), translator: translator, profile: .offline)

    let turns = try await pipeline.process(.file(URL(fileURLWithPath: "/tmp/example.wav")))

    #expect(turns.count == 1)
    #expect(turns[0].englishText == "Already English")
    #expect(await translator.contextCounts.isEmpty)
}

@Test func contextDoesNotSkipAnOversizedMostRecentTurn() throws {
    let older = TranscriptTurn(
        segment: RecognizedSegment(
            timeRange: try AudioTimeRange(start: 0, end: 1),
            timeline: testTimeline,
            language: .japanese,
            sourceText: "older"
        ),
        englishText: "old",
        sessionLocale: nil
    )
    let newest = TranscriptTurn(
        segment: RecognizedSegment(
            timeRange: try AudioTimeRange(start: 1, end: 2),
            timeline: testTimeline,
            language: .japanese,
            sourceText: String(repeating: "長", count: 101)
        ),
        englishText: nil,
        sessionLocale: nil
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
        timeline: testTimeline,
        language: .japanese,
        sourceText: "待って"
    )
    let pipeline = TranslationPipeline(
        recognizer: RecognizerStub(segments: [segment]),
        translator: SlowTranslatorStub(),
        profile: .live,
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
        timeline: testTimeline,
        language: .english,
        sourceText: "English at Tagalog",
        languageConfidence: 0.99,
        containsMixedLanguages: true
    )
    let translator = TranslatorStub()
    let pipeline = TranslationPipeline(recognizer: RecognizerStub(segments: [segment]), translator: translator, profile: .live)

    let turns = try await pipeline.process(.file(URL(fileURLWithPath: "/tmp/example.wav")))

    #expect(turns.first?.englishText == "English: English at Tagalog")
    #expect(await translator.contextCounts.count == 1)
}

@Test func pipelineYieldsFinalizedTurnBeforeRecognitionCompletes() async throws {
    let recognizer = StreamingRecognizerStub()
    let pipeline = TranslationPipeline(
        recognizer: recognizer,
        translator: TranslatorStub(),
        profile: .live
    )
    let stream = await pipeline.events(for: .file(URL(fileURLWithPath: "/tmp/example.wav")))
    var iterator = stream.makeAsyncIterator()

    let first = try await iterator.next()

    guard case let .transcript(turn) = first else {
        Issue.record("Expected the first pipeline event to be a transcript turn")
        return
    }
    #expect(turn.sourceText == "先に表示")
    #expect(await !recognizer.finished)
}

private struct RecognizerStub: SpeechRecognizing {
    let segments: [RecognizedSegment]

    func transcribe(_ input: AudioInput, language: WhisperLanguage) async throws -> SpeechRecognitionOutput {
        SpeechRecognitionOutput(segments: segments)
    }
}

@Test func passThroughTranslatorPreservesSourceText() async throws {
    let segment = RecognizedSegment(
        timeRange: try AudioTimeRange(start: 0, end: 1),
        timeline: testTimeline,
        language: .japanese,
        sourceText: "原文"
    )

    let response = try await PassThroughTranslator().translate(
        TranslationRequest(segment: segment, recentContext: [])
    )

    #expect(response.englishText == "原文")
}

private actor TranslatorStub: TextTranslating {
    private(set) var contextCounts: [Int] = []
    private(set) var contextSources: [[String]] = []

    func translate(_ request: TranslationRequest) async throws -> TranslationResponse {
        contextCounts.append(request.recentContext.count)
        contextSources.append(request.recentContext.map(\.sourceText))
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

private actor StreamingRecognizerStub: SpeechRecognizing {
    private(set) var finished = false

    func transcribe(_ input: AudioInput, language: WhisperLanguage) async throws -> SpeechRecognitionOutput {
        SpeechRecognitionOutput(segments: [])
    }

    func events(
        for input: AudioInput,
        language: WhisperLanguage
    ) async -> AsyncThrowingStream<SpeechRecognitionEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.segment(RecognizedSegment(
                    timeRange: try! AudioTimeRange(start: 0, end: 1),
                    timeline: testTimeline,
                    language: .japanese,
                    sourceText: "先に表示"
                )))
                try? await Task.sleep(for: .milliseconds(200))
                self.markFinished()
                continuation.yield(.completed(timings: [], metrics: nil))
                continuation.finish()
            }
        }
    }

    private func markFinished() {
        finished = true
    }
}
