import Foundation

/// 1 問の結果。UI 側の演出（ハプティクス・効果音・エフェクト）はこれを見て決める。
public struct RoundResult: Sendable, Equatable {
    public let judgement: Judgement
    public let deviation: Int
    public let gainedPoints: Int
    public let didLevelUp: Bool
    public let isGameOver: Bool
    /// タップされないまま制限時間が切れた結果か。
    /// スコア・ライフ・コンボの扱いは MISS と完全に同じで、**表示だけを分ける**ための印。
    public let isTimeUp: Bool

    public init(
        judgement: Judgement,
        deviation: Int,
        gainedPoints: Int,
        didLevelUp: Bool,
        isGameOver: Bool,
        isTimeUp: Bool = false
    ) {
        self.judgement = judgement
        self.deviation = deviation
        self.gainedPoints = gainedPoints
        self.didLevelUp = didLevelUp
        self.isGameOver = isGameOver
        self.isTimeUp = isTimeUp
    }
}

/// ゲームの状態機械。UI に一切依存しない。
///
/// 処理順は仕様どおり **判定確定 → 獲得点計算 → コンボ更新 → 正解数／ライフ更新 →
/// レベル更新 → 次のお題** の順に固定している。獲得点はコンボ更新前・レベルアップ前の
/// 値で計算する（順序を入れ替えると全スコアがずれる）。
public struct GameEngine<RNG: RandomNumberGenerator & Sendable>: Sendable {
    /// このゲームのレベルカーブ。速度・制限時間・お題構成はここから引く。
    /// 出荷値は `.standard` の 1 本だけで、差し替えられるのはテストのため
    public let curve: LevelCurve

    public private(set) var score: Int = 0
    public private(set) var lives: Int = GameConfig.initialLives
    public private(set) var combo: Int = 0
    public private(set) var correctCount: Int = 0
    public private(set) var level: Int = 1
    public private(set) var question: Question
    public private(set) var isGameOver: Bool = false
    /// このプレイで復活した回数。`GameConfig.maxRevivesPerGame` が上限
    public private(set) var reviveCount: Int = 0

    private var rng: RNG
    private let generator: QuestionGenerator

    public init(
        curve: LevelCurve = .standard,
        rng: RNG,
        generator: QuestionGenerator = QuestionGenerator()
    ) {
        self.curve = curve
        var rng = rng
        self.question = generator.make(level: 1, curve: curve, using: &rng)
        self.rng = rng
        self.generator = generator
    }

    /// 現在レベルの片道スイープ時間。
    public var sweepDuration: TimeInterval {
        SweepSchedule.duration(level: level, curve: curve)
    }

    /// 現在レベルでの 1 問の制限時間。この時間タップが無ければ `timeUp()` を呼ぶ。
    public var roundTimeLimit: TimeInterval {
        SweepSchedule.roundTimeLimit(level: level, curve: curve)
    }

    /// カーソルを止めた位置比率を渡して 1 問を確定させる。
    @discardableResult
    public mutating func submit(stopRatio: Double) -> RoundResult {
        precondition(!isGameOver, "ゲームオーバー後に submit は呼べない")

        let d = deviation(stopRatio: stopRatio, target: question.target)
        return finish(judgement: judge(deviation: d), deviation: d, isTimeUp: false)
    }

    /// タップされないまま制限時間が切れたときに呼ぶ。1 問を MISS として確定させる。
    ///
    /// - Important: 判定は `judge(deviation:)` を通さず **常に `.miss` に固定する**。
    ///   制限時間の本数は必ず半奇数なので、時間切れの瞬間のカーソルは
    ///   **必ず数直線の中央（比率 0.5）** にいる（レベルにも目標にも依存しない。
    ///   根拠と本数は `SweepSchedule.roundTimeLimit` を見ること）。ズレから判定すると
    ///   目標が 0.43〜0.57 のお題で GOOD 以上に化ける。「放置していたら正解になった」は
    ///   仕様として誤り。
    /// - Note: `deviation` には最大のズレ（レンジ幅 100% = 10000）を入れる。
    /// - Note: この「必ず中央」という性質は画面側にも効いている。時間切れのカーソル位置は
    ///   位置としての情報を持たないので、`GameViewModel.showsCursor` が描画を止める。
    @discardableResult
    public mutating func timeUp() -> RoundResult {
        precondition(!isGameOver, "ゲームオーバー後に timeUp は呼べない")

        return finish(judgement: .miss, deviation: 10_000, isTimeUp: true)
    }

