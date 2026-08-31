import Testing
@testable import NumberSniperCore

@Suite("スコア計算")
struct ScoringTests {
    @Test("コンボ倍率は 100% から 10% 刻みで増え、300% で頭打ち", arguments: [
        (0, 100), (1, 110), (5, 150), (19, 290), (20, 300), (21, 300), (100, 300),
    ])
    func comboMultiplier(combo: Int, expected: Int) {
        #expect(comboMultiplierPercent(combo: combo) == expected)
    }

    @Test("PERFECT はコンボ +2、GREAT は +1、GOOD/MISS は 0 リセット")
    func comboTransitions() {
        #expect(nextCombo(current: 3, judgement: .perfect) == 5)
        #expect(nextCombo(current: 3, judgement: .great) == 4)
        #expect(nextCombo(current: 3, judgement: .good) == 0)
        #expect(nextCombo(current: 3, judgement: .miss) == 0)
    }

    @Test("Lv1・コンボ0 の PERFECT は 1000 点")
    func baselinePerfect() {
        #expect(roundPoints(judgement: .perfect, level: 1, combo: 0) == 1000)
    }

    @Test("レベル倍率とコンボ倍率が掛かる")
    func multipliersApply() {
        // 500 * 3 * 150% / 100 = 2250
        #expect(roundPoints(judgement: .great, level: 3, combo: 5) == 2250)
        // 1000 * 10 * 300% / 100 = 30000（コンボ上限。Lv10 は代表値で、上限レベルではない）
        #expect(roundPoints(judgement: .perfect, level: 10, combo: 50) == 30_000)
        // 100 * 4 * 120% / 100 = 480
        #expect(roundPoints(judgement: .good, level: 4, combo: 2) == 480)
    }

    @Test("MISS は 0 点")
    func missScoresNothing() {
        #expect(roundPoints(judgement: .miss, level: 10, combo: 50) == 0)
    }

    @Test("獲得点はどの組み合わせでも整数除算で割り切れる（切り捨て損失が出ない）")
    func divisionIsExact() {
        for judgement in Judgement.allCases {
            for level in 1...GameConfig.maxLevel {
                for combo in 0...25 {
                    let numerator = judgement.accuracyPoints * level * comboMultiplierPercent(combo: combo)
                    #expect(numerator % 100 == 0)
                    #expect(roundPoints(judgement: judgement, level: level, combo: combo) == numerator / 100)
                }
            }
        }
    }
}
