import Testing
@testable import NumberSniperCore

@Suite("固定小数点の表示")
struct LineValueTests {
    @Test("末尾ゼロを落として表示する")
    func trimsTrailingZeros() {
        #expect(LineValue(scaled: 2_550, decimals: 2).trimmedText == "25.5")
        #expect(LineValue(scaled: 3_800, decimals: 2).trimmedText == "38")
        #expect(LineValue(scaled: 5, decimals: 2).trimmedText == "0.05")
    }

    @Test("小数部のゼロ埋めが要る値でも桁がずれない")
    func padsFractionDigits() {
        // 5/100 は "0.5" ではなく "0.05"。ゼロ埋めを忘れると 10 倍の嘘になる
        #expect(LineValue(scaled: 105, decimals: 2).trimmedText == "1.05")
        #expect(LineValue(scaled: 1, decimals: 2).trimmedText == "0.01")
    }

    @Test("整数値と 0 は小数点を付けない")
    func integersHaveNoPoint() {
        #expect(LineValue(scaled: 0, decimals: 2).trimmedText == "0")
        #expect(LineValue(scaled: 0, decimals: 0).trimmedText == "0")
        #expect(LineValue(scaled: 209, decimals: 0).trimmedText == "209")
    }

    @Test("負値は trimmedText にだけ符号が付く")
    func negativeSignOnlyInTrimmedText() {
        let value = LineValue(scaled: -2_550, decimals: 2)
        #expect(value.trimmedText == "-25.5")
        #expect(value.magnitudeText == "25.5")
    }

    @Test("magnitudeText には符号が漏れない")
    func magnitudeTextIsUnsigned() {
        #expect(LineValue(scaled: -1, decimals: 2).magnitudeText == "0.01")
        #expect(LineValue(scaled: -38, decimals: 0).magnitudeText == "38")
    }

    @Test("同じ実値でも桁数が違えば別の値")
    func decimalsArePartOfIdentity() {
        #expect(LineValue(scaled: 38, decimals: 0) != LineValue(scaled: 3_800, decimals: 2))
        #expect(LineValue(scaled: 3_800, decimals: 2) == LineValue(scaled: 3_800, decimals: 2))
    }

    @Test("表示桁数は PERFECT 窓が潰れない最小桁になる")
    func offsetDecimalsFollowsPerfectWindow() {
        #expect(LineRange.unit.offsetDecimals == 2)                          // W=1  窓 0.01
        #expect(LineRange.integers(lower: 0, upper: 10).offsetDecimals == 1) // W=10 窓 0.1
        #expect(LineRange.integers(lower: 0, upper: 50).offsetDecimals == 1) // W=50 窓 0.5
        #expect(LineRange.integers(lower: 0, upper: 100).offsetDecimals == 0) // W=100 窓 1
        #expect(LineRange.integers(lower: 150, upper: 387).offsetDecimals == 0)
    }

    @Test("表示桁数は practiceMaxDecimals を超えない")
    func offsetDecimalsIsCapped() {
        #expect(LineRange.unit.offsetDecimals <= GameConfig.practiceMaxDecimals)
    }

    @Test("ズレの丸めは half-away-from-zero（境界ちょうどで切り上がる）")
    func roundsHalfAwayFromZero() {
        // W=1 / n=2。scaled = (|d|·1·100 + 5000) / 10000 なので d=50 が境界ちょうど
        #expect(LineRange.unit.offsetValue(signedDeviation: 49).scaled == 0)
        #expect(LineRange.unit.offsetValue(signedDeviation: 50).scaled == 1)
        #expect(LineRange.unit.offsetValue(signedDeviation: -50).scaled == 1)
        // W=100 / n=0。同じく d=50 が境界
        let hundred = LineRange.integers(lower: 0, upper: 100)
        #expect(hundred.offsetValue(signedDeviation: 49).scaled == 0)
        #expect(hundred.offsetValue(signedDeviation: 50).scaled == 1)
    }

    @Test("0〜1 レンジのズレは 0.01 刻みで立ち上がる")
    func unitRangeOffsetSteps() {
        #expect(LineRange.unit.offsetValue(signedDeviation: 0).magnitudeText == "0")
        #expect(LineRange.unit.offsetValue(signedDeviation: 49).magnitudeText == "0")
        #expect(LineRange.unit.offsetValue(signedDeviation: 50).magnitudeText == "0.01")
        #expect(LineRange.unit.offsetValue(signedDeviation: 250).magnitudeText == "0.03")
        // 末尾ゼロを落とすので "0.00" / "0.10" という表示は存在しない
        #expect(LineRange.unit.offsetValue(signedDeviation: 1_000).magnitudeText == "0.1")
    }

    @Test("13〜63 で 3 ズレたら「3」と出る")
    func customRangeOffsetText() {
        // レンジ幅 50 の 3 は d = 3/50 × 10000 = 600
        let range = LineRange.integers(lower: 13, upper: 63)
        #expect(range.offsetValue(signedDeviation: -600).magnitudeText == "3")
        #expect(range.offsetValue(signedDeviation: 600).magnitudeText == "3")
        // 1 桁小数まで出る帯なので 0.5 刻みが潰れない
        #expect(range.offsetValue(signedDeviation: 100).magnitudeText == "0.5")
    }

    @Test("ズレの実数値はレンジ幅に比例する")
    func offsetScalesWithWidth() {
        // 同じ d = 1000（レンジ幅の 10%）でも、実数値はレンジ幅ぶん違う
        #expect(LineRange.integers(lower: 0, upper: 100)
            .offsetValue(signedDeviation: 1_000).magnitudeText == "10")
        #expect(LineRange.integers(lower: 150, upper: 387)
            .offsetValue(signedDeviation: 1_000).magnitudeText == "24")  // 23.7 → n=0 で 24
    }

    @Test("ズレの実数値は符号を持たない")
    func offsetValueIsUnsigned() {
        let range = LineRange.integers(lower: 13, upper: 63)
        #expect(range.offsetValue(signedDeviation: -600) == range.offsetValue(signedDeviation: 600))
        #expect(range.offsetValue(signedDeviation: -600).scaled >= 0)
    }
}
