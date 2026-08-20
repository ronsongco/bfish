import Foundation

public protocol AudioCapturing: Sendable {
    func frames(from input: AudioInput) -> AsyncThrowingStream<AudioFrame, Error>
}

public protocol SpeechSegmenting: Sendable {
    func segments(from frames: AsyncThrowingStream<AudioFrame, Error>) -> AsyncThrowingStream<[Float], Error>
}

public protocol SpeechRecognizing: Sendable {
    func transcribe(_ input: AudioInput, language: LanguageTag) async throws -> [RecognizedSegment]
}

public struct TranslationRequest: Sendable {
    public let segment: RecognizedSegment
    public let recentContext: [TranscriptTurn]

    public init(segment: RecognizedSegment, recentContext: [TranscriptTurn]) {
        self.segment = segment
        self.recentContext = recentContext
    }
}

public protocol TextTranslating: Sendable {
    func translate(_ request: TranslationRequest) async throws -> TranslationResponse
}

public protocol SpeakerDiarizing: Sendable {
    func assignSpeakers(
        to segments: [RecognizedSegment],
        in audioFile: URL,
        expectedSpeakerCount: Int?
    ) async throws -> [RecognizedSegment]
}

public protocol TranscriptFormatting: Sendable {
    func format(_ turn: TranscriptTurn) -> String
}
