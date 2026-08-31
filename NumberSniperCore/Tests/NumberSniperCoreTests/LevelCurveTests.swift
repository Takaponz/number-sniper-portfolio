import Testing
import Foundation
@testable import NumberSniperCore

@Suite("単一レベルカーブの不変条件")
struct LevelCurveTests {
    static let curve = LevelCurve.standard

    // MARK: - 速度カーブ

    /// r = 0.94 / base 2.6 / min 1.35 のカーブ。**この期待値は設計値なので、
    /// 実装に合わせて書き換えてはいけない**（落ちたら実装側を直す）
    static let expectedDurations: [TimeInterval] = [
        2.6,                        // Lv1
        2.6 * pow(0.94, 1),         // Lv2
        2.6 * pow(0.94, 2),         // Lv3
        2.6 * pow(0.94, 3),         // Lv4
        2.6 * pow(0.94, 4),         // Lv5
        2.6 * pow(0.94, 5),         // Lv6
        2.6 * pow(0.94, 6),         // Lv7
        2.6 * pow(0.94, 7),         // Lv8
        2.6 * pow(0.94, 8),         // Lv9
        2.6 * pow(0.94, 9),         // Lv10
        2.6 * pow(0.94, 10),        // Lv11
        1.35,                       // Lv12（下限に張り付く）
    ]

