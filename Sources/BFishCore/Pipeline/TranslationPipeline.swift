import Foundation

public enum PipelineEvent: Sendable {
    case transcript(TranscriptTurn)
    case diagnostic(DiagnosticEvent)
}

public enum TranslationPipelineError: Error, Equatable, Sendable {
    case translationTimedOut
}

public actor TranslationPipeline {
    private let recognizer: any SpeechRecognizing
    private let translator: any TextTranslating
    private let contextTurnLimit: Int
    private let contextCharacterLimit: Int
    private let translationTimeout: Duration

    public init(
        recognizer: any SpeechRecognizing,
        translator: any TextTranslating,
        contextLimit: Int = 4,
        contextCharacterLimit: Int = 2_000,
        translationTimeout: Duration = .seconds(30)
    ) {
        self.recognizer = recognizer
        self.translator = translator
        self.contextTurnLimit = max(0, contextLimit)
        self.contextCharacterLimit = max(0, contextCharacterLimit)
        self.translationTimeout = translationTimeout
    }

    /// Primary API. Recoverable translation errors produce a source-only turn
    /// and a diagnostic rather than terminating the stream.
    public func events(
        for input: AudioInput,
        language: WhisperLanguage = .automatic
    ) -> AsyncThrowingStream<PipelineEvent, Error> {
        let recognizer = self.recognizer
        let translator = self.translator
        let turnLimit = contextTurnLimit
        let characterLimit = contextCharacterLimit
        let timeout = translationTimeout

        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            let task = Task {
                do {
                    let segments = try await recognizer.transcribe(input, language: language)
                    var contextTurns: [TranscriptTurn] = []

                    for segment in segments where Self.hasMeaningfulContent(segment.sourceText) {
                        if segment.language == .english {
                            let turn = TranscriptTurn(segment: segment, englishText: segment.sourceText)
                            contextTurns.append(turn)
                            continuation.yield(.transcript(turn))
                            continue
                        }

                        let context = Self.boundedContext(
                            contextTurns,
                            turnLimit: turnLimit,
                            characterLimit: characterLimit
                        )

                        do {
                            let response = try await Self.withTimeout(timeout) {
                                try await translator.translate(
                                    TranslationRequest(segment: segment, recentContext: context)
                                )
                            }
                            let turn = TranscriptTurn(segment: segment, englishText: response.englishText)
                            contextTurns.append(turn)
                            continuation.yield(.transcript(turn))
                        } catch {
                            let turn = TranscriptTurn(segment: segment, englishText: nil)
                            contextTurns.append(turn)
                            continuation.yield(.transcript(turn))
                            continuation.yield(.diagnostic(DiagnosticEvent(
                                event: .translationUnavailable,
                                segmentID: segment.id,
                                details: DiagnosticDetails(errorCode: Self.errorCode(for: error))
                            )))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Batch convenience for tests and short files. Long-running consumers
    /// should consume `events(for:language:)` directly.
    public func process(
        _ input: AudioInput,
        language: WhisperLanguage = .automatic
    ) async throws -> [TranscriptTurn] {
        var turns: [TranscriptTurn] = []
        for try await event in events(for: input, language: language) {
            if case let .transcript(turn) = event {
                turns.append(turn)
            }
        }
        return turns
    }

    private static func boundedContext(
        _ turns: [TranscriptTurn],
        turnLimit: Int,
        characterLimit: Int
    ) -> [TranscriptTurn] {
        guard turnLimit > 0, characterLimit > 0 else { return [] }
        var result: [TranscriptTurn] = []
        var characters = 0

        for turn in turns.suffix(turnLimit).reversed() {
            let cost = turn.sourceText.count
            if !result.isEmpty, characters + cost > characterLimit { break }
            guard cost <= characterLimit else { continue }
            result.append(turn)
            characters += cost
        }
        return result.reversed()
    }

    private static func hasMeaningfulContent(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let normalized = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]()"))
            .lowercased()
        let nonSpeechLabels: Set<String> = ["music", "applause", "laughter", "silence"]
        guard !nonSpeechLabels.contains(normalized) else { return false }

        return trimmed.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    private static func errorCode(for error: any Error) -> String {
        if error is TranslationPipelineError { return "translation_timeout" }
        return "translation_failed"
    }

    private static func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw TranslationPipelineError.translationTimedOut
            }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return result
        }
    }
}
