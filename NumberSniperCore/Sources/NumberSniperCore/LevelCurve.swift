import Foundation

/// レベル進行そのものが難易度になる、ただ 1 本のカーブ。
///
/// **難易度選択は持たない。** Lv1〜`GameConfig.maxLevel` の進行に「加速」「お題の種類」
/// 「1 問に与える考える時間」をすべて載せる。ライフ 3 のゲームオーバーが選別装置として
/// 働くので、低年齢層は Lv1-6 で止まり、上級者は Lv11-12 に到達する。
///
/// 初速（Lv1 の片道スイープ時間）はここに置かない。`GameConfig.baseSweepSeconds` が正で、
/// 「速さそのものを難易度差にしない」という設計意図を構造で守っている。
public struct LevelCurve: Sendable {
    /// 片道スイープ時間の下限。判定窓がフレーム格子に埋もれない値にする
    public let minSweepSeconds: TimeInterval
    /// レベルごとの減衰率。小さいほど加速が強い
    public let sweepDecayRate: Double
    /// レベル帯ごとのお題構成と制限時間。Lv1〜`GameConfig.maxLevel` を穴なく覆う
    public let stages: [LevelStage]

    /// - Important: `minSweepSeconds` が初速以上だと Lv1 から下限に張り付き、
    ///   「レベルが上がると速くなる」というカーブの前提そのものが消える。
    ///   テストではなく `precondition` で閉じているのは、フィールドに書けてしまう値を
    ///   構造で禁じるため（`GameConfig.baseSweepSeconds` を別ファイルへ移しただけでは、
    ///   `minSweepSeconds` 側から初速を上書きする抜け道が残っていた）
    public init(
        minSweepSeconds: TimeInterval,
        sweepDecayRate: Double,
        stages: [LevelStage]
    ) {
        precondition(
            minSweepSeconds > 0,
            "minSweepSeconds(\(minSweepSeconds)) は正の値にすること"
        )
        precondition(
            minSweepSeconds < GameConfig.baseSweepSeconds,
            "minSweepSeconds(\(minSweepSeconds)) は初速 \(GameConfig.baseSweepSeconds) より短くすること"
        )
        precondition(
            sweepDecayRate > 0 && sweepDecayRate < 1,
            "sweepDecayRate(\(sweepDecayRate)) は 0 < r < 1 にすること"
        )
        precondition(!stages.isEmpty, "stages が空のカーブは作れない")
        // 被覆もここで閉じる。`stage(for:)` は maxLevel まで clamp するだけなので、
        // 覆えていないレベルはクラッシュせず黙って stages[0]（= Lv1 の構成）に落ちる。
        // 半奇数・初速・減衰率を precondition で守るなら、被覆だけテスト依存にする理由はない
        for level in 1...GameConfig.maxLevel {
            let matches = stages.filter { $0.levels.contains(level) }.count
            precondition(matches == 1, "Lv\(level) に対応するステージが \(matches) 個（1 個であること）")
        }
        self.minSweepSeconds = minSweepSeconds
        self.sweepDecayRate = sweepDecayRate
        self.stages = stages
    }

    /// レベルに対応するステージ。
    ///
    /// `stages` は Lv1〜`GameConfig.maxLevel` を穴なく・重複なく覆う
    /// （`init` の `precondition` で固定）。範囲外のレベルは端に丸める。
    /// `init` が `stages` の非空を保証しているので `stages[0]` は安全。
    public func stage(for level: Int) -> LevelStage {
        let clamped = min(max(1, level), GameConfig.maxLevel)
        return stages.first { $0.levels.contains(clamped) } ?? stages[0]
    }
}

/// 1 つのレベル帯で出せるお題・その帯での生成パラメータ・1 問の制限時間。
///
/// パラメータと制限時間を**ステージに持たせる**のが要点。「Lv2 は分母 2〜4、Lv7 は 2〜9」
/// のように同じタイプでも帯で難度が変わり、「Lv1-5 は 3.5 本・Lv6-12 は 2.5 本」のように
/// 考える時間も帯で変わるため、カーブ直下に 1 セットだけ置く形では表現できない。
public struct LevelStage: Sendable {
    public let levels: ClosedRange<Int>
    /// この帯で出しうるタイプ。帯の中ではここから一様に選ぶ
    public let types: [QuestionType]
    public let parameters: QuestionParameters
    /// 1 問の制限時間を片道スイープ何本ぶんにするか。**必ず半奇数**。理由は
    /// `SweepSchedule.roundTimeLimit`
    public let roundTimeLimitSweeps: Double

