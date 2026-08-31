import Testing
@testable import NumberSniperCore

@Suite("レベル進行")
struct LevelProgressionTests {
    @Test("Lv n 到達は 3×(n−1) 問正解後", arguments: [
        (0, 1), (1, 1), (2, 1),
        (3, 2), (5, 2),
        (6, 3),
        (9, 4), (11, 4),
        (12, 5),
    ])
    func levelsUpEveryThreeCorrect(correctCount: Int, expected: Int) {
        #expect(LevelProgression.level(correctCount: correctCount) == expected)
    }

    @Test("最高レベルが上限で、それ以上正解しても上がらない")
    func capsAtMaxLevel() {
        // リテラルで書くと maxLevel を変えた瞬間に嘘になる（2026-08-05 に 10 → 12 で実際に落ちた）
        let atCap = GameConfig.correctAnswersPerLevel * (GameConfig.maxLevel - 1)
        #expect(LevelProgression.level(correctCount: atCap) == GameConfig.maxLevel)
        #expect(LevelProgression.level(correctCount: atCap - 1) == GameConfig.maxLevel - 1)
        #expect(LevelProgression.level(correctCount: atCap + 1) == GameConfig.maxLevel)
        #expect(LevelProgression.level(correctCount: atCap * 100) == GameConfig.maxLevel)
    }

    @Test("12 問目の正解は Lv4 で採点され、直後に Lv5 へ上がる")
    func twelfthCorrectIsScoredAtLevel4() {
        // 12 問目の開始時点 = それまでの正解数 11
        #expect(LevelProgression.level(correctCount: 11) == 4)
        // 12 問目を正解した直後
        #expect(LevelProgression.level(correctCount: 12) == 5)
    }

    @Test("負の正解数でも Lv1 を下回らない")
    func neverBelowLevelOne() {
        #expect(LevelProgression.level(correctCount: -5) == 1)
    }
}
