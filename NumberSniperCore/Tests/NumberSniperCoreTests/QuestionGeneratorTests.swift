import Testing
import Foundation
@testable import NumberSniperCore

@Suite("お題生成")
struct QuestionGeneratorTests {
    let generator = QuestionGenerator()

    /// 変則レンジ帯（Lv9 = 第1ライン）のパラメータ。`LevelCurveTable.standard()` の値
    /// （分母 2〜9 / `.arbitrary(widths: 20...50)` / `percentStep: 1`）を持つ帯で、
    /// 個別タイプのテストで使う。`beginner()` を使う帯（Lv1-3 と Lv5-6）は
    /// 0 始まりレンジ・10% 刻みなので期待値が合わない。
    ///
    /// - Important: **`.customRange` を実際に出す帯（Lv9）から取ること。**
    ///   Lv4/7/8 も同じ `standard()` を使うので値は同一だが、それらの帯は
    ///   `.customRange` を types に持たない（2026-08-25 の並び替えで変則レンジの初出を
    ///   Lv9 に一本化した）。出さない帯を結合先にすると、(a) その帯のパラメータを
    ///   正当に簡素化しただけで無関係な変則レンジのテストが落ち、
    ///   (b) Lv9 のレンジ様式が退行しても気づけない
    static let standardParameters = LevelCurve.standard.stage(for: 9).parameters

    @Test("Lv1〜6 の固定タイプ帯は、生成経路でもその帯のタイプだけを出す", arguments: [
        (1, Set<QuestionType>([.percent])),
        (2, Set<QuestionType>([.fraction])),
        (3, Set<QuestionType>([.decimalValue])),
        (4, Set<QuestionType>([.decimalValue, .percent])),
        (5, Set<QuestionType>([.arithmetic])),
        (6, Set<QuestionType>([.arithmetic])),
    ])
    func fixedTypesForEarlyLevels(level: Int, expected: Set<QuestionType>) {
        // 2026-08-25 第3弾で Lv4 が 2 タイプのミックス帯になったので「単一タイプ」前提が崩れた。
        // 集合の包含だけだと「Lv4 が percent しか出さなくなった」退行を弁別できないので、
        // 複数タイプの帯は seed を増やして全タイプの出現も見る（mixedBandProducesEveryType と同型）
        let seedCount: UInt64 = expected.count > 1 ? 2000 : 50
        var seen: Set<QuestionType> = []
        for seed in UInt64(0)..<seedCount {
            var rng = SeededRandomNumberGenerator(seed: seed)
            let type = generator.make(level: level, using: &rng).type
            #expect(expected.contains(type), "Lv\(level): \(type)")
            seen.insert(type)
        }
        #expect(seen == expected, "Lv\(level): 出なかったタイプがある \(expected.subtracting(seen))")
    }

