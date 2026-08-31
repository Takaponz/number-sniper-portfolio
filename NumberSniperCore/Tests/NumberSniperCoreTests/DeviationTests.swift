import Testing
@testable import NumberSniperCore

@Suite("ズレ d への丸め")
struct DeviationTests {
    @Test("ぴったり止めたら 0")
    func exactHitIsZero() {
        #expect(deviation(stopRatio: 0.62, target: 0.62) == 0)
    }

    @Test("符号によらず絶対値で測る")
    func isAbsolute() {
        #expect(deviation(stopRatio: 0.60, target: 0.62) == deviation(stopRatio: 0.64, target: 0.62))
    }

    @Test("レンジ幅の 0.01% 単位の整数になる")
    func scalesToTenThousandths() {
        #expect(deviation(stopRatio: 0.63, target: 0.62) == 100)
        #expect(deviation(stopRatio: 0.69, target: 0.62) == 700)
    }

    @Test("最も近い整数に丸める")
    func roundsToNearest() {
        // 期待値はすべて実際に計算して確かめた値。
        // 二進浮動小数では「ちょうど 0.5」を作れないので（例: 0.50005 - 0.5 は
        // 0.49999999999994493 になって 0 に丸まる）、half-away-from-zero そのものを
        // 突く形ではなく、最近接丸めの挙動を検証する
        #expect(deviation(stopRatio: 0.6201, target: 0.62) == 1)    // 1.0 相当
        #expect(deviation(stopRatio: 0.62014, target: 0.62) == 1)   // 1.4 相当
        #expect(deviation(stopRatio: 0.62016, target: 0.62) == 2)   // 1.6 相当
    }

    @Test("0〜10000 にクランプされる")
    func clampsToValidRange() {
        #expect(deviation(stopRatio: 5.0, target: 0.5) == 10_000)
        #expect(deviation(stopRatio: .nan, target: 0.5) == 10_000)
    }
}
