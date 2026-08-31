import Foundation

/// ズレの方向。
public enum OffsetDirection: Sendable, Equatable {
    /// 止めた位置が目標より左
    case left
    /// 止めた位置が目標より右
    case right
    /// ぴったり（d == 0）
    case exact
}

/// 練習モードの 1 問の結果。
///
/// **方向情報は `direction` だけが持つ。** `offset` に符号を持たせると、
/// 副表示が「レンジの -6%」になる表示事故を招く。
public struct PracticeResult: Sendable, Equatable {
    /// 本編と同じ `judge(deviation:)` の結果
    public let judgement: Judgement
    public let signedDeviation: Int
    /// ズレの実数値（**絶対値**）
    public let offset: LineValue
    /// ズレをレンジ幅の % で見た概算（整数除算の切り捨て）。副表示用
    public let offsetPercent: Int
    public let direction: OffsetDirection

    public init(
        judgement: Judgement,
        signedDeviation: Int,
        offset: LineValue,
        offsetPercent: Int,
        direction: OffsetDirection
    ) {
        self.judgement = judgement
        self.signedDeviation = signedDeviation
        self.offset = offset
        self.offsetPercent = offsetPercent
        self.direction = direction
    }
}

/// 練習モードの状態機械。UI に一切依存しない。
///
/// **`lives` / `score` / `isGameOver` が型に存在しない**（到達不能ではなく不存在）。
/// スコアの永続化・ゲームオーバー集計・リーダーボードのどの型へも参照を持たないので、
/// 練習が本編スコアを汚す経路が型のレベルで無い。
///
/// - Note: 補助の grep ゲート（spec の「スコア非汚染は型で保証」節）は、このファイルに
///   該当する識別子が 1 つも現れないことを機械的に見る。**説明のためであっても
///   ここに型名を書かないこと**（コメントで落ちる）。
public struct PracticeSession<RNG: RandomNumberGenerator & Sendable>: Sendable {
    /// 練習するレベル。**進まない**（`let`）
    public let level: Int
    public let curve: LevelCurve
    public private(set) var question: Question
    /// 解いた問数（ヘッダの「N 問」）
    public private(set) var solvedCount: Int = 0
    /// お題切り替え演出の目印
    public private(set) var roundIndex: Int = 0
    public private(set) var lastResult: PracticeResult?

    private var rng: RNG
    private let generator: QuestionGenerator

    /// 片道スイープ時間。**本編と同じ関数**を通す。
    /// ここが違うと練習で身に付いた感覚が本編に転移しない。
    public var sweepDuration: TimeInterval {
        SweepSchedule.duration(level: level, curve: curve)
    }

    public init(
        level: Int,
        curve: LevelCurve = .standard,
        rng: RNG,
        generator: QuestionGenerator = QuestionGenerator()
    ) {
        // `LevelCurve.stage(for:)` / `SweepSchedule.duration` と同じクランプ
        let clampedLevel = min(max(1, level), GameConfig.maxLevel)
        self.level = clampedLevel
        self.curve = curve
        var rng = rng
        self.question = generator.make(level: clampedLevel, curve: curve, using: &rng)
        self.rng = rng
        self.generator = generator
    }

    /// カーソルを止めた位置比率を渡して 1 問を判定する。**お題は進まない**（`advance()` が進める）。
    ///
    /// - Important: 判定表示中（`lastResult != nil`）の再呼び出しは**状態を変えず**
    ///   直近の結果を返す。`precondition` にしないのは、`stopRatio` がタップ由来の
    ///   外部入力で、連打やタッチ配送の順序ゆらぎで普通に到達しうるため
    @discardableResult
    public mutating func submit(stopRatio: Double) -> PracticeResult {
        if let lastResult { return lastResult }

        let d = deviation(stopRatio: stopRatio, target: question.target)
        let signed = signedDeviation(stopRatio: stopRatio, target: question.target)
        let direction: OffsetDirection =
            if signed < 0 { .left } else if signed > 0 { .right } else { .exact }
        let result = PracticeResult(
            judgement: judge(deviation: d),
            signedDeviation: signed,
            offset: question.range.offsetValue(signedDeviation: signed),
            offsetPercent: d / 100,
            direction: direction
        )
        lastResult = result
        solvedCount += 1
        return result
    }

    /// 次のお題へ進む。未判定（`lastResult == nil`）のときは **no-op**。
    public mutating func advance() {
        guard lastResult != nil else { return }
        lastResult = nil
        question = generator.make(level: level, curve: curve, using: &rng)
        roundIndex += 1
    }
}

extension PracticeSession where RNG == SystemRandomNumberGenerator {
    /// 本番用。システムの乱数で初期化する。
    public init(level: Int, curve: LevelCurve = .standard) {
        self.init(level: level, curve: curve, rng: SystemRandomNumberGenerator())
    }
}
