import Testing
@testable import NumberSniperCore

@Suite("練習モードの目盛")
struct PracticeTickTests {
    @Test("目盛値が有限小数で表せる invariant")
    func scaleIsDivisibleByDivisions() {
        #expect(power10(GameConfig.practiceMaxDecimals) % GameConfig.practiceTickDivisions == 0)
    }

    @Test("出荷値は 4 分割 ＝ 25/50/75% の 3 本")
    func shippingDivisionsAreQuarters() {
        // invariant（scale % D == 0）だけだと D=5 でも通る。確定済み要件の
        // 「25/50/75% 位置」は D=4 でしか成立しないので直接固定する
        #expect(GameConfig.practiceTickDivisions == 4)
        let ticks = LineRange.unit.practiceTicks()
        #expect(ticks.count == 3)
        #expect(ticks.map(\.ratio) == [0.25, 0.5, 0.75])
        #expect(ticks.map(\.index) == [1, 2, 3])
        #expect(ticks.allSatisfy { $0.divisions == 4 })
    }

    @Test("0〜1 レンジの目盛は 0.25 / 0.5 / 0.75")
    func unitRangeTicks() {
        #expect(LineRange.unit.practiceTicks().map(\.value.trimmedText) == ["0.25", "0.5", "0.75"])
    }

    @Test("13〜63 の目盛は 25.5 / 38 / 50.5")
    func twoDigitRangeTicks() {
        let ticks = LineRange.integers(lower: 13, upper: 63).practiceTicks()
        #expect(ticks.map(\.value.trimmedText) == ["25.5", "38", "50.5"])
    }

    @Test("150〜387 の目盛は 209.25 / 268.5 / 327.75（丸めない）")
    func threeDigitRangeTicks() {
        let ticks = LineRange.integers(lower: 150, upper: 387).practiceTicks()
        // 209.25 を 209.3 と出すと線の位置と表示値が食い違う
        #expect(ticks.map(\.value.trimmedText) == ["209.25", "268.5", "327.75"])
    }

    @Test("分割数を変えると目盛もそれに追従する（ハードコードでない）")
    func honorsCustomDivisions() {
        let range = LineRange.integers(lower: 13, upper: 63)
        let halves = range.practiceTicks(divisions: 2)
        #expect(halves.count == 1)
        #expect(halves[0].value.trimmedText == "38")
        #expect(halves[0].ratio == 0.5)

        let fifths = range.practiceTicks(divisions: 5)
        #expect(fifths.count == 4)
        #expect(fifths.map(\.value.trimmedText) == ["23", "33", "43", "53"])

        #expect(LineRange.unit.practiceTicks(divisions: 10).count == 9)
        #expect(LineRange.unit.practiceTicks(divisions: 10)[0].value.trimmedText == "0.1")
    }

    @Test("レンジ幅と下端はレンジの種類で決まる")
    func widthAndLowerBound() {
        #expect(LineRange.unit.width == 1)
        #expect(LineRange.unit.lowerBound == 0)
        #expect(LineRange.integers(lower: 13, upper: 63).width == 50)
        #expect(LineRange.integers(lower: 13, upper: 63).lowerBound == 13)
        #expect(LineRange.integers(lower: 150, upper: 387).width == 237)
    }

    /// 出荷カーブが実際に生成しうるレンジを総当たりして、目盛が
    /// **独立に組んだ有理数の期待値**と一致することを見る。
    ///
    /// 「落ちない」「桁数 ≤ 上限」「単調増加」は `k·W/D`（1≤k<D, W≥1）である限り
    /// どんな実装でも成立する ＝ 弁別力ゼロなので、`value = lower + k·W/D` の
    /// 等式そのものを（除算を挟まない交差乗算で）突き合わせる。
    ///
    /// - Important: 期待値は **`LineRange` の enum ペイロードから直接**組む。
    ///   `range.lowerBound` / `range.width` を使うとこの PR で足した実装を両辺で使うことになり、
    ///   その 2 つのバグが相殺して総当たりが素通りする（`width` を `upper - lower + 1` に
    ///   改変しても pass したのを実測）
    @Test("出荷カーブ全帯のお題で目盛が期待値と一致する")
    func ticksMatchIndependentExpectationAcrossShippingCurve() {
        let curve = LevelCurve.standard
        let generator = QuestionGenerator()
        let scale = power10(GameConfig.practiceMaxDecimals)
        var rng = SeededRandomNumberGenerator(seed: 0xB1AC_2026)
        var checkedBounds = Set<Bounds>()

        for stage in curve.stages {
            for type in stage.types {
                for _ in 0..<200 {
                    let question = generator.make(
                        type: type, parameters: stage.parameters, using: &rng
                    )
                    let range = question.range
                    let bounds = Bounds(range)
                    checkedBounds.insert(bounds)
                    // 実装側の width / lowerBound もここで初めて突き合わせる
                    #expect(range.lowerBound == bounds.lower)
                    #expect(range.width == bounds.width)

                    for divisions in [2, GameConfig.practiceTickDivisions, 5] {
                        let ticks = range.practiceTicks(divisions: divisions)
                        #expect(ticks.count == divisions - 1)
                        for tick in ticks {
                            // value == lower + k·W/D を交差乗算で（実装の式を写経しない形で）確認
                            let expectedNumerator =
                                (bounds.lower * divisions + tick.index * bounds.width) * scale
                            #expect(tick.value.scaled * divisions == expectedNumerator)
                            #expect(tick.value.decimals == GameConfig.practiceMaxDecimals)
                            // 目盛はレンジの内側にある
                            #expect(tick.value.scaled > bounds.lower * scale)
                            #expect(tick.value.scaled < bounds.upper * scale)
                        }
                    }
                }
            }
        }

        // .unit と 0 始まり・2 桁・3 桁の非包含な組が実際に回っていること（vacuous pass の防止）
        #expect(checkedBounds.contains(Bounds(.unit)))
        // 0 始まりキリ番（Lv5-6 の四則演算）
        #expect(checkedBounds.contains { $0.lower == 0 && $0.width >= 10 })
        // 2 桁の任意レンジ（Lv9-10）。下端が 1 以上なのが 0 始まりとの違い
        #expect(checkedBounds.contains { $0.lower >= 1 && (20...50).contains($0.width) })
        // 3 桁レンジ（Lv11-12）
        #expect(checkedBounds.contains { $0.lower >= 100 && $0.width >= 200 })
    }

    /// `LineRange` の両端を enum のペイロードから直に取り出したもの。
    /// テストの期待値を実装（`LineRange.width` / `lowerBound`）から独立させるために使う。
    private struct Bounds: Hashable {
        let lower: Int
        let upper: Int
        var width: Int { upper - lower }

        init(_ range: LineRange) {
            switch range {
            case .unit:
                (lower, upper) = (0, 1)
            case .integers(let lower, let upper):
                (self.lower, self.upper) = (lower, upper)
            }
        }
    }
}
