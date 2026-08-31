import Foundation

/// レベルとカーブに応じたお題を生成する。
///
/// お題タイプとレンジは必ずペアで決める（`QuestionType.requiredRangeIsUnit` が正）。
/// 変則レンジには `customRange` ／ `arithmetic` ／ `customRangeDecimal` のお題のみ、
/// `decimalValue` ／ 分数／パーセント／無理数／平方根／分数の和は 0〜1 レンジのみ。
/// 目標比率は常に 0.05〜0.95 に収める（端は判定が片側に潰れるため）。
public struct QuestionGenerator: Sendable {
    public init() {}

    /// レベルからお題を 1 問生成する。
    public func make(
        level: Int,
        curve: LevelCurve = .standard,
        using rng: inout some RandomNumberGenerator
    ) -> Question {
        let stage = curve.stage(for: level)
        // stage.types は空にならない（LevelStage.init の precondition で保証）
        let type = stage.types.randomElement(using: &rng) ?? .decimalValue
        return make(type: type, parameters: stage.parameters, using: &rng)
    }

    /// タイプとパラメータを指定して 1 問生成する。
    public func make(
        type: QuestionType,
        parameters: QuestionParameters,
        using rng: inout some RandomNumberGenerator
    ) -> Question {
        switch type {
        case .decimalValue:
            // step は常に 1（プロファイルの percentStep は見ない）。10% 刻みにすると
            // 表示が `0.10` / `0.20` になり、2 桁表示が売りの decimalValue が
            // percent と見分けのつかないお題になってしまう
            let percentValue = Self.percentInTargetBounds(step: 1, using: &rng)
            let target = Double(percentValue) / 100
            return Question(
                type: .decimalValue,
                promptText: String(format: "%.2f", target),
                range: .unit,
                target: target
            )

        case .percent:
            return makePercent(step: parameters.percentStep, using: &rng)

        case .fraction:
            return makeFraction(denominators: parameters.fractionDenominators, using: &rng)

        case .customRange:
            let range = Self.resolveRange(style: parameters.customRangeStyle, using: &rng)
            return makeCustomRange(
                lower: range.lower,
                upper: range.upper,
                promptStep: range.promptStep,
                using: &rng
            )

        case .irrational:
            // テーブルは空にならない（QuestionModelTests で固定）
            let constant = IrrationalConstants.all.randomElement(using: &rng)
                ?? IrrationalConstants.all[0]
            return Question(
                type: .irrational,
                promptText: constant.text,
                range: .unit,
                target: constant.value
            )

        case .arithmetic:
            // arithmetic は 0 始まりレンジ専用（LevelCurveTests で固定）
            let range = Self.resolveRange(style: parameters.customRangeStyle, using: &rng)
            return makeArithmetic(
                upper: range.upper,
                operations: parameters.arithmeticOperations,
                using: &rng
            )

        case .fractionSum:
            return makeFractionSum(denominators: parameters.fractionDenominators, using: &rng)

        case .customRangeDecimal:
            let range = Self.resolveRange(style: parameters.customRangeStyle, using: &rng)
            return makeCustomRangeDecimal(lower: range.lower, upper: range.upper, using: &rng)

        case .squareRoot:
            return makeSquareRoot(using: &rng)
        }
    }

    // MARK: - タイプ別

    /// パーセントお題。`step` 刻みの値を出す。
    /// 出荷カーブでは **Lv1 だけ 10**、パーセントを出す他の帯（Lv4・8・10）は 1。
    /// 「入口帯かどうか」では決まらない — 入口帯の Lv4 が 1 で、入口外の Lv5-6 は 10 のまま
    /// （percent を出さない帯なので値は使われない）。
    public func makePercent(
        step: Int,
        using rng: inout some RandomNumberGenerator
    ) -> Question {
        let percentValue = Self.percentInTargetBounds(step: step, using: &rng)
        return Question(
            type: .percent,
            promptText: "\(percentValue)%",
            range: .unit,
            target: Double(percentValue) / 100
        )
    }

    /// 分数お題。分母は `denominators` の範囲から選ぶ。
    public func makeFraction(
        denominators: ClosedRange<Int>,
        using rng: inout some RandomNumberGenerator
    ) -> Question {
        let (numerator, denominator) = Self.irreducibleFraction(
            denominators: denominators,
            using: &rng
        )
        return Question(
            type: .fraction,
            promptText: "\(numerator)/\(denominator)",
            range: .unit,
            target: Double(numerator) / Double(denominator)
        )
    }

    /// 変則レンジ上の整数お題。
    ///
    /// `promptStep` はレンジのスタイルが決める（`LevelCurve+Standard.swift` の
    /// `RoundRangeOption`）。0 始まりキリ番レンジ（出荷カーブは 0〜100 の 1 種）では 5 刻みになり、
    /// 「0〜100 で 63」より「0〜100 で 65」の方が位置を体で掴みやすくなる
    /// （2026-08-25 の並び替えでキリ番お題を出す帯は出荷カーブから消えたが、
    /// 実装は将来の再登場に備えて残している。変則・3 桁レンジは 1 刻み）。
    public func makeCustomRange(
        lower: Int,
        upper: Int,
        promptStep: Int,
        using rng: inout some RandomNumberGenerator
    ) -> Question {
        let width = upper - lower
        let minOffset = Int((GameConfig.minTarget * Double(width)).rounded(.up))
        let maxOffset = Int((GameConfig.maxTarget * Double(width)).rounded(.down))
        let offset = Self.randomMultiple(of: promptStep, in: minOffset...maxOffset, using: &rng)
        return Question(
            type: .customRange,
            promptText: "\(lower + offset)",
            range: .integers(lower: lower, upper: upper),
            target: Double(offset) / Double(width)
        )
    }

