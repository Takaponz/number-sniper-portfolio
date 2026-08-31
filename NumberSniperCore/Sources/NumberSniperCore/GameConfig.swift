import Foundation

/// ゲームの全チューニング定数。実機チューニングの対象はすべてここに置く。
/// コード中に数値を直書きしないこと。
public enum GameConfig {
    // MARK: - 判定しきい値（ズレ d: レンジ幅の 0.01% 単位の整数）
    /// PERFECT: d <= 100（= 1%）
    public static let perfectThreshold = 100
    /// GREAT: 100 < d <= 300（= 3%）
    public static let greatThreshold = 300
    /// GOOD: 300 < d <= 700（= 7%）。これを超えると MISS
    public static let goodThreshold = 700

    // MARK: - 精度点（すべて 100 の倍数。獲得点の整数除算が必ず割り切れる前提）
    public static let perfectPoints = 1000
    public static let greatPoints = 500
    public static let goodPoints = 100

    // MARK: - コンボ
    public static let perfectComboGain = 2
    public static let greatComboGain = 1
    public static let comboMultiplierBasePercent = 100
    public static let comboMultiplierStepPercent = 10
    public static let comboMultiplierCapPercent = 300

    // MARK: - レベル
    public static let correctAnswersPerLevel = 3
    /// 最高レベル。到達は `correctAnswersPerLevel × (maxLevel − 1)` 問正解後
    /// （`LevelProgression`）。以降はレベルが上がらない「スコアレース」フェーズになる
    /// （Lv12 のエンドレス帯 = `LevelCurve+Standard.swift` の最終ステージ）。
    public static let maxLevel = 12

    // MARK: - カーソル速度・制限時間
    /// Lv1 の片道スイープ時間。
    ///
    /// これは「目測と実際のズレを楽しむ」ゲームであって、速いカーソルを止める
    /// 反射神経を競うゲームではない。だから**速さそのものは難しさの主軸にしない**。
    /// 初速をカーブの外（ここ）に置いてあるのは、`LevelCurve` 側から書き換えられないようにするため。
    /// 難しさは「レベルが上がるときの加速」（`sweepDecayRate` / `minSweepSeconds`）と
    /// お題の種類（`LevelStage.types` / `parameters`）で出す。
    public static let baseSweepSeconds: TimeInterval = 2.6

    /// 加速の強さ（`sweepDecayRate` / `minSweepSeconds`）と制限時間の本数
    /// （`roundTimeLimitSweeps`）・お題の生成パラメータは `LevelCurve` に置いてある。
    /// 値は `LevelCurve+Standard.swift`。

    // MARK: - Game Center
    /// リーダーボードは 1 本だけ。**リリース後は変えられない**ので、App Store Connect に
    /// 登録する ID と一字一句合わせること
    public static let leaderboardID = "com.example.numbersniper.highscore"

    // MARK: - お題
    /// 目標比率 t の下限・上限（端は判定が片側に潰れるため除外する）。全レベル共通
    public static let minTarget = 0.05
    public static let maxTarget = 0.95
    /// 変則レンジの幅と分数の分母は**レベル帯ごとに違う**ので
    /// `QuestionParameters` に置いてある（`LevelCurve+Standard.swift`）。

    // MARK: - ライフ
    public static let initialLives = 3

    // MARK: - 復活（リワード広告コンティニュー）
    /// 1 プレイで復活できる回数の上限。
    ///
    /// 復活は実質「ハイスコアを広告視聴で買える」ことを意味するので、**上限がスコア膨張の
    /// 有界性を担保している**。無制限にすると時間をかけた人が勝つランキングになり、
    /// リーダーボードを 1 本のまま運用できなくなる
    public static let maxRevivesPerGame = 1
    /// 復活したときのライフ。
    public static let livesOnRevive = 1
    /// 復活時にお題を引き直す最大回数。
    ///
    /// 死んだ時と同じお題を引いたら引き直すが、**必ず上限を付ける**。お題空間が狭いレベルでは
    /// 同じ値しか作れない場合があり、無条件のループだと戻ってこない
    public static let reviveQuestionDrawLimit = 8
    /// 復活オファーの秒読み（秒）。
    ///
    /// 5 秒だと「広告を見て復活」の意味を読む前に消え、10 秒だと死んだ直後の待ち時間として長い。
    /// 実機で調整する前提の値
    public static let continueOfferSeconds = 8

    // MARK: - ラウンド進行
    /// 判定確定後、次の問題が始まるまでカーソルを止めておく時間（秒）
    public static let interRoundPauseSeconds: TimeInterval = 0.45

    // MARK: - 入力
    /// 入力遅延の一律補正（秒）。実機チューニング用。正の値でタップ時刻を過去にずらす
    public static let inputLatencyCompensationSeconds: TimeInterval = 0.0

    // MARK: - 復帰
    /// バックグラウンド復帰時のカウントダウン秒数
    public static let resumeCountdownSeconds = 3

    // MARK: - 広告
    /// 何回のゲームオーバーごとにインタースティシャルを出すか。
    ///
    /// **「毎回」を判定ロジックではなく定数で表しているのが要点。** 広告過多でリテンションが
    /// 落ちたら `2` に戻すだけで済む。0 は `%` がゼロ除算でクラッシュするので不可
    /// （`GameConfigTests` の invariant で固定）
    public static let gameOversPerInterstitial = 1

    // MARK: - 練習モード
    /// 目盛の分割数。3 本の目盛（25/50/75%）を出すので 4。
    ///
    /// **`10^practiceMaxDecimals % practiceTickDivisions == 0` が invariant。**
    /// これが崩れると目盛値が有限小数で表せず、丸めた表示（線の位置と食い違う嘘の値）に
    /// なる。D = 3 にすると 1/3 が有限小数にならないのでこの性質が壊れる。
    public static let practiceTickDivisions = 4
    /// 練習モードの表示で許す最大の小数桁数
    public static let practiceMaxDecimals = 2
    /// 判定表示から次の問題へ進めるまでの最短時間（秒）。タップ連打で
    /// ズレ表示を読む前に次が始まるのを防ぐ
    public static let practiceMinResultDisplaySeconds: TimeInterval = 0.35
}
