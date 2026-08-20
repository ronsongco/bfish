import Foundation

public actor TranslationPipeline {
    private let recognizer: any SpeechRecognizing
    private let translator: any TextTranslating
    private let contextLimit: Int

    public init(
        recognizer: any SpeechRecognizing,
        translator: any TextTranslating,
        contextLimit: Int = 4
    ) {
        self.recognizer = recognizer
        self.translator = translator
        self.contextLimit = max(0, contextLimit)
    }

    public func process(_ input: AudioInput, language: LanguageTag = .automatic) async throws -> [TranscriptTurn] {
        let segments = try await recognizer.transcribe(input, language: language)
        var turns: [TranscriptTurn] = []

        for segment in segments where !segment.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let context = Array(turns.suffix(contextLimit))
            let response = try await translator.translate(
                TranslationRequest(segment: segment, recentContext: context)
            )
            turns.append(TranscriptTurn(segment: segment, englishText: response.englishText))
        }

        return turns
    }
}