    @Test("片道スイープ時間は Lv1〜12 で設計値と一致する")
    func durationsMatchDesignTable() throws {
        // 前提条件のガードなので `#expect` ではなく `try #require`。`#expect` は失敗を
        // 記録しても実行を継続するので、表が足りないときに直後の添字が範囲外に突っ込む
        try #require(Self.expectedDurations.count == GameConfig.maxLevel)
        for level in 1...GameConfig.maxLevel {
            let actual = SweepSchedule.duration(level: level, curve: Self.curve)
            #expect(
                abs(actual - Self.expectedDurations[level - 1]) < 1e-9,
                "Lv\(level): \(actual) != \(Self.expectedDurations[level - 1])"
            )
        }
    }

    @Test("下限スイープに張り付くのは Lv12 から")
    func clampLevelIsFixed() {
        // 減衰率を 0.94 → 0.945 のように緩めると下限が到達不能になり、数表が嘘になる。
        // 「どのレベルで張り付くか」を固定しないと、その変更が全 pass のまま通ってしまう
        #expect(SweepSchedule.duration(level: 12, curve: Self.curve) == Self.curve.minSweepSeconds)
        #expect(SweepSchedule.duration(level: 11, curve: Self.curve) > Self.curve.minSweepSeconds)
    }

    @Test("レベルが上がるほど短くなる（単調非増加）")
    func monotonicallyDecreases() {
        for level in 1..<GameConfig.maxLevel {
            #expect(
                SweepSchedule.duration(level: level + 1, curve: Self.curve)
                    <= SweepSchedule.duration(level: level, curve: Self.curve)
            )
        }
    }

    @Test("Lv1 は共通の初速そのもの")
    func levelOneUsesBase() {
        #expect(abs(SweepSchedule.duration(level: 1, curve: Self.curve) - GameConfig.baseSweepSeconds) < 1e-9)
    }

    // MARK: - 判定窓とフレーム格子
    //
    // 採点は `GameViewModel.lastDrawnTime`（TimelineView が最後に描いたフレーム時刻）
    // 基準なので、止められる位置は**フレーム間隔の格子**になる。PERFECT 窓（全幅 2%）に
    // 格子点がいくつ入るかが、下限スイープの実質的な下限を決める。

    /// PERFECT 窓（全幅 2%）に入るフレーム格子点の数
    static func frameGridPoints(refreshHz: Double) -> Int {
        let windowSeconds = 2 * curve.minSweepSeconds * Double(GameConfig.perfectThreshold) / 10_000
        return Int(windowSeconds * refreshHz)
    }

    @Test("ProMotion 機（120Hz）では PERFECT 窓に格子が 3 点以上入る")
    func perfectWindowHasEnoughGridPointsOnProMotion() {
        // 120Hz が出た場合の理論値。**実機（iPhone 16 Pro / iOS 26.5.2）では 60Hz 張り付きで、
        // この経路は現状使われていない**。`Config/Info.plist` の
        // `CADisableMinimumFrameDuration` / `CADisableMinimumFrameDurationOnPhone` を
        // 個別に実測してどちらも 60Hz だったため、ProMotion オプトインは 2026-08-05 に打ち切った
        // （Task 1）。このテストは将来 120Hz が出るようになったときの回帰ガードとして残す。
        // **実行時の前提には使わないこと**（現行の手触りを支えているのは
        // `perfectWindowSurvivesOn60Hz` の方）
        #expect(Self.frameGridPoints(refreshHz: 120) >= 3)
    }

    @Test("60Hz 機・低電力モードでも PERFECT 窓に格子が 1 点以上入る")
    func perfectWindowSurvivesOn60Hz() {
        // iPhone SE や無印 iPhone は ProMotion 非搭載で 60Hz のまま。低電力モードの
        // ProMotion 機も同じ。Lv12 の PERFECT 窓は全幅 27ms なので 60Hz では格子が
        // 1〜2 点しか入らない。**上級帯は格子が粗いと承知のうえで採用している**
        // （下限を 1.7 秒まで上げれば 2 点確保できるが、そうするとカーブ表全体を引き直す）
        #expect(Self.frameGridPoints(refreshHz: 60) >= 1)
    }

    // MARK: - ステージ構造

    @Test("Lv1〜12 のどのレベルにもステージが 1 つだけ対応する")
    func stagesCoverEveryLevelExactlyOnce() {
        for level in 1...GameConfig.maxLevel {
            let matches = Self.curve.stages.filter { $0.levels.contains(level) }
            #expect(matches.count == 1, "Lv\(level) に対応するステージが \(matches.count) 個")
        }
    }

    /// 設計表の「出るお題」列。**この期待値は設計値なので、実装に合わせて書き換えてはいけない**
    ///
    /// 秒数・本数・レンジ様式は他のテストが設計値リテラルで固定しているのに、types だけは
    /// どのテストも「どこかの帯に出れば良い」「比率が範囲内なら良い」までしか見ておらず、
    /// 当時の Lv7（＝ 現 Lv4）を `[.decimalValue, .percent]` → `[.percent]` に変えても
    /// 全 pass してしまっていた。
    /// Task 4 以降で types を触るので、そこに入る前に列ごと固定する
    @Test("各レベルのお題タイプは設計表どおり", arguments: [
        (1, [QuestionType.percent]),
        (2, [.fraction]),
        (3, [.decimalValue]),
        (4, [.decimalValue, .percent]),
        (5, [.arithmetic]),
        (6, [.arithmetic]),
        (7, [.fraction]),
        (8, [.decimalValue, .percent, .fraction]),
        (9, [.customRange]),
        (10, [.customRangeDecimal, .customRange, .decimalValue, .percent, .fractionSum]),
        (11, [.customRange, .customRangeDecimal, .irrational]),
        (12, [.customRange, .customRangeDecimal, .decimalValue, .squareRoot]),
    ])
    func typesMatchDesignTable(level: Int, expected: [QuestionType]) {
        let types = Self.curve.stage(for: level).types
        // 集合で比べるのは設計表が並び順まで規定していないため。ただし重複は
        // `randomElement` の一様抽選でそのまま出現率になるので件数も併せて固定する
        #expect(Set(types) == Set(expected), "Lv\(level): \(types)")
        #expect(types.count == expected.count, "Lv\(level): タイプが重複している \(types)")
    }

    @Test("設計表が名指ししている生成パラメータ（刻み・演算子）も設計表どおり")
    func generationParametersMatchDesignTable() {
        // 設計表の「パーセント（10%刻み）」「四則演算（＋−のみ）」「四則演算（×÷追加）」は
        // types だけでは表現できない列。typesMatchDesignTable と対にして表の全列を埋める
        // （これが無いと Lv1 の刻みを 10 → 1 に変えても、Lv5 に ×÷ を足しても全 pass する）
        #expect(Self.curve.stage(for: 1).parameters.percentStep == 10)
        // パーセントを出す他の帯。Lv5-6 は入口帯外だが percent を出さないので 10 のまま
        for level in [4, 8, 10] {
            #expect(Self.curve.stage(for: level).parameters.percentStep == 1, "Lv\(level)")
        }
        #expect(Self.curve.stage(for: 5).parameters.arithmeticOperations == [.add, .subtract])
        #expect(
            Set(Self.curve.stage(for: 6).parameters.arithmeticOperations)
                == Set(ArithmeticOperation.allCases)
        )
    }

    @Test("QuestionType.allCases のすべてが、どこかのステージから出せる")
    func everyQuestionTypeIsReachable() {
        let reachable = Set(Self.curve.stages.flatMap(\.types))
        #expect(
            reachable == Set(QuestionType.allCases),
            """
            QuestionType に登場するが、どのステージの types にも入っていないタイプがある。\
            新しいタイプを追加したら必ずどこかのステージの types に加えること。\
            加えないと、そのタイプは一度も生成されず、他のテストの対象にもならない死んだケースになる。
            """
        )
    }

    @Test("制限時間の本数は全ステージで半奇数かつ 2.5 本以上")
    func timeLimitSweepsIsHalfOddEverywhere() {
        // 2S 周期に対して余りが 0.5S か 1.5S なら、三角波の比率はどちらも 0.5 ＝ 中央。
        // 「時間切れ時のカーソル位置が何の情報も持たない」というこの性質が、
        // 時間切れでカーソルを消す表示判断（GameViewModel.showsCursor）の根拠になっている
        for stage in Self.curve.stages {
            let remainder = stage.roundTimeLimitSweeps.truncatingRemainder(dividingBy: 2)
            #expect(
                abs(remainder - 0.5) < 1e-9 || abs(remainder - 1.5) < 1e-9,
                "Lv\(stage.levels) の \(stage.roundTimeLimitSweeps) 本は半奇数でない"
            )
            #expect(stage.roundTimeLimitSweeps >= 2.5, "Lv\(stage.levels) が下限 2.5 本を割っている")
        }
    }

    @Test("制限時間の段差は Lv5 → Lv6 の 1 箇所だけ")
    func timeLimitStepHappensOnlyOnce() {
        // 半奇数の制約で 3.0 本が作れないので段差は必ず生まれる。**位置は Lv6 に据え置く。**
        // ~~第1ライン（Lv9）ではなく上級帯の入口（Lv10）へ分離する~~ は 2026-08-26 に撤回した
        // （2026-08-25 第3弾で一度入れた判断）。廃止理由: レベル並び替え後の実機所感が
        // 「制限時間は今のままで気持ちよかった」で、秒のリズムをレベル番号ごとに
        // 変えないことを優先したため。**このテストが崖の位置の唯一の固定装置**で、
        // 段差が増えると意図しない場所で「急に忙しくなった」と感じさせてしまう
        var stepLevels: [Int] = []
        for level in 2...GameConfig.maxLevel {
            let previous = Self.curve.stage(for: level - 1).roundTimeLimitSweeps
            let current = Self.curve.stage(for: level).roundTimeLimitSweeps
            if abs(previous - current) > 1e-9 { stepLevels.append(level) }
        }
        #expect(stepLevels == [6], "本数が変わるレベル: \(stepLevels)")
        #expect(abs(Self.curve.stage(for: 5).roundTimeLimitSweeps - 3.5) < 1e-9)
        #expect(abs(Self.curve.stage(for: 6).roundTimeLimitSweeps - 2.5) < 1e-9)
        // 第1ライン（Lv9）は 2.5 本側 ＝ 崖の位置と第1ラインの位置は別。
        // **これは上の 3 つから含意される冗長なアサート**（`stepLevels == [6]` が
        // Lv6〜Lv12 の全一致を強制するので、崖を動かす改変は必ずそちらで先に落ちる）。
        // 弁別力のためではなく、「崖 ≠ 第1ライン」という 2026-08-26 変更 (4) の帰結を
        // テストの上で読めるようにするために置いている
        #expect(abs(Self.curve.stage(for: 9).roundTimeLimitSweeps - 2.5) < 1e-9)
    }

    @Test("制限時間は片道スイープの roundTimeLimitSweeps 本ぶん")
    func timeLimitIsMultipleOfSweep() {
        for level in 1...GameConfig.maxLevel {
            let expected = SweepSchedule.duration(level: level, curve: Self.curve)
                * Self.curve.stage(for: level).roundTimeLimitSweeps
            #expect(abs(SweepSchedule.roundTimeLimit(level: level, curve: Self.curve) - expected) < 1e-9)
        }
    }

    @Test("時間切れの瞬間、カーソルは必ず数直線の中央にいる")
    func cursorIsAtCenterWhenTimeExpires() {
        for level in 1...GameConfig.maxLevel {
            let ratio = CursorClock.ratio(
                elapsed: SweepSchedule.roundTimeLimit(level: level, curve: Self.curve),
                sweepDuration: SweepSchedule.duration(level: level, curve: Self.curve)
            )
            #expect(abs(ratio - 0.5) < 1e-9, "Lv\(level)")
        }
    }

    @Test("2 回目のチャンス（復路）は締め切りの半周ぶん以上手前に来る")
    func secondChanceHasMarginBeforeDeadline() {
        for level in 1...GameConfig.maxLevel {
            let s = SweepSchedule.duration(level: level, curve: Self.curve)
            let limit = SweepSchedule.roundTimeLimit(level: level, curve: Self.curve)
            for target in [GameConfig.minTarget, 0.5, GameConfig.maxTarget] {
                #expect(target * s < limit, "Lv\(level) t=\(target)")
                #expect((2 - target) * s <= limit - 0.5 * s, "Lv\(level) t=\(target)")
            }
        }
    }

    @Test("目標が左端寄り（t < 0.5）なら 3 回目のチャンスまで間に合う", arguments: [0.05, 0.25, 0.49])
    func lowTargetsGetAThirdChance(target: Double) {
        // t = 0.05 の 1 点だけを見ると境界（t < 0.5）の弁別力がない。
        // 境界直下の 0.49 まで回して初めて「t < 0.5 なら」の主張が検証される
        for level in 1...GameConfig.maxLevel {
            let s = SweepSchedule.duration(level: level, curve: Self.curve)
            let limit = SweepSchedule.roundTimeLimit(level: level, curve: Self.curve)
            #expect((2 + target) * s < limit, "Lv\(level) t=\(target)")
        }
    }

    // MARK: - 難しさの 2 本のライン

    // ⚠️ このセクションの関数名に `Difficulty` を使わないこと。Task 6 Step 8 の
    // 受け入れゲートが Swift ファイル全体で `Difficulty|difficulty` を検出するため

    @Test("第1ライン: Lv1-8 は固定レンジ、Lv9 で初めて変則レンジのお題が出る")
    func firstHardLineIsAtLevelNine() {
        // 判定は customRangeStyle ではなく types で行う。2026-08-25 第3弾の並び替えで
        // Lv4/7/8 も分母 2〜9・1% 刻みのために `LevelCurveTable.standard()`（= .arbitrary）を
        // 使うようになり、レンジ様式だけでは Lv9 と弁別できなくなったため。
        // 実際に変則レンジのお題が出るかどうかは types 側で決まる
        let customRangeTypes: Set<QuestionType> = [.customRange, .customRangeDecimal]
        for level in 1...8 {
            let types = Set(Self.curve.stage(for: level).types)
            #expect(
                types.isDisjoint(with: customRangeTypes),
                "Lv\(level) が第1ラインより手前で変則レンジのお題を出している: \(types)"
            )
        }
        #expect(Self.curve.stage(for: 9).types.contains(.customRange), "Lv9 で変則レンジが出ない")
        // types だけだと Lv9 のパラメータを beginner()（= roundFromZero）に付け替えても
        // 全 pass で素通りする。旧テストが customRangeStyle で担っていた回帰検出をここで引き継ぐ
        #expect(
            Self.curve.stage(for: 9).parameters.customRangeStyle == .arbitrary(widths: 20...50),
            "Lv9 のレンジ様式が 2 桁の任意レンジ（幅 20〜50）でない"
        )
    }

    @Test("第2ライン: 3 桁レンジは Lv11 で初めて出る")
    func secondHardLineIsAtLevelEleven() {
        for level in 1...10 {
            if case .threeDigit = Self.curve.stage(for: level).parameters.customRangeStyle {
                Issue.record("Lv\(level) が第2ラインより手前で 3 桁レンジになっている")
            }
        }
        for level in 11...GameConfig.maxLevel {
            guard case .threeDigit = Self.curve.stage(for: level).parameters.customRangeStyle else {
                Issue.record("Lv\(level) が 3 桁レンジでない")
                continue
            }
        }
    }

    @Test("暗算の重いお題は 1 帯 1 種のスパイスで、出現率は 20〜35%")
    func spiceTypesAreRareAndIsolated() {
        // 暗算軸は「難易度の上げ方」ではなく「対象年齢の広げ方」。上級者を殺すのは
        // 目測軸（変則レンジ・3桁レンジ・速度）であるべきなので、暗算の重いタイプが
        // 主軸になっていないことを固定する。
        //
        // 上限を 35% にしてあるのは、**この比率で型構成を決めさせないため**。20〜25% に
        // 締めると Lv11 のような 3 タイプの帯に易しい型を員数合わせで足す圧力が生まれ、
        // 最高帯が薄まる。比率は「主軸になっていないこと」の確認であって、設計目標ではない。
        // types は randomElement で一様抽選されるので、この比率がそのまま出現率になる
        let spices: Set<QuestionType> = [.fractionSum, .irrational, .squareRoot]
        var seen: Set<QuestionType> = []
        for stage in Self.curve.stages {
            let inStage = stage.types.filter { spices.contains($0) }
            guard !inStage.isEmpty else { continue }
            #expect(inStage.count == 1, "Lv\(stage.levels) にスパイスが \(inStage.count) 種入っている")
            let rate = Double(inStage.count) / Double(stage.types.count)
            #expect(rate >= 0.20 && rate <= 0.35, "Lv\(stage.levels) のスパイス出現率 \(rate)")
            seen.formUnion(inStage)
        }
        #expect(seen == spices, "出番のないスパイスがある: \(spices.subtracting(seen))")
    }

    @Test("小学校の範囲（四則演算・分母2〜4の分数）は Lv6 までに収まる")
    func elementarySchoolBandEndsAtLevelSix() {
        #expect(Self.curve.stage(for: 2).parameters.fractionDenominators == 2...4)
        // 分母が広がるのは標準帯に入ってから
        #expect(Self.curve.stage(for: 7).parameters.fractionDenominators == 2...9)
        for level in 7...GameConfig.maxLevel {
            #expect(
                !Self.curve.stage(for: level).types.contains(.arithmetic),
                "Lv\(level) に四則演算が残っている"
            )
        }
    }

    // MARK: - 生成パラメータの成立条件

    @Test("四則演算を出す帯は 0 始まりレンジで、演算子が空でない")
    func arithmeticStagesUseRoundFromZeroRange() {
        for stage in Self.curve.stages where stage.types.contains(.arithmetic) {
            guard case .roundFromZero = stage.parameters.customRangeStyle else {
                Issue.record("Lv\(stage.levels) が arithmetic を 0 始まり以外のレンジで出そうとしている")
                continue
            }
            #expect(!stage.parameters.arithmeticOperations.isEmpty)
        }
    }

    @Test("四則演算を出す帯は、どの U・どの演算子でも候補が空にならない")
    func arithmeticStagesAlwaysHaveCandidates() {
        for stage in Self.curve.stages where stage.types.contains(.arithmetic) {
            guard case .roundFromZero(let options) = stage.parameters.customRangeStyle else { continue }
            for option in options {
                for operation in stage.parameters.arithmeticOperations {
                    let candidates = QuestionGenerator.arithmeticCandidates(
                        operation: operation,
                        upper: option.upper
                    )
                    #expect(
                        !candidates.isEmpty,
                        "Lv\(stage.levels): \(operation) / U=\(option.upper) の候補が空"
                    )
                }
            }
        }
    }

    @Test("0 始まりレンジの刻みは、目標比率の範囲に 2 つ以上の値を残す")
    func roundRangeStepLeavesEnoughChoices() {
        for stage in Self.curve.stages {
            guard case .roundFromZero(let options) = stage.parameters.customRangeStyle else { continue }
            for option in options {
                let minOffset = Int((GameConfig.minTarget * Double(option.upper)).rounded(.up))
                let maxOffset = Int((GameConfig.maxTarget * Double(option.upper)).rounded(.down))
                let lowestIndex = (minOffset + option.promptStep - 1) / option.promptStep
                let highestIndex = maxOffset / option.promptStep
                #expect(
                    highestIndex - lowestIndex >= 1,
                    "0〜\(option.upper) を \(option.promptStep) 刻みにすると選択肢が足りない"
                )
            }
        }
    }

    @Test("分数の和を出す帯は候補が空にならない")
    func fractionSumStagesAlwaysHaveCandidates() {
        for stage in Self.curve.stages where stage.types.contains(.fractionSum) {
            let candidates = QuestionGenerator.fractionSumCandidates(
                denominators: stage.parameters.fractionDenominators
            )
            #expect(!candidates.isEmpty, "Lv\(stage.levels) の分数の和の候補が空")
        }
    }

    @Test("パーセントの刻みは目標比率の範囲に少なくとも 1 つ値を持つ")
    func percentStepFitsInsideTargetBounds() {
        for stage in Self.curve.stages where stage.types.contains(.percent) {
            let step = stage.parameters.percentStep
            #expect(step >= 1)
            let lower = Int((GameConfig.minTarget * 100).rounded())
            let upper = Int((GameConfig.maxTarget * 100).rounded())
            #expect(((lower + step - 1) / step) * step <= upper, "\(step)% 刻みでは目標比率の範囲に値がない")
        }
    }

    // MARK: - カーブ → generator への橋渡し
    //
    // 以下は必ず `make(level:curve:using:)` 経由で呼ぶ。`make(type:parameters:using:)` を
    // 直接呼ぶテストは `stage.parameters` が正しく渡されているかを検証できない

    @Test("どのレベルでも、お題タイプとレンジのペア制約を満たす")
    func typeAndRangeAreAlwaysPaired() {
        let generator = QuestionGenerator()
        for seed in UInt64(0)..<300 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            for level in 1...GameConfig.maxLevel {
                let question = generator.make(level: level, using: &rng)
                if question.type.requiredRangeIsUnit {
                    #expect(question.range == .unit, "Lv\(level) \(question.type)")
                } else {
                    #expect(question.range.allowsIntegerPrompts, "Lv\(level) \(question.type)")
                }
            }
        }
    }

    @Test("どのレベルでも目標比率は 0.05〜0.95 に収まる")
    func targetAlwaysInsideBounds() {
        let generator = QuestionGenerator()
        for seed in UInt64(0)..<300 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            for level in 1...GameConfig.maxLevel {
                let question = generator.make(level: level, using: &rng)
                #expect(question.target >= GameConfig.minTarget, "Lv\(level) \(question.promptText)")
                #expect(question.target <= GameConfig.maxTarget, "Lv\(level) \(question.promptText)")
            }
        }
    }

    @Test("Lv5 は make(level:curve:using:) 経由でも足し算・引き算しか出ない")
    func level5OnlyUsesAddAndSubtract() {
        let generator = QuestionGenerator()
        for seed in UInt64(0)..<300 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            let question = generator.make(level: 5, using: &rng)
            #expect(!question.promptText.contains("×"), "seed \(seed): \(question.promptText)")
            #expect(!question.promptText.contains("÷"), "seed \(seed): \(question.promptText)")
        }
    }

    @Test("Lv6 は掛け算・割り算も出る（Lv5 からの演算子拡大の確認）")
    func level6CanProduceMultiplyAndDivide() {
        // Lv5 の制限（+ − のみ）だけを見るテストは、全レベルが + − 固定でも通ってしまう。
        // Lv6 で × と ÷ が実際に出ることまで確認して、演算子集合が帯ごとに変わっていることを裏取りする
        let generator = QuestionGenerator()
        var sawMultiply = false
        var sawDivide = false
        for seed in UInt64(0)..<300 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            let question = generator.make(level: 6, using: &rng)
            if question.promptText.contains("×") { sawMultiply = true }
            if question.promptText.contains("÷") { sawDivide = true }
        }
        #expect(sawMultiply, "300 seed 回しても Lv6 で × が 1 度も出なかった")
        #expect(sawDivide, "300 seed 回しても Lv6 で ÷ が 1 度も出なかった")
    }

    @Test("Lv3 の 0〜1 小数は 0.01 刻み（Lv4 と同分布）のまま")
    func level3DecimalUsesFineStep() {
        // 入口帯の「刻みを粗くする」規約（Lv1 percent の 10% 刻み）は decimalValue に
        // 適用しない — 0.1 刻みにすると表示が `0.10`/`0.20` になり percent と
        // 見分けのつかないお題になるため（QuestionGenerator.swift の設計コメントが正、
        // spec 2026-08-25 変更ノート副作用 (3) で受容）。将来 decimalValue が
        // percentStep を尊重するよう変わったとき、Lv3 が黙って 0.1 刻みに変わるのを防ぐ
        // （同分布の相手は 2026-08-25 第3弾で Lv7 → Lv4 に移った）
        let generator = QuestionGenerator()
        var sawFineValue = false
        for seed in UInt64(0)..<300 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            let question = generator.make(level: 3, using: &rng)
            let percentValue = Int((question.target * 100).rounded())
            #expect((5...95).contains(percentValue), "seed \(seed): \(question.promptText)")
            if percentValue % 10 != 0 { sawFineValue = true }
        }
        #expect(sawFineValue, "300 seed 回しても 10% 刻みに乗らない値が 1 度も出なかった（0.01 刻みが失われている）")
    }

    @Test("入口帯 Lv1-4 は基準ライン（0〜1）が一切変わらない")
    func entryLevelsShareUnitBaseline() {
        // 2026-08-25 の並び替えの狙いそのもの。数直線の両端が Lv4 まで 0 と 1 のまま
        // 固定されることを、生成経路（make(level:curve:using:)）で固定する。
        // Lv1-4 に非 unit タイプを足すとここが落ちる（第3弾で Lv4 のミックス帯まで伸びた。
        // Lv4 は standard() を使うが types が 0〜1 レンジのタイプだけなので unit のまま）
        let generator = QuestionGenerator()
        for seed in UInt64(0)..<300 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            for level in 1...4 {
                let question = generator.make(level: level, using: &rng)
                #expect(question.range == .unit, "Lv\(level) seed \(seed): \(question.promptText)")
            }
        }
    }

    @Test("算数帯 Lv5-6 の基準ラインは常に 0〜100")
    func arithmeticLevelsUseFixedHundredRange() {
        // 2026-08-25 第2弾の狙いそのもの。0〜100 は 0〜1 と位置が同一（ラベルが ×100 なだけ）
        // なので、Lv1-6 全体が同じ位置感覚で通せる。roundFromZero の options に
        // 別レンジ（0〜10/20/50 等）を足し戻すとここが落ちる
        let generator = QuestionGenerator()
        for seed in UInt64(0)..<300 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            for level in 5...6 {
                let question = generator.make(level: level, using: &rng)
                #expect(
                    question.range == .integers(lower: 0, upper: 100),
                    "Lv\(level) seed \(seed): \(question.promptText)"
                )
            }
        }
    }

    @Test("Lv1 のパーセントは 10% 刻みのまま")
    func level1PercentStaysInTenPercentSteps() {
        let generator = QuestionGenerator()
        let expectedStep = LevelCurve.standard.stage(for: 1).parameters.percentStep
        for seed in UInt64(0)..<300 {
            var rng = SeededRandomNumberGenerator(seed: seed)
            let question = generator.make(level: 1, using: &rng)
            guard question.promptText.hasSuffix("%"), let value = Int(question.promptText.dropLast()) else {
                Issue.record("Lv1 のお題が percent の形式でない: \(question.promptText)")
                continue
            }
            #expect(value % expectedStep == 0, "seed \(seed): \(question.promptText)")
        }
    }

    @Test("分数の分母は帯ごとに変わる（Lv2 は 2〜4、Lv7 は 2〜9）")
    func fractionDenominatorsAreReadPerStage() {
        let generator = QuestionGenerator()
        // Lv2 の 2...4 は Lv7 の 2...9 に包含されるので、範囲アサートだけでは
        // 「Lv7 が Lv2 のパラメータを誤って読む」回帰を弁別できない。
        // Lv7 で 5 以上の分母が実際に出ることまで見る
        var sawWideDenominatorAtLevel7 = false
        for (level, expectedRange) in [(2, 2...4), (7, 2...9)] {
            for seed in UInt64(0)..<300 {
                var rng = SeededRandomNumberGenerator(seed: seed)
                let question = generator.make(level: level, using: &rng)
                let parts = question.promptText.split(separator: "/").compactMap { Int($0) }
                guard parts.count == 2 else {
                    Issue.record("Lv\(level) のお題が fraction の形式でない: \(question.promptText)")
                    continue
                }
                #expect(
                    expectedRange.contains(parts[1]),
                    "Lv\(level) seed \(seed): 分母 \(parts[1]) が \(expectedRange) の範囲外 (\(question.promptText))"
                )
                if level == 7 && parts[1] >= 5 { sawWideDenominatorAtLevel7 = true }
            }
        }
        #expect(sawWideDenominatorAtLevel7, "300 seed 回しても Lv7 で分母 5 以上が 1 度も出なかった")
    }

    @Test("Lv11-12 の 3 桁レンジは 999 を超えず、幅も設定通りに保たれる")
    func threeDigitRangeStaysWithinCeilingAndWidth() {
        guard case .threeDigit(_, let widths) = LevelCurve.standard.stage(for: 12).parameters.customRangeStyle else {
            Issue.record("Lv12 が threeDigit レンジでなくなっている")
            return
        }
        let generator = QuestionGenerator()
        var sawIntegerRange = false
        for level in 11...GameConfig.maxLevel {
            for seed in UInt64(0)..<300 {
                var rng = SeededRandomNumberGenerator(seed: seed)
                let question = generator.make(level: level, using: &rng)
                guard case .integers(let lower, let upper) = question.range else { continue }
                sawIntegerRange = true
                #expect(upper <= 999, "Lv\(level) の整数レンジが 999 の上限を超えた: \(lower)〜\(upper)")
                #expect(
                    widths.contains(upper - lower),
                    "Lv\(level) の整数レンジの幅が設定の \(widths) から外れた: \(lower)〜\(upper)（幅 \(upper - lower)）"
                )
            }
        }
        #expect(sawIntegerRange, "300 seed 回しても .integers レンジのお題が 1 つも出なかった。これでは何も検証できていない")
    }
}