    // MARK: - レンジ

    /// スタイルから変則レンジの両端と、お題に出す値の刻みを決める。
    static func resolveRange(
        style: CustomRangeStyle,
        using rng: inout some RandomNumberGenerator
    ) -> (lower: Int, upper: Int, promptStep: Int) {
        switch style {
        case .roundFromZero(let options):
            // `make(level:curve:)` 経由では options は空にならない（`LevelStage.init` の precondition）。
            // ただし public の `make(type:parameters:using:)` からは任意の QuestionParameters が
            // 来うるので、このフォールバックは残す
            let option = options.randomElement(using: &rng) ?? RoundRangeOption(upper: 100, promptStep: 5)
            return (lower: 0, upper: option.upper, promptStep: option.promptStep)

        case .arbitrary(let widths):
            let width = Int.random(in: widths, using: &rng)
            let lower = Int.random(in: 1...(99 - width), using: &rng)
            return (lower: lower, upper: lower + width, promptStep: 1)

        case .threeDigit(let lowerBounds, let widths):
            let width = Int.random(in: widths, using: &rng)
            // 上端を 999 に収めるため、下端の側で先に上限を絞る。
            // あとから `min(999, lower + width)` で切ると、指定した幅より狭いレンジが
            // 黙って出来てしまう（3 桁レンジは幅が広いことが難しさの源なので、
            // ここが縮むと Lv10 が易しくなる）
            let highestLower = min(lowerBounds.upperBound, 999 - width)
            // `highestLower < lowerBounds.lowerBound` になるのは、幅が広すぎて
            // 「下端を lowerBounds に収めつつ上端を 999 に収める」の両方を満たす
            // 下端が存在しないとき。`max(...)` で握りつぶすと上端が 999 を超えた
            // レンジが黙って出来てしまう（このケース自体がテスト済み: 上の「999 を超えず」の
            // コメントが指す保証が崩れる）ので、`makeArithmetic` と同じく
            // 設定側の不備として止めて気づかせる
            precondition(
                highestLower >= lowerBounds.lowerBound,
                "threeDigit(lowerBounds: \(lowerBounds), widths: \(widths)) は width=\(width) のとき "
                    + "lower を \(lowerBounds.lowerBound) 以上に保ったまま upper を 999 以下に収められない"
            )
            let lower = Int.random(in: lowerBounds.lowerBound...highestLower, using: &rng)
            return (lower: lower, upper: lower + width, promptStep: 1)
        }
    }

    // MARK: - 共通ヘルパ

    /// 目標比率の範囲（5〜95）に収まる `step` 刻みのパーセント値。
    static func percentInTargetBounds(
        step: Int,
        using rng: inout some RandomNumberGenerator
    ) -> Int {
        let lower = Int((GameConfig.minTarget * 100).rounded())
        let upper = Int((GameConfig.maxTarget * 100).rounded())
        return randomMultiple(of: step, in: lower...upper, using: &rng)
    }

    /// `bounds` の内側にある `step` の倍数を 1 つ選ぶ。
    /// `step <= 1` のときは `Int.random(in:)` と完全に同じ（既存挙動を保つ）。
    static func randomMultiple(
        of step: Int,
        in bounds: ClosedRange<Int>,
        using rng: inout some RandomNumberGenerator
    ) -> Int {
        guard step > 1 else { return Int.random(in: bounds, using: &rng) }
        let lowestIndex = (bounds.lowerBound + step - 1) / step
        let highestIndex = bounds.upperBound / step
        // 範囲内に倍数が 1 つも無い組は出荷カーブに存在しない
        // （`percent` 経由は LevelCurveTests.percentStepFitsInsideTargetBounds、
        // `makeCustomRange` の promptStep 経由は
        // LevelCurveTests.roundRangeStepLeavesEnoughChoices で固定）
        guard lowestIndex <= highestIndex else { return Int.random(in: bounds, using: &rng) }
        return Int.random(in: lowestIndex...highestIndex, using: &rng) * step
    }

    /// 既約の真分数。分母は `denominators` の範囲。
    /// 分母 2〜13 の真分数は値が 1/13 〜 12/13 なので、目標比率の範囲を必ず満たす。
    static func irreducibleFraction(
        denominators: ClosedRange<Int>,
        using rng: inout some RandomNumberGenerator
    ) -> (numerator: Int, denominator: Int) {
        while true {
            let denominator = Int.random(in: denominators, using: &rng)
            let numerator = Int.random(in: 1..<denominator, using: &rng)
            if greatestCommonDivisor(numerator, denominator) == 1 {
                return (numerator, denominator)
            }
        }
    }

    static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        b == 0 ? abs(a) : greatestCommonDivisor(b, a % b)
    }
}
