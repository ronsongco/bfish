import Foundation

public enum PipelineEvent: Sendable {
    case transcript(TranscriptTurn)
    case diagnostic(DiagnosticEvent)
}

public enum TranslationPipelineError: Error, Equatable, Sendable {
    case translationTimedOut
    case sessionAlreadyRunning
}

public enum EnglishBypassPolicy: Equatable, Sendable {
    case never
    case highConfidenceOnly(minimumConfidence: Double)
    case always
}

public enum PipelineProfile: String, Codable, Sendable {
    case live
    case offline

    public var contextTurnLimit: Int { self == .live ? 4 : 8 }
    public var contextCharacterLimit: Int { self == .live ? 2_000 : 6_000 }
    public var translationTimeout: Duration { self == .live ? .seconds(15) : .seconds(60) }
    public var audioBufferingPolicy: AudioBufferingPolicy {
        AudioBufferingPolicy(newestChunkLimit: self == .live ? 32 : 128)
    }
}

/// One stateful transcription/translation session. Context and session identity
/// live on the actor and concurrent streams from one instance are rejected.
public actor TranslationPipeline {
    private let recognizer: any SpeechRecognizing
    private let translator: any TextTranslating
    private let contextTurnLimit: Int
    private let contextCharacterLimit: Int
    private let translationTimeout: Duration
    private let englishBypassPolicy: EnglishBypassPolicy
    private let maximumNoSpeechProbability: Double
    private let maximumCompressionRatio: Double
    private let sessionLocale: SessionLocale?

    private var activeSessionID: UUID?
    private var contextTurns: [TranscriptTurn] = []

    public init(
        recognizer: any SpeechRecognizing,
        translator: any TextTranslating,
        profile: PipelineProfile,
        contextLimit: Int? = nil,
        contextCharacterLimit: Int? = nil,
        translationTimeout: Duration? = nil,
        englishBypassPolicy: EnglishBypassPolicy = .highConfidenceOnly(minimumConfidence: 0.9),
        maximumNoSpeechProbability: Double = 0.6,
        maximumCompressionRatio: Double = 2.4,
        sessionLocale: SessionLocale? = nil
    ) {
        self.recognizer = recognizer
        self.translator = translator
        self.contextTurnLimit = max(0, contextLimit ?? profile.contextTurnLimit)
        self.contextCharacterLimit = max(0, contextCharacterLimit ?? profile.contextCharacterLimit)
        self.translationTimeout = translationTimeout ?? profile.translationTimeout
        self.englishBypassPolicy = englishBypassPolicy
        self.maximumNoSpeechProbability = min(1, max(0, maximumNoSpeechProbability))
        self.maximumCompressionRatio = max(1, maximumCompressionRatio)
        self.sessionLocale = sessionLocale
    }

    /// Primary API. Finalized transcript events use unbounded buffering because
    /// they are product output and must never be silently discarded.
    public func events(
        for input: AudioInput,
        language: WhisperLanguage = .automatic
    ) -> AsyncThrowingStream<PipelineEvent, Error> {
        guard activeSessionID == nil else {
            return AsyncThrowingStream { $0.finish(throwing: TranslationPipelineError.sessionAlreadyRunning) }
        }

        let sessionID = UUID()
        activeSessionID = sessionID
        contextTurns = []
        let recognizer = self.recognizer

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let recognition = try await recognizer.transcribe(input, language: language)
                    for diagnostic in recognition.diagnostics {
                        continuation.yield(.diagnostic(diagnostic))
                    }
                    if !recognition.timings.isEmpty {
                        continuation.yield(.diagnostic(DiagnosticEvent(
                            event: .recognitionCompleted,
                            timings: recognition.timings,
                            details: recognition.metrics?.diagnosticDetails
                        )))
                    }
                    for segment in recognition.segments {
                        let output = await self.handle(segment, sessionID: sessionID)
                        for event in output {
                            continuation.yield(event)
                        }
                    }
                    self.endSession(sessionID)
                    continuation.finish()
                } catch {
                    self.endSession(sessionID)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await self.endSession(sessionID) }
            }
        }
    }

    /// Batch convenience for tests and short files.
    public func process(
        _ input: AudioInput,
        language: WhisperLanguage = .automatic
    ) async throws -> [TranscriptTurn] {
        var turns: [TranscriptTurn] = []
        for try await event in events(for: input, language: language) {
            if case let .transcript(turn) = event { turns.append(turn) }
        }
        return turns
    }

    private func handle(_ segment: RecognizedSegment, sessionID: UUID) async -> [PipelineEvent] {
        guard activeSessionID == sessionID else { return [] }
        if let filterReason = Self.filterReason(for: segment, maximumCompressionRatio: maximumCompressionRatio) {
            return [.diagnostic(DiagnosticEvent(
                event: .segmentFiltered,
                segmentID: segment.id,
                details: DiagnosticDetails(segmentFilterReason: filterReason)
            ))]
        }

        if let probability = segment.noSpeechProbability, probability > maximumNoSpeechProbability {
            let turn = TranscriptTurn(segment: segment, englishText: nil, sessionLocale: sessionLocale)
            return [
                .transcript(turn),
                .diagnostic(DiagnosticEvent(
                    event: .translationSuppressed,
                    segmentID: segment.id,
                    details: DiagnosticDetails(errorCode: "high_no_speech_probability")
                )),
            ]
        }

        if shouldBypassEnglish(segment) {
            let turn = TranscriptTurn(segment: segment, englishText: segment.sourceText, sessionLocale: sessionLocale)
            retainForContext(turn)
            return [.transcript(turn)]
        }

        let context = Self.boundedContext(
            contextTurns,
            turnLimit: contextTurnLimit,
            characterLimit: contextCharacterLimit
        )
        let contextCharacters = Self.characterCost(context)

        do {
            let response = try await Self.withTimeout(translationTimeout) {
                try await self.translator.translate(
                    TranslationRequest(segment: segment, recentContext: context)
                )
            }
            guard activeSessionID == sessionID else { return [] }
            let turn = TranscriptTurn(segment: segment, englishText: response.englishText, sessionLocale: sessionLocale)
            retainForContext(turn)
            return [
                .transcript(turn),
                .diagnostic(DiagnosticEvent(
                    event: .segmentCompleted,
                    segmentID: segment.id,
                    details: DiagnosticDetails(
                        promptTokenCount: response.promptTokenCount,
                        contextCharacterCount: contextCharacters
                    )
                )),
            ]
        } catch {
            guard activeSessionID == sessionID else { return [] }
            let turn = TranscriptTurn(segment: segment, englishText: nil, sessionLocale: sessionLocale)
            retainForContext(turn)
            return [
                .transcript(turn),
                .diagnostic(DiagnosticEvent(
                    event: .translationUnavailable,
                    segmentID: segment.id,
                    details: DiagnosticDetails(
                        errorCode: Self.errorCode(for: error),
                        contextCharacterCount: contextCharacters
                    )
                )),
            ]
        }
    }

    private func shouldBypassEnglish(_ segment: RecognizedSegment) -> Bool {
        guard segment.language == .english, !segment.containsMixedLanguages else { return false }
        switch englishBypassPolicy {
        case .never: return false
        case .always: return true
        case let .highConfidenceOnly(minimumConfidence):
            return (segment.languageConfidence ?? 0) >= minimumConfidence
        }
    }

    private func endSession(_ sessionID: UUID) {
        guard activeSessionID == sessionID else { return }
        activeSessionID = nil
        contextTurns = []
    }

    private func retainForContext(_ turn: TranscriptTurn) {
        contextTurns.append(turn)
        contextTurns = Self.trimmedContextHistory(contextTurns, limit: contextTurnLimit)
    }

    static func trimmedContextHistory(_ turns: [TranscriptTurn], limit: Int) -> [TranscriptTurn] {
        guard limit > 0 else { return [] }
        return Array(turns.suffix(limit))
    }

    static func boundedContext(
        _ turns: [TranscriptTurn],
        turnLimit: Int,
        characterLimit: Int
    ) -> [TranscriptTurn] {
        guard turnLimit > 0, characterLimit > 0 else { return [] }
        var result: [TranscriptTurn] = []
        var characters = 0

        for turn in turns.suffix(turnLimit).reversed() {
            let cost = characterCost(turn)
            if cost > characterLimit || characters + cost > characterLimit { break }
            result.append(turn)
            characters += cost
        }
        return result.reversed()
    }

    static func characterCost(_ turns: [TranscriptTurn]) -> Int {
        turns.reduce(0) { $0 + characterCost($1) }
    }

    private static func characterCost(_ turn: TranscriptTurn) -> Int {
        turn.sourceText.count + (turn.englishText?.count ?? 0)
    }

    static func filterReason(for text: String) -> SegmentFilterReason? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        if let first = trimmed.first, let last = trimmed.last {
            let bracketPairs: [Character: Character] = [
                "[": "]", "(": ")", "［": "］", "（": "）", "【": "】", "〔": "〕",
            ]
            if bracketPairs[first] == last { return .annotation }
        }
        return trimmed.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) } ? nil : .noContent
    }

    static func filterReason(
        for segment: RecognizedSegment,
        maximumCompressionRatio: Double = 2.4
    ) -> SegmentFilterReason? {
        if let textualReason = filterReason(for: segment.sourceText) { return textualReason }
        if knownHallucinations.contains(normalizedHallucinationText(segment.sourceText)) {
            return .knownHallucination
        }
        if let ratio = segment.compressionRatio, ratio > maximumCompressionRatio {
            return .repetitive
        }
        return nil
    }

    private static let knownHallucinations: Set<String> = [
        "ご視聴ありがとうございました",
        "ご覧いただきありがとうございました",
        "thanksforwatching",
        "thankyouforwatching",
        "感谢观看",
        "感謝觀看",
        "시청해주셔서감사합니다",
        "obrigadoporassistir",
        "graciasporver",
        "grazieperaverguardato",
        "salamatsapanonood",
    ]

    private static func normalizedHallucinationText(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping
            .lowercased()
            .filter { !$0.isWhitespace && !$0.isPunctuation }
    }

    private static func errorCode(for error: any Error) -> String {
        if error is TranslationPipelineError { return "translation_timeout" }
        return "translation_failed"
    }

    static func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw TranslationPipelineError.translationTimedOut
            }
            guard let result = try await group.next() else { throw CancellationError() }
            group.cancelAll()
            return result
        }
    }
}