    public init(
        levels: ClosedRange<Int>,
        types: [QuestionType],
        parameters: QuestionParameters,
        roundTimeLimitSweeps: Double
    ) {
        // 半奇数は Double なので型では縛れない。値の invariant なのでここで止める。
        // 整数本にすると時間切れの瞬間にカーソルが端で止まり、狙って止めたように見える
        let remainder = roundTimeLimitSweeps.truncatingRemainder(dividingBy: 2)
        precondition(
            abs(remainder - 0.5) < 1e-9 || abs(remainder - 1.5) < 1e-9,
            "roundTimeLimitSweeps(\(roundTimeLimitSweeps)) は半奇数にすること"
        )
        precondition(
            roundTimeLimitSweeps >= 2.5,
            "roundTimeLimitSweeps(\(roundTimeLimitSweeps)) が下限の 2.5 本を割っている"
        )
        precondition(!types.isEmpty, "Lv\(levels) にタイプがない")
        // 0 始まりレンジの選択肢が空だと、`QuestionGenerator.resolveRange` の
        // `?? RoundRangeOption(upper: 100, promptStep: 5)` に黙って落ちて、
        // 設定していない「0〜100 / 5 刻み」が出る。テスト側は options を回すループで
        // 検査しているので、空配列だと本体が 1 度も回らず vacuous に全 pass する。
        // 2026-08-25 のレンジ固定で出荷の唯一 option がフォールバックと同値になり、
        // お題からは fallback 発火を区別できなくなった — この precondition が唯一の検出器
        if case .roundFromZero(let options) = parameters.customRangeStyle {
            precondition(!options.isEmpty, "Lv\(levels) の roundFromZero に選択肢がない")
        }
        self.levels = levels
        self.types = types
        self.parameters = parameters
        self.roundTimeLimitSweeps = roundTimeLimitSweeps
    }
}

/// お題生成のパラメータ。
public struct QuestionParameters: Sendable {
    /// 分数・分数の和で使う分母の範囲
    public let fractionDenominators: ClosedRange<Int>
    /// 変則レンジ（`customRange` / `customRangeDecimal` / `arithmetic`）の作り方
    public let customRangeStyle: CustomRangeStyle
    /// 四則演算お題で使う演算子。`arithmetic` を出さない帯では空でよい
    public let arithmeticOperations: [ArithmeticOperation]
    /// パーセントお題の刻み。出荷カーブでは Lv1 だけ 10 で、パーセントを出す他の帯
    /// （Lv4・8・10）は 1。「入口帯かどうか」では決まらない — 入口帯の Lv4 が 1 で、
    /// 入口外の Lv5-6 は 10 のまま（percent を出さない帯なので値は使われない）
    public let percentStep: Int

    public init(
        fractionDenominators: ClosedRange<Int> = 2...9,
        customRangeStyle: CustomRangeStyle = .arbitrary(widths: 20...50),
        arithmeticOperations: [ArithmeticOperation] = [],
        percentStep: Int = 1
    ) {
        // 生成時に trap する設定を構築時に前倒しで止める。
        // 分母 1 は `irreducibleFraction` の `Int.random(in: 1..<1)`（空レンジ）で落ちる
        precondition(
            fractionDenominators.lowerBound >= 2,
            "fractionDenominators(\(fractionDenominators)) の分母は 2 以上にすること"
        )
        // 幅 W = 1 は `makeCustomRange` の目標レンジ ceil(0.05W)...floor(0.95W) が
        // 1...0（空レンジ）になって落ちる。W >= 2 なら [0.1, 1.9] に 1 が入るので成立する
        switch customRangeStyle {
        case .arbitrary(let widths):
            // 幅 99 は `resolveRange` の `Int.random(in: 1...(99 - width))`（空レンジ）でも落ちる
            precondition(
                widths.lowerBound >= 2 && widths.upperBound <= 98,
                "arbitrary(widths: \(widths)) は 2〜98 の範囲に収めること（幅 1 は目標レンジが空になり、幅 99 は下端 1 以上・上端 99 以下を保てない）"
            )
        case .roundFromZero(let options):
            // 非空は `LevelStage.init` が見る（`make(type:parameters:using:)` 直呼びの
            // 空 options はフォールバックが受けるので、ここでは各選択肢の幅だけ見る）
            precondition(
                options.allSatisfy { $0.upper >= 2 },
                "roundFromZero の上端は 2 以上にすること（0〜1 のレンジは目標レンジが空になる）"
            )
        case .threeDigit:
            // 幅と下端の整合は `resolveRange` の precondition が見る
            break
        }
        self.fractionDenominators = fractionDenominators
        self.customRangeStyle = customRangeStyle
        self.arithmeticOperations = arithmeticOperations
        self.percentStep = percentStep
    }
}

/// 0 始まりレンジの 1 択ぶん。
public struct RoundRangeOption: Sendable, Equatable {
    /// 数直線の右端
    public let upper: Int
    /// お題に出す値の刻み。`0〜100 で 63` より `0〜100 で 65` の方が位置を体で掴みやすいので、
    /// 広いレンジでは 5 刻みにする。狭いレンジ（0〜10 / 0〜20）で 5 刻みにすると
    /// 出せる値が 1〜2 種類しか残らないので 1 のままにする
    public let promptStep: Int

    public init(upper: Int, promptStep: Int = 1) {
        self.upper = upper
        self.promptStep = promptStep
    }
}

/// 変則レンジの両端の決め方。
public enum CustomRangeStyle: Sendable, Equatable {
    /// 0 〜 キリ番（算数帯 Lv5-6 の四則演算）。左端が必ず 0 なので「60 は 0〜100 の真ん中よりちょっと右」が体で分かる
    case roundFromZero(options: [RoundRangeOption])
    /// 2 桁の任意レンジ（変則レンジを出す Lv9-10）。下端 1 以上・上端 99 以下
    case arbitrary(widths: ClosedRange<Int>)
    /// 3 桁レンジ（上級帯 Lv11-12）。`137〜482` で `309` は暗算が要る
    case threeDigit(lowerBounds: ClosedRange<Int>, widths: ClosedRange<Int>)
}
