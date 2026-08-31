import Testing
@testable import NumberSniperCore

@Suite("GameConfig の不変条件")
struct GameConfigTests {
    @Test("判定しきい値は昇順に並んでいる")
    func thresholdsAreAscending() {
        #expect(GameConfig.perfectThreshold < GameConfig.greatThreshold)
        #expect(GameConfig.greatThreshold < GameConfig.goodThreshold)
    }

    @Test("精度点はすべて 100 の倍数（獲得点の整数除算が割り切れる前提）")
    func accuracyPointsAreMultiplesOf100() {
        for points in [GameConfig.perfectPoints, GameConfig.greatPoints, GameConfig.goodPoints] {
            #expect(points % 100 == 0)
        }
    }

    @Test("目標比率の範囲は 0 と 1 の内側にある")
    func targetBoundsAreInsideUnitInterval() {
        #expect(GameConfig.minTarget > 0)
        #expect(GameConfig.maxTarget < 1)
        #expect(GameConfig.minTarget < GameConfig.maxTarget)
    }

    @Test("目盛の分割数は 10^practiceMaxDecimals を割り切る")
    func practiceTickDivisionsDivideScale() {
        // これが崩れると目盛値が有限小数で表せず、丸めた（＝線の位置と食い違う）表示になる
        #expect(power10(GameConfig.practiceMaxDecimals) % GameConfig.practiceTickDivisions == 0)
    }

    @Test("目盛の分割数は 2 以上（1 以下は目盛が引けない）")
    func practiceTickDivisionsAreAtLeastTwo() {
        #expect(GameConfig.practiceTickDivisions > 1)
    }

    @Test("広告頻度は 1 以上（0 はゼロ除算でクラッシュする）")
    func interstitialFrequencyIsPositive() {
        // `ScoreStore` が count % gameOversPerInterstitial で判定しているので、
        // 0 にすると「広告を止める」つもりの変更がクラッシュになる
        #expect(GameConfig.gameOversPerInterstitial >= 1)
    }

    @Test("復活の定数は 1 以上（0 だと機能が黙って死ぬ）")
    func reviveConstantsArePositive() {
        // maxRevivesPerGame が 0 なら canRevive が常に false、livesOnRevive が 0 なら
        // 復活した瞬間にまたゲームオーバー。どちらもクラッシュせず静かに壊れる
        #expect(GameConfig.maxRevivesPerGame >= 1)
        #expect(GameConfig.livesOnRevive >= 1)
    }

    @Test("復活オファーの秒読みは正の秒数")
    func continueOfferSecondsIsPositive() {
        // 0 以下だと stride が空になり、オファーが一瞬も表示されないまま確定する
        #expect(GameConfig.continueOfferSeconds > 0)
    }

    @Test("練習モードの確定仕様の値を固定する")
    func practiceConstantsAreFixed() {
        // 定数から導出するテストしか無いと、値を変えても境界テストが追従して通ってしまう。
        // 「25.5 / 38 / 50.5 の 2 桁小数」「0.35 秒の連打ガード」は spec の確定済み要件なので
        // リテラルで固定する（0 だと 0〜1 レンジで PERFECT 窓 0.01 が表示上 0 に潰れる）
        #expect(GameConfig.practiceMaxDecimals == 2)
        #expect(GameConfig.practiceMinResultDisplaySeconds == 0.35)
    }
}
