import Testing
@testable import NumberSniperCore

@Suite("判定のカスケード評価")
struct JudgementTests {
    @Test("境界値ちょうどは上位の判定を採る", arguments: [
        (0, Judgement.perfect),
        (100, Judgement.perfect),
        (101, Judgement.great),
        (300, Judgement.great),
        (301, Judgement.good),
        (700, Judgement.good),
        (701, Judgement.miss),
        (10_000, Judgement.miss),
    ])
    func boundaries(d: Int, expected: Judgement) {
        #expect(judge(deviation: d) == expected)
    }

    @Test("正解は MISS 以外")
    func correctnessExcludesOnlyMiss() {
        #expect(Judgement.perfect.isCorrect)
        #expect(Judgement.great.isCorrect)
        #expect(Judgement.good.isCorrect)
        #expect(!Judgement.miss.isCorrect)
    }

    @Test("精度点は判定別の固定値")
    func accuracyPointsAreFixed() {
        #expect(Judgement.perfect.accuracyPoints == 1000)
        #expect(Judgement.great.accuracyPoints == 500)
        #expect(Judgement.good.accuracyPoints == 100)
        #expect(Judgement.miss.accuracyPoints == 0)
    }
}