    // MARK: - 復活（リワード広告コンティニュー）

    /// 復活を提案してよいか。**ライフ 0 ／ 上限未達 ／ 1 問以上正解**の 3 つが揃ったときだけ true。
    ///
    /// `correctCount > 0` を条件に入れているのは、開幕 3 連続 MISS のスコア 0 では
    /// 失うものが無く復活の動機がそもそも無いため。出しても使われずに広告在庫を無駄打ちし、
    /// プレイヤーには「開始 10 秒でもう広告」に見える。
    public var canRevive: Bool {
        isGameOver && reviveCount < GameConfig.maxRevivesPerGame && correctCount > 0
    }

    /// 復活する。ライフを戻してゲームオーバーを取り消し、**次のお題から**再開する。
    ///
    /// - Important: **お題はここで作り直す。** `finish` はライフ 0 のとき `question` を
    ///   更新しないので、死んだ時のお題が残っている。時間切れで死んだ場合は画面に緑の
    ///   目標マーカーが出たままなので（`GameViewModel.showsCursor` / `revealedTargetRatio`）、
    ///   同じお題を再出題すると正解位置を見た状態で撃てて確実に PERFECT になる。
    /// - Important: **1 回引くだけでは足りない。** 生成は乱数なので、引き直した結果が
    ///   たまたま死んだ時と同じお題になることがある（お題空間の狭い低レベルでは数 % 起きる）。
    ///   確率が低くても、起きたときは上と同じ「正解位置を見た状態で撃てる」状態になるので、
    ///   一致している間は引き直す。ただし**上限付き**で回す（`reviveQuestionDrawLimit`）。
    /// - Note: `score` / `level` / `correctCount` / `combo` は継続する（触らない）。
    ///   コンボは死因の MISS で既に 0 になっている（`nextCombo`）。
    public mutating func revive() {
        precondition(canRevive, "復活できない状態で revive は呼べない")

        reviveCount += 1
        lives = GameConfig.livesOnRevive
        isGameOver = false

        let questionAtDeath = question
        for _ in 0..<GameConfig.reviveQuestionDrawLimit {
            question = generator.make(level: level, curve: curve, using: &rng)
            if question != questionAtDeath { break }
        }
    }

    /// 判定が決まったあとの状態更新。`submit` と `timeUp` の唯一の合流点。
    private mutating func finish(
        judgement: Judgement,
        deviation d: Int,
        isTimeUp: Bool
    ) -> RoundResult {
        // 獲得点は「その問の開始時点」のレベルとコンボで計算する
        let gained = roundPoints(judgement: judgement, level: level, combo: combo)
        score += gained

        combo = nextCombo(current: combo, judgement: judgement)

        if judgement.isCorrect {
            correctCount += 1
        } else {
            lives -= 1
        }

        let newLevel = LevelProgression.level(correctCount: correctCount)
        let didLevelUp = newLevel > level
        level = newLevel

        if lives <= 0 {
            isGameOver = true
        } else {
            question = generator.make(level: level, curve: curve, using: &rng)
        }

        return RoundResult(
            judgement: judgement,
            deviation: d,
            gainedPoints: gained,
            didLevelUp: didLevelUp,
            isGameOver: isGameOver,
            isTimeUp: isTimeUp
        )
    }
}

extension GameEngine where RNG == SystemRandomNumberGenerator {
    /// 本番用。システムの乱数で初期化する。
    public init(curve: LevelCurve = .standard) {
        self.init(curve: curve, rng: SystemRandomNumberGenerator())
    }
}
