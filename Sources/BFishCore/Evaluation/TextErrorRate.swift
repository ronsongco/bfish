import Foundation

public enum TextErrorRateError: Error, Equatable, Sendable {
    case emptyReference
}

public struct ErrorRateScore: Codable, Equatable, Sendable {
    public let edits: Int
    public let referenceUnitCount: Int

    public init(edits: Int, referenceUnitCount: Int) {
        self.edits = edits
        self.referenceUnitCount = referenceUnitCount
    }

    public var rate: Double {
        Double(edits) / Double(referenceUnitCount)
    }
}

public struct TextErrorRateReport: Codable, Equatable, Sendable {
    public let rawCharacterErrorRate: ErrorRateScore
    public let normalizedCharacterErrorRate: ErrorRateScore
    public let normalizedWordErrorRate: ErrorRateScore

    public init(reference: String, hypothesis: String) throws {
        rawCharacterErrorRate = try TextErrorRate.characterScore(
            reference: Array(reference),
            hypothesis: Array(hypothesis)
        )
        normalizedCharacterErrorRate = try TextErrorRate.characterScore(
            reference: TextEvaluationNormalizer.characters(reference),
            hypothesis: TextEvaluationNormalizer.characters(hypothesis)
        )
        normalizedWordErrorRate = try TextErrorRate.wordScore(
            reference: TextEvaluationNormalizer.words(reference),
            hypothesis: TextEvaluationNormalizer.words(hypothesis)
        )
    }
}

public enum TextEvaluationNormalizer {
    public static func characters(_ text: String) -> [Character] {
        Array(canonicalText(text).filter { character in
            !character.unicodeScalars.allSatisfy {
                CharacterSet.whitespacesAndNewlines.contains($0)
                    || CharacterSet.punctuationCharacters.contains($0)
            }
        })
    }

    public static func words(_ text: String) -> [String] {
        let separated = canonicalText(text).map { character -> Character in
            character.unicodeScalars.allSatisfy {
                CharacterSet.punctuationCharacters.contains($0)
            } ? " " : character
        }
        return String(separated).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func canonicalText(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
    }
}

public enum TextErrorRate {
    public static func characterScore(
        reference: [Character],
        hypothesis: [Character]
    ) throws -> ErrorRateScore {
        try score(reference: reference, hypothesis: hypothesis)
    }

    public static func wordScore(
        reference: [String],
        hypothesis: [String]
    ) throws -> ErrorRateScore {
        try score(reference: reference, hypothesis: hypothesis)
    }

    private static func score<Unit: Equatable>(
        reference: [Unit],
        hypothesis: [Unit]
    ) throws -> ErrorRateScore {
        guard !reference.isEmpty else { throw TextErrorRateError.emptyReference }

        var previous = Array(0...hypothesis.count)
        for (referenceIndex, referenceUnit) in reference.enumerated() {
            var current = Array(repeating: 0, count: hypothesis.count + 1)
            current[0] = referenceIndex + 1
            for (hypothesisIndex, hypothesisUnit) in hypothesis.enumerated() {
                let substitutionCost = referenceUnit == hypothesisUnit ? 0 : 1
                current[hypothesisIndex + 1] = min(
                    previous[hypothesisIndex + 1] + 1,
                    current[hypothesisIndex] + 1,
                    previous[hypothesisIndex] + substitutionCost
                )
            }
            previous = current
        }

        return ErrorRateScore(edits: previous[hypothesis.count], referenceUnitCount: reference.count)
    }
}
