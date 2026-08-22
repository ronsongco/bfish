import Testing
@testable import BFishCore

@Test func normalizedCharacterErrorRateIgnoresCaseSpacingAndPunctuation() throws {
    let report = try TextErrorRateReport(
        reference: "Olá, mundo!",
        hypothesis: "olá mundo",
        language: .portuguese
    )

    #expect(report.rawCharacterErrorRate.edits > 0)
    #expect(report.normalizedCharacterErrorRate.rate == 0)
    #expect(report.normalizedWordErrorRate?.rate == 0)
}

@Test func characterErrorRateCapturesCJKSubstitutionsWithoutSegmentation() throws {
    let score = try TextErrorRate.characterScore(
        reference: TextEvaluationNormalizer.characters("音声"),
        hypothesis: TextEvaluationNormalizer.characters("本生")
    )

    #expect(score.edits == 2)
    #expect(score.referenceUnitCount == 2)
    #expect(score.rate == 1)
}

@Test func normalizationUsesCompatibilityUnicodeComposition() throws {
    let score = try TextErrorRate.characterScore(
        reference: TextEvaluationNormalizer.characters("한글"),
        hypothesis: TextEvaluationNormalizer.characters("한글")
    )

    #expect(score.rate == 0)
}

@Test func compatibilityNormalizationFoldsJapaneseWidthVariants() throws {
    let score = try TextErrorRate.characterScore(
        reference: TextEvaluationNormalizer.characters("789 ABC カタカナ"),
        hypothesis: TextEvaluationNormalizer.characters("７８９ ＡＢＣ ｶﾀｶﾅ")
    )

    #expect(score.rate == 0)
}

@Test func wordErrorRateIsUnavailableForNonWhitespaceLanguages() throws {
    let japanese = try TextErrorRateReport(reference: "音声認識", hypothesis: "音声識別", language: .japanese)
    let portuguese = try TextErrorRateReport(reference: "olá mundo", hypothesis: "olá", language: .portuguese)

    #expect(japanese.normalizedWordErrorRate == nil)
    #expect(portuguese.normalizedWordErrorRate != nil)
}

@Test func wordErrorRateCountsOneSubstitution() throws {
    let score = try TextErrorRate.wordScore(
        reference: ["this", "is", "a", "test"],
        hypothesis: ["this", "was", "a", "test"]
    )

    #expect(score.edits == 1)
    #expect(score.rate == 0.25)
}

@Test func emptyReferenceIsRejected() {
    #expect(throws: TextErrorRateError.emptyReference) {
        try TextErrorRate.characterScore(reference: [], hypothesis: Array("x"))
    }
}
