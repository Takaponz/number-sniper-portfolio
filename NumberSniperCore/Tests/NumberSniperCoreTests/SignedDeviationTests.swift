import Foundation
import Testing
@testable import NumberSniperCore

@Suite("符号付きのズレ")
struct SignedDeviationTests {
    @Test("目標より左で止めたら負")
    func leftIsNegative() {
        #expect(signedDeviation(stopRatio: 0.60, target: 0.62) == -200)
    }

    @Test("目標より右で止めたら正")
    func rightIsPositive() {
        #expect(signedDeviation(stopRatio: 0.64, target: 0.62) == 200)
    }

    @Test("ぴったり止めたら 0")
    func exactHitIsZero() {
        #expect(signedDeviation(stopRatio: 0.62, target: 0.62) == 0)
    }

    @Test("絶対値は既存 deviation() と総当たりで一致し、符号は大小関係に従う")
    func magnitudeAndSignMatchAcrossTheLine() {
        for target in [0.05, 0.37, 0.5, 0.62, 0.95] {
            for step in 0...100 {
                let stopRatio = Double(step) / 100
                let signed = signedDeviation(stopRatio: stopRatio, target: target)
                // 委譲が外れていないこと
                #expect(abs(signed) == deviation(stopRatio: stopRatio, target: target))
                // 本当のリスクである符号の向きを全ペアで固定する
                // （d が 0 に丸まる近傍だけは符号が消えるので除外）
                if signed != 0 {
                    #expect((stopRatio < target) == (signed < 0))
                }
            }
        }
    }

    @Test("判定は本編と同じ経路（絶対値を judge に通した結果と一致）")
    func judgementMatchesMainLine() {
        for target in [0.2, 0.5, 0.8] {
            for step in 0...100 {
                let stopRatio = Double(step) / 100
                let signed = signedDeviation(stopRatio: stopRatio, target: target)
                #expect(judge(deviation: abs(signed))
                    == judge(deviation: deviation(stopRatio: stopRatio, target: target)))
            }
        }
    }

    @Test("nan は正側の最大ズレになる")
    func nanIsPositiveMax() {
        #expect(signedDeviation(stopRatio: .nan, target: 0.5) == 10_000)
        #expect(signedDeviation(stopRatio: 0.5, target: .nan) == 10_000)
    }

    @Test("+∞ の目標でも符号が反転しない（guard が無いと −10000 になる）")
    func infiniteTargetDoesNotFlipSign() {
        // stopRatio(0) < target(∞) は true なので、guard 無しでは −10000 が返る
        #expect(signedDeviation(stopRatio: 0, target: .infinity) == 10_000)
        #expect(signedDeviation(stopRatio: 0, target: -.infinity) == 10_000)
        #expect(signedDeviation(stopRatio: .infinity, target: 0.5) == 10_000)
    }

    @Test("レンジ外まで飛んでもクランプされた値に符号が乗る")
    func clampsWithSign() {
        #expect(signedDeviation(stopRatio: -5.0, target: 0.5) == -10_000)
        #expect(signedDeviation(stopRatio: 5.0, target: 0.5) == 10_000)
    }

    @Test("数直線の両端は符号だけが逆になる")
    func endsAreSymmetric() {
        #expect(signedDeviation(stopRatio: 0, target: 0.5) == -5_000)
        #expect(signedDeviation(stopRatio: 1, target: 0.5) == 5_000)
    }
}