    @Test("Lv8 の混合帯では 3 タイプすべてが出る")
    func mixedBandProducesEveryType() {
        // 変則レンジは第1ライン（Lv9）の初出に一本化したので、この帯は 0〜1 レンジの 3 種だけ
        var seen: Set<QuestionType> = []
        for seed in UInt64(0)..<2000 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            seen.insert(generator.make(level: 8, using: &rng).type)
        }
        #expect(seen == Set([.decimalValue, .percent, .fraction]))
    }

    @Test("目標比率は常に 0.05〜0.95 に収まる")
    func targetAlwaysInsideBounds() {
        for seed in UInt64(0)..<2000 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            for level in 1...GameConfig.maxLevel {
                let question = generator.make(level: level, using: &rng)
                #expect(question.target >= GameConfig.minTarget)
                #expect(question.target <= GameConfig.maxTarget)
            }
        }
    }

    @Test("お題タイプとレンジは必ずペアになる")
    func typeAndRangeAreAlwaysPaired() {
        for seed in UInt64(0)..<2000 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            for level in 1...GameConfig.maxLevel {
                let question = generator.make(level: level, using: &rng)
                if question.type.requiredRangeIsUnit {
                    #expect(question.range == .unit)
                } else {
                    #expect(question.range.allowsIntegerPrompts)
                }
            }
        }
    }

    @Test("標準帯の変則レンジは幅 20〜50、下端 1 以上、上端 99 以下")
    func customRangeBoundsAreValid() {
        for seed in UInt64(0)..<2000 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            let question = generator.make(
                type: .customRange,
                parameters: Self.standardParameters,
                using: &rng
            )
            guard case .integers(let lower, let upper) = question.range else {
                Issue.record("変則レンジになっていない: \(question.range)")
                return
            }
            #expect((20...50).contains(upper - lower))
            #expect(lower >= 1)
            #expect(upper <= 99)
        }
    }

    @Test("変則レンジのお題は a < n < b を満たす整数で、t = (n−a)/(b−a) と一致する")
    func customRangePromptMatchesTarget() {
        for seed in UInt64(0)..<2000 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            let question = generator.make(
                type: .customRange,
                parameters: Self.standardParameters,
                using: &rng
            )
            guard case .integers(let lower, let upper) = question.range,
                  let value = Int(question.promptText) else {
                Issue.record("整数お題として解釈できない: \(question)")
                return
            }
            #expect(value > lower)
            #expect(value < upper)
            let expectedTarget = Double(value - lower) / Double(upper - lower)
            #expect(abs(question.target - expectedTarget) < 1e-12)
        }
    }

    @Test("0 始まりレンジは、指定した刻みで値を出す（promptStep 1 と 5 の両経路）")
    func roundRangesFollowPromptStep() {
        // キリ番お題（customRange）を出す帯は 2026-08-25 の並び替えで出荷カーブから消え、
        // 出荷の 0 始まりレンジは 0〜100（5 刻み）の 1 択になった（同日第2弾。出荷設定
        // そのものは LevelCurveTests の arithmeticLevelsUseFixedHundredRange が固定する）。
        // promptStep の既定値 1 は設計理由つきで残る機能（`RoundRangeOption` の doc）なので、
        // ここはテストローカルの options で step 1 / 5 の両生成経路を検証し続ける
        let options = [
            RoundRangeOption(upper: 10),
            RoundRangeOption(upper: 100, promptStep: 5),
        ]
        let parameters = QuestionParameters(customRangeStyle: .roundFromZero(options: options))
        let stepByUpper = Dictionary(uniqueKeysWithValues: options.map { ($0.upper, $0.promptStep) })
        var seenUppers: Set<Int> = []
        var sawNonMultipleOfFiveAtTen = false

        for seed in UInt64(0)..<2000 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            let question = generator.make(type: .customRange, parameters: parameters, using: &rng)
            guard case .integers(let lower, let upper) = question.range,
                  let value = Int(question.promptText) else {
                Issue.record("整数お題として解釈できない: \(question)")
                return
            }
            #expect(lower == 0)
            guard let step = stepByUpper[upper] else {
                Issue.record("options に無い上端が出た: \(upper)")
                return
            }
            seenUppers.insert(upper)
            #expect(value % step == 0, "0〜\(upper)（\(step) 刻み）で \(value) が出た")
            if upper == 10, value % 5 != 0 { sawNonMultipleOfFiveAtTen = true }
        }
        // 乱数抽選が片方の option しか返さない退行（resolveRange の潰れ）もここで捕まえる
        #expect(seenUppers == Set(stepByUpper.keys), "両方の上端が出ていない: \(seenUppers)")
        // step=1 の `% 1 == 0` は恒真なので、これが無いと生成器が promptStep を無視して
        // 常に 5 刻みを使う退行でも通ってしまう（level3DecimalUsesFineStep と同じ型）
        #expect(sawNonMultipleOfFiveAtTen, "0〜10（1 刻み）で 5 の倍数以外が 1 度も出なかった（step=1 経路が失われている）")
    }

    @Test("小数お題は 2 桁表記で、表示と目標比率が一致する")
    func decimalPromptMatchesTarget() {
        for seed in UInt64(0)..<500 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            let question = generator.make(
                type: .decimalValue,
                parameters: Self.standardParameters,
                using: &rng
            )
            #expect(question.promptText.hasPrefix("0."))
            #expect(Double(question.promptText).map { abs($0 - question.target) < 1e-12 } == true)
        }
    }

    @Test("パーセントお題は % 付きで、値を 100 で割ると目標比率になる")
    func percentPromptMatchesTarget() {
        for seed in UInt64(0)..<500 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            let question = generator.make(
                type: .percent,
                parameters: Self.standardParameters,
                using: &rng
            )
            #expect(question.promptText.hasSuffix("%"))
            let digits = question.promptText.dropLast()
            #expect(Int(digits).map { abs(Double($0) / 100 - question.target) < 1e-12 } == true)
        }
    }

    @Test("入口帯（Lv1）のパーセントお題は 10% 刻み")
    func entryBandPercentUsesTenPercentSteps() {
        let parameters = LevelCurve.standard.stage(for: 1).parameters
        for seed in UInt64(0)..<500 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            let question = generator.make(type: .percent, parameters: parameters, using: &rng)
            guard let value = Int(question.promptText.dropLast()) else {
                Issue.record("パーセント値を読めない: \(question.promptText)")
                return
            }
            #expect(value % 10 == 0)
            #expect(value >= 10 && value <= 90)
        }
    }

    @Test("分数お題は既約で、分母がパラメータの範囲に収まり、値が目標比率と一致する")
    func fractionPromptIsIrreducible() {
        for seed in UInt64(0)..<500 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            let question = generator.make(
                type: .fraction,
                parameters: Self.standardParameters,
                using: &rng
            )
            let parts = question.promptText.split(separator: "/").compactMap { Int($0) }
            #expect(parts.count == 2)
            guard parts.count == 2 else { return }
            let (numerator, denominator) = (parts[0], parts[1])
            #expect((2...9).contains(denominator))
            #expect(numerator > 0 && numerator < denominator)
            #expect(QuestionGenerator.greatestCommonDivisor(numerator, denominator) == 1)
            #expect(abs(Double(numerator) / Double(denominator) - question.target) < 1e-12)
        }
    }

    @Test("無理数お題はテーブルの項目そのもの")
    func irrationalPromptComesFromTable() {
        for seed in UInt64(0)..<500 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            let question = generator.make(
                type: .irrational,
                parameters: Self.standardParameters,
                using: &rng
            )
            let match = IrrationalConstants.all.first { $0.text == question.promptText }
            #expect(match != nil)
            #expect(match.map { abs($0.value - question.target) < 1e-12 } == true)
        }
    }

    @Test("同じ seed なら同じお題列になる")
    func generationIsDeterministic() {
        func sequence(seed: UInt64) -> [String] {
            var rng = SeededRandomNumberGenerator(seed: seed)
            return (1...20).map { generator.make(level: $0 % GameConfig.maxLevel + 1, using: &rng).promptText }
        }
        #expect(sequence(seed: 7) == sequence(seed: 7))
    }
}
