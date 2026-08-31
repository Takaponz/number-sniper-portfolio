import Foundation
import NumberSniperCore

/// Core の `GameEngine` と SwiftUI の橋渡し。
/// ゲームの判断は一切持たず、「いつ Core を呼ぶか」と「結果をどう見せるか」だけを持つ。
@Observable
final class GameViewModel {
    /// 進行状態は Core の `RoundPhase` をそのまま使う。
    /// 遷移の判断（いつ一時停止するか等）も Core の `RoundLifecycle` に置いてあり、
    /// Task 12 でそれを呼ぶだけにする
    typealias Phase = RoundPhase

    private(set) var engine: GameEngine<SystemRandomNumberGenerator>
    private(set) var phase: Phase = .playing
    private(set) var lastResult: RoundResult?
    private(set) var outcome: GameOverOutcome?

    /// **画面に出しているお題**。`engine.question` は submit した瞬間に次のお題へ
    /// 進んでしまうので、判定表示中に画面が次の問題に化けないよう別に持つ。
    /// 判定表示が終わったタイミングでだけ `engine.question` に追従させる
    private(set) var displayedQuestion: Question

    /// 判定が確定したときに呼ばれる。ハプティクス・効果音を刺すための穴
    var onRoundJudged: ((RoundResult) -> Void)?
    /// ゲームオーバー時に呼ばれる。Game Center 送信・広告表示を刺すための穴
    var onGameOver: ((GameOverOutcome) -> Void)?

    /// リワード広告を今すぐ出せるか。`RootView` が `AdServing` に繋ぐ。
    ///
    /// サービスを直接持たないのは既存の設計に合わせるため。この型は判断も外部接続も持たず、
    /// `onRoundJudged` / `onGameOver` と同じ「穴」を `RootView` が埋める形で外と繋がる
    var isRewardedAdReady: (() -> Bool)?
    /// リワード広告を出し、完走したら true。`RootView` が `AdServing` に繋ぐ
    var presentRewardedAd: (() async -> Bool)?

    /// リワード広告の表示待ちか。オファーのボタンを無効化して二重タップを塞ぐために公開する
    private(set) var isPresentingRewardedAd = false

    private(set) var clock: CursorClock
    /// 判定表示中はここに止めた位置が入る。nil なら三角波で動いている
    private(set) var frozenCursorRatio: Double?
    /// 判定表示中の残り時間バーの値。判定が出た瞬間の残量で固定する
    private(set) var frozenRemainingRatio: Double?

    /// ラウンドの通し番号。**お題が切り替わったことを画面に伝えるためだけ**に使う。
    ///
    /// 表示文字列を切り替えの目印にすると、`1/2` が 2 問続いたときや、同じ数字が
    /// 別のレンジで出たとき（`13〜63` の `50` と `20〜70` の `50` は目標比率が違う）に
    /// 「変わっていない」と誤判定して演出が出ない
    private(set) var roundIndex = 0

    private let scoreStore: ScoreStore
    private let now: () -> TimeInterval
    private var isTouchConsumed = false
    private var roundIntervalTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var timeLimitTask: Task<Void, Never>?
    /// 復活オファーの秒読み。他の 3 つと同じく、中断・作り直しのたびに畳む
    private var continueOfferTask: Task<Void, Never>?

    /// このプレイで一度でも復活したか。終了後インタースティシャルの免除に使う。
    /// `restart()` で false に戻す（`engine.reviveCount` は engine ごと作り直される）
    private var didRevive = false

    /// 最後の判定を見せている間に中断され、オファーを出すかどうかの判断を
    /// 復帰まで先送りしている状態。この間 phase は `.playing` のまま止まっている
    private var isOfferDecisionDeferred = false

    /// シーンが前景（`.active`）にいるか。`RootView` が `scenePhase` の変化のたびに更新する。
    ///
    /// **広告を待っている間に離席されたことを知るために持つ。** 広告表示中は
    /// `isSuspendedByExternalUI` でシーン遷移の一時停止を止めている（広告そのものが
    /// `.inactive` を起こすため）ので、この 1 ビットが無いと「広告が出て非アクティブになった」のか
    /// 「ユーザーがアプリを離れた」のかを区別できず、**誰も見ていない画面で復活後のラウンドが
    /// 始まって制限時間だけが進む**
    private(set) var isSceneActive = true

    /// `TimelineView` が最後に描いたフレームの時刻。
    ///
    /// タップ時刻を `Date()` で取ると、**画面に出ている位置**と**採点する位置**で
    /// 基準の時計が別になる。両者は表示パイプラインとタッチ配送の遅延ぶんズレるので、
    /// (a) 止めた瞬間にカーソルと残り時間バーが飛び、(b) S = 2.6 秒では 1〜2% の
    /// ズレになって PERFECT が GREAT に落ちる。描画に使った時刻をそのまま採点にも使えば
    /// 「見えていた位置で止まる」が保証される。
    ///
    /// 毎フレーム書き換わるので `@ObservationIgnored`。観測対象にすると描画のたびに
    /// View が無効化されて再評価が止まらなくなる。
    @ObservationIgnored private var lastDrawnTime: TimeInterval?

    #if DEBUG
    /// 直近フレームの間隔（秒）。リングバッファ。ProMotion が効いているかを実機で確認するために持つ。
    ///
    /// `lastDrawnTime` と同じ理由で `@ObservationIgnored`。毎フレーム書き換わるうえ、
    /// 読み手の `statusBar` は書き手（`NumberLineView` の `TimelineView`）の**兄弟**なので、
    /// 観測対象にすると「描画 → `PlayView` 全体が無効化 → 再描画」のループになる。
    /// 計器が毎フレームの再評価を誘発したら、測りたいフレーム間隔を計器自身が歪めてしまう
    @ObservationIgnored private var recentFrameIntervals: [TimeInterval] = []

    /// 計器の周期表示の位相アンカー。**`Date()` を View の body 内で作ってはいけない。**
    /// `PeriodicTimelineSchedule` は `from:` を位相の起点にするので、body 評価のたびに
    /// 新しい `Date()` を渡すとスケジュールが作り直されて経過が 0 に戻り、
    /// 「0.5 秒ごとに更新」が一度も成立しない（判定確定や次ラウンドで body は必ず再評価される）
    @ObservationIgnored let instrumentEpoch = Date()

    /// 実測リフレッシュレート（中央値 / 最遅 / 最速）。
    ///
    /// **中央値で見るのが要点。** 最短間隔を latch する形にすると、一度でも短い delta が
    /// 混じった時点で以降ずっと 120 と表示され、実際にレートが落ちていても検出できない
    /// （＝「120Hz が持続しているか」という問い自体に答えられない）。
    /// 最遅も併記するのは、中央値 120 でもコマ落ちしていることを読み取れるようにするため。
    ///
    /// **読まれた時に計算する（記録側では計算しない）。** 記録は毎フレーム走るが読み手は
    /// 0.5 秒に 1 回しか居ない。記録側で `sorted()` を回すと、「8.33ms の予算に間に合って
    /// いるか」を測りたい計器そのものが描画ホットパスに O(n log n) を積むことになる。
    /// Debug 構成は `-Onone` なので効きも大きい
    var measuredRefresh: (median: Double, slowest: Double, fastest: Double)? {
        // 一瞬の揺らぎで数字が暴れないよう、ある程度たまってから出す
        guard recentFrameIntervals.count >= 30 else { return nil }
        let sorted = recentFrameIntervals.sorted()
        // 偶数個のときは中央 2 点の平均を取る。上側中央値だけを見ると、120Hz と 60Hz が
        // 交互に来る（＝コマ落ちの典型形）ときに真の中央値 80Hz を 60Hz と誤読する
        let mid = sorted.count / 2
        let medianInterval = sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
        // 間隔が短いほど Hz は高い。sorted は昇順なので先頭が最速・末尾が最遅
        return (
            median: 1 / medianInterval,
            slowest: 1 / sorted[sorted.count - 1],
            fastest: 1 / sorted[0]
        )
    }
    #endif

    /// 広告・ATT・Game Center UI の表示中は true。この間はシーン遷移で一時停止しない
    var isSuspendedByExternalUI = false

    init(
        scoreStore: ScoreStore,
        now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
    ) {
        self.scoreStore = scoreStore
        self.now = now
        self.clock = CursorClock(originTime: now())
        // @Observable が保存プロパティをアクセサ経由に変えるため、init 内で
        // self.engine を読む前に全プロパティが初期化されている必要がある。
        // ローカルに作ってから両方へ入れる
        let engine = GameEngine<SystemRandomNumberGenerator>()
        self.engine = engine
        self.displayedQuestion = engine.question
    }

    /// 判定確定後だけ目標位置を見せる（プレイ中に見えたらゲームにならない）。
    /// 表示中のお題の目標を使う（`engine.question` は次の問題に進んでいる）
    var revealedTargetRatio: Double? {
        frozenCursorRatio == nil ? nil : displayedQuestion.target
    }

    /// カーソルを描くか。**時間切れのときだけ描かない**。
    ///
    /// 制限時間の本数は必ず半奇数なので、時間切れの瞬間のカーソルは必ず数直線の中央
    /// （比率 0.5）にいる（根拠は `SweepSchedule.roundTimeLimit`、値は `LevelCurveTests`
    /// で固定）。つまり**位置としての情報を一切持たない**。それを描くと、目標が中央付近の
    /// お題では目標マーカーとカーソルが重なった状態で TIME UP が出て、「ぴったり止めたのに
    /// MISS」に見えてしまう。カーソルを消せば「一度も止めなかった」ことが画面と一致する
    var showsCursor: Bool {
        !(frozenCursorRatio != nil && lastResult?.isTimeUp == true)
    }

    /// 描画時刻に対応するカーソル位置比率。
    ///
    /// ついでに描画時刻を記録する。タップの採点はこの時刻を基準にする（`lastDrawnTime` 参照）。
    func cursorRatio(at time: TimeInterval) -> Double {
        if let frozenCursorRatio { return frozenCursorRatio }
        #if DEBUG
        recordFrameInterval(at: time)
        #endif
        lastDrawnTime = time
        return clock.ratio(at: time, sweepDuration: engine.sweepDuration)
    }

    #if DEBUG
    /// 直近 120 フレームの間隔を貯めるだけ。Hz への変換は読み手側（`measuredRefresh`）で行う。
    /// `lastDrawnTime` を更新する**前**に呼ぶこと（前フレームとの差を取るため）。
    private func recordFrameInterval(at time: TimeInterval) {
        guard let previous = lastDrawnTime else { return }
        let interval = time - previous
        // 0 以下（同一フレームでの二重呼び出し）と 0.1 秒超（一時停止明け）は捨てる
        guard interval > 0, interval < 0.1 else { return }
        recentFrameIntervals.append(interval)
        if recentFrameIntervals.count > 120 { recentFrameIntervals.removeFirst() }
    }
    #endif

    /// 描画時刻に対応する残り時間の比率（1 = 満タン、0 = 時間切れ）。
    ///
    /// カーソルと同じく「原点時刻からの経過時間」だけで決まるので、`@Observable` を
    /// 毎フレーム更新せずに `TimelineView` 側から引ける。
    func remainingRatio(at time: TimeInterval) -> Double {
        if let frozenRemainingRatio { return frozenRemainingRatio }
        // 一時停止・復帰カウントダウン中は計時していない。満タンで見せる
        // （復帰後は beginNextRound で原点ごと引き直され、制限時間も最初から始まる）
        guard phase == .playing else { return 1 }
        let limit = engine.roundTimeLimit
        guard limit > 0 else { return 0 }
        let elapsed = time - clock.originTime
        return min(1, max(0, 1 - elapsed / limit))
    }

    /// タッチダウン。`DragGesture(minimumDistance: 0).onChanged` から呼ぶ。
    func touchDown() {
        guard phase == .playing, !isTouchConsumed, frozenCursorRatio == nil else { return }
        // ライフ 0 の状態で submit すると Core の precondition に当たる
        guard !engine.isGameOver else { return }
        isTouchConsumed = true
        // タップで確定したので制限時間の計時を止める
        timeLimitTask?.cancel()
        timeLimitTask = nil

        // 基準は「画面に最後に描かれたフレームの時刻」。Date() ではない（`lastDrawnTime` 参照）。
        // まだ 1 フレームも描かれていないラウンド頭だけ now() にフォールバックする
        let tapTime = (lastDrawnTime ?? now()) - GameConfig.inputLatencyCompensationSeconds

        // 締め切りを過ぎていたら、タイマーの発火を待たずここで時間切れにする。
        //
        // `Task.sleep` は単調時計かつ **Task 本体が動き始めてから**計り始めるのに対し、
        // 残り時間バーは `now()`（壁時計）と原点時刻から引いている。この 2 つを別々に
        // 信じると、バーが 0 になってもタイマーがまだ発火していない窓ができる。
        // その窓のタップを通常判定すると、締め切りの瞬間カーソルは比率 0.5 にいるので、
        // 目標が中央付近のお題で TIME UP のはずが PERFECT になる。
        // 締め切りの判定は**バーと同じ時計**に一本化する
        guard remainingRatio(at: tapTime) > 0 else {
            handleTimeUp()
            return
        }

        let stopRatio = clock.ratio(at: tapTime, sweepDuration: engine.sweepDuration)
        frozenRemainingRatio = remainingRatio(at: tapTime)
        frozenCursorRatio = stopRatio

        let result = engine.submit(stopRatio: stopRatio)
        lastResult = result
        onRoundJudged?(result)

        if result.isGameOver {
            scheduleContinueOfferOrGameOver()
        } else {
            scheduleNextRound()
        }
    }

    /// タッチアップ。次のタッチダウンを受け付けられるようにする。
    func touchUp() {
        isTouchConsumed = false
    }

    /// 次の問題を画面に出して、カーソルを左端から動かし始める。
    ///
    /// - Important: 判定表示の終了経路は「通常の休止明け」と「一時停止からの復帰」の
    ///   2 つあり、**どちらも必ずここを通す**。`displayedQuestion` の同期を片方だけに
    ///   書くと、判定表示中にバックグラウンドへ行った場合に画面が前の問題のまま残り、
    ///   次のタップが別の問題の target で採点される
    ///
    /// - Note: `isTouchConsumed` はここでは触らない。通常のラウンド進行では指がまだ
    ///   画面に乗っている可能性があり、ここでリセットすると「タップはタッチダウンの
    ///   最初の 1 回だけ採用する」仕様が壊れて、置きっぱなしの指で次の問題が
    ///   即座に自動 submit される。解除は `touchUp()` の役目。
    ///   例外は一時停止からの復帰で、そちらは中断でタッチが失われ `touchUp()` が
    ///   来ないため `startCountdown()` 側で明示的にリセットする
    private func beginNextRound() {
        // ここは「判定確定後の次ラウンド」と「一時停止からの復帰」の両方が通る。
        // 復帰でまだ判定していない場合は engine.question が進んでいないので、お題は同じまま
        // 再開する。そのときに roundIndex を進めると、変わっていないお題に切り替え演出が
        // 出てしまい「変わったことに気づかせる」という演出の意味が薄れる
        let isNewQuestion = engine.question != displayedQuestion
        displayedQuestion = engine.question
        if isNewQuestion { roundIndex += 1 }
        frozenCursorRatio = nil
        frozenRemainingRatio = nil
        clock.resetOrigin(to: now())
        // 原点を動かしたので、前ラウンドの描画時刻は捨てる。
        // 残したまま次のフレームより先にタップされると、新しい原点より過去の時刻で
        // 位置を計算してしまい、カーソルが右端付近にいる扱いになる
        lastDrawnTime = nil
        startRoundTimer()
    }

    /// 制限時間の計時を張り直す。カーソルの原点と同時に引き直すこと
    /// （原点だけずらすと、バーの残量と実際の締め切りがずれる）。
    private func startRoundTimer() {
        timeLimitTask?.cancel()
        let limit = engine.roundTimeLimit
        timeLimitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard !Task.isCancelled, let self else { return }
            self.handleTimeUp()
        }
    }

    /// 制限時間切れ。タップ無しで MISS を確定させる。
    ///
    /// 以降の流れ（判定表示 → 次の問題 / ゲームオーバー）はタップ時と完全に同じ経路を通す。
    private func handleTimeUp() {
        guard phase == .playing, frozenCursorRatio == nil, !engine.isGameOver else { return }

        // 止めた位置は「時間切れの瞬間のカーソル位置」を見せる。
        // ただし判定そのものはこの位置から計算しない（Core の timeUp が .miss に固定する）
        frozenCursorRatio = clock.ratio(
            at: lastDrawnTime ?? now(),
            sweepDuration: engine.sweepDuration
        )
        frozenRemainingRatio = 0

        let result = engine.timeUp()
        lastResult = result
        onRoundJudged?(result)

        if result.isGameOver {
            scheduleContinueOfferOrGameOver()
        } else {
            scheduleNextRound()
        }
    }

    /// 判定表示のあと、カーソルを左端に戻して次の問題を始める。
    private func scheduleNextRound() {
        roundIntervalTask?.cancel()
        roundIntervalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(GameConfig.interRoundPauseSeconds))
            guard !Task.isCancelled, let self, self.phase == .playing else { return }
            self.beginNextRound()
        }
    }

    /// 最後の判定（多くは MISS）を見せてから、復活オファーかゲームオーバーへ進む。
    /// 即座に遷移すると、止めた位置・目標位置・判定バッジが一瞬も見えない
    private func scheduleContinueOfferOrGameOver() {
        timeLimitTask?.cancel()
        timeLimitTask = nil
        roundIntervalTask?.cancel()
        roundIntervalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(GameConfig.interRoundPauseSeconds))
            guard !Task.isCancelled, let self, self.phase == .playing else { return }
            // 復活できる状態（ライフ 0 / 上限未達 / 1 問以上正解）でも、広告が
            // 読めていなければオファーを出さない。押してから「広告がありません」が最悪
            if self.engine.canRevive, self.isRewardedAdReady?() == true {
                self.startContinueCountdown(from: GameConfig.continueOfferSeconds)
            } else {
                self.finalizeGameOver()
            }
        }
    }

    /// 復活オファーの秒読み。0 まで落ちたら辞退と同じ扱いでゲームオーバーを確定させる。
    ///
    /// - Parameter remaining: 開始する残り秒数。**バックグラウンド復帰では途中の値から
    ///   張り直す**ため引数で受ける（最初から数え直すと、電話 1 本でオファーが延命される）
    private func startContinueCountdown(from remaining: Int) {
        continueOfferTask?.cancel()
        phase = .continueOffer(remaining: remaining)
        continueOfferTask = Task { [weak self] in
            guard let self else { return }
            for value in stride(from: remaining, through: 1, by: -1) {
                guard !Task.isCancelled, self.isOfferingContinue else { return }
                self.phase = .continueOffer(remaining: value)
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled, self.isOfferingContinue else { return }
            self.finalizeGameOver()
        }
    }

    /// ゲームオーバーの確定。ハイスコア更新・広告カウンタ・リーダーボード予約を一度に行う。
    ///
    /// - Important: **ここに `phase == .playing` のガードを持ち込まないこと。**
    ///   オファー経由で呼ぶときの phase は `.continueOffer` なので、ガードを入れると
    ///   ゲームオーバーが永久に確定しない。判定表示の遅延ガードは呼び出し側の Task に置く
    private func finalizeGameOver() {
        let outcome = scoreStore.recordGameOver(score: engine.score, didRevive: didRevive)
        self.outcome = outcome
        phase = .gameOver
        onGameOver?(outcome)
    }

    /// 「広告を見て復活」。完走したら続きから、しなければゲームオーバーを確定させる。
    func acceptContinue() async {
        // 広告を待っている間もオーバーレイは生きている。二重タップで `revive()` が
        // 2 回走ると、2 回目は `canRevive == false` で precondition に当たって落ちる
        guard isOfferingContinue, !isPresentingRewardedAd else { return }
        isPresentingRewardedAd = true
        continueOfferTask?.cancel()
        continueOfferTask = nil
        isSuspendedByExternalUI = true

        let didWatch = await presentRewardedAd?() ?? false

        // 広告表示でタッチが失われ `touchUp()` が来ないので、ここで明示的に解除する。
        // 飛ばすと復活後の初回タップが効かない（`startCountdown()` が同じ理由で解除している）
        isTouchConsumed = false
        // どちらの経路でも必ず戻す。立ちっぱなしになるとバックグラウンド復帰の
        // カウントダウンが二度と出なくなる
        isSuspendedByExternalUI = false
        isPresentingRewardedAd = false

        guard didWatch, engine.canRevive else {
            finalizeGameOver()
            return
        }
        engine.revive()
        didRevive = true

        // 広告を見ている間に離席されていたら、ここで再開しない。
        // ライフを戻したうえで復帰待ちに置き、通常の 3 秒カウントダウンで再開させる
        // （そのまま `.playing` にすると、制限時間だけが背面で進んで理不尽な TIME UP になる）
        guard isSceneActive else {
            phase = .countdown(remaining: GameConfig.resumeCountdownSeconds)
            return
        }

        // 再開は通常のラウンド進行と同じ経路を通す（原点・制限時間・お題の同期が 1 本に保たれる）
        beginNextRound()
        phase = .playing
    }

    /// `scenePhase` の変化を伝える。**route に関係なく毎回呼ぶこと**
    /// （リザルトで広告を待っている間の離席も拾う必要がある）。
    func setSceneActive(_ isActive: Bool) {
        isSceneActive = isActive
    }

    /// 「あきらめる」。秒読みを待たずにゲームオーバーを確定させる。
    func declineContinue() {
        guard isOfferingContinue, !isPresentingRewardedAd else { return }
        continueOfferTask?.cancel()
        continueOfferTask = nil
        finalizeGameOver()
    }

    private var isOfferingContinue: Bool {
        if case .continueOffer = phase { return true }
        return false
    }

    /// タイトルからの開始／リザルトからのリトライ／練習モードの「はじめから挑戦」。
    /// engine を作り直す。**常に Lv1 から始まる。**
    func restart() {
        roundIntervalTask?.cancel()
        countdownTask?.cancel()
        timeLimitTask?.cancel()
        continueOfferTask?.cancel()
        countdownTask = nil
        roundIntervalTask = nil
        timeLimitTask = nil
        continueOfferTask = nil
        didRevive = false
        isPresentingRewardedAd = false
        isOfferDecisionDeferred = false
        engine = GameEngine<SystemRandomNumberGenerator>()
        displayedQuestion = engine.question
        roundIndex += 1
        clock = CursorClock(originTime: now())
        frozenCursorRatio = nil
        frozenRemainingRatio = nil
        lastDrawnTime = nil
        isTouchConsumed = false
        lastResult = nil
        outcome = nil
        phase = .playing
        // 1 問目の計時開始。phase を .playing にしたあとに張ること
        startRoundTimer()
    }

    // MARK: - シーン遷移

    /// `.inactive` / `.background` になったときに呼ぶ。
    /// プレイ画面でラウンド進行中のときだけ効く。
    func pauseForSceneChange() {
        // 最後の判定を見せている 0.45 秒の間の中断。phase はまだ `.playing` なので
        // 下の 2 つの経路はどちらも畳まない（`onSceneInactive` は `isGameOverPending` で
        // 早期 return、オファー分岐はまだ `.continueOffer` でない）。放置すると
        // **誰も見ていない画面でオファーの秒読み 8 秒が丸ごと消化される**ので、
        // 判断ごと復帰まで先送りする
        if RoundLifecycle.onSceneInactiveBeforeOffer(
            from: phase,
            isSuspendedByExternalUI: isSuspendedByExternalUI,
            isGameOverPending: engine.isGameOver
        ) {
            roundIntervalTask?.cancel()
            roundIntervalTask = nil
            isOfferDecisionDeferred = true
            return
        }

        // 復活オファー中は phase を保ったまま秒読みだけ止める（復帰時に残り秒数から張り直す）。
        // オファー中は必ずライフ 0 ＝ `isGameOverPending` なので、下の `onSceneInactive` では
        // 早期 return されて扱えない。`Task.sleep` は端末が休んでいる間も進むため、
        // ここで畳まないと**電話 1 本でオファーを取り逃がす**
        if RoundLifecycle.onSceneInactiveDuringOffer(from: phase) {
            continueOfferTask?.cancel()
            continueOfferTask = nil
            return
        }

        // 一時停止してよいかの判断は Core の RoundLifecycle が持つ（テスト済み）。
        // ここは「判断に従ってタスクを畳む」だけ
        guard let next = RoundLifecycle.onSceneInactive(
            from: phase,
            isSuspendedByExternalUI: isSuspendedByExternalUI,
            isGameOverPending: engine.isGameOver
        ) else { return }

        roundIntervalTask?.cancel()
        roundIntervalTask = nil
        countdownTask?.cancel()
        countdownTask = nil
        // 制限時間も止める。Task.sleep は端末が休んでいる間も進むので、
        // ここで畳まないとバックグラウンド中に時間切れが確定してしまう
        timeLimitTask?.cancel()
        timeLimitTask = nil
        phase = next
    }

    /// `.active` に戻ったときに呼ぶ。3 秒カウントダウンを挟んでから再開する。
    func resumeFromSceneChange() {
        // 先送りしていた「オファーを出すか / ゲームオーバーを確定させるか」の判断を
        // やり直す。判定表示の遅延から張り直すので、戻ってきた直後にいきなり
        // オーバーレイが出ることはない
        if RoundLifecycle.shouldResumeBeforeOffer(
            isOfferDecisionDeferred: isOfferDecisionDeferred,
            isSuspendedByExternalUI: isSuspendedByExternalUI
        ) {
            isOfferDecisionDeferred = false
            scheduleContinueOfferOrGameOver()
            return
        }

        // オファーの秒読みは**残り秒数から**再開する。復帰カウントダウン 3 秒は挟まない
        // （まだ復活しておらずゲームが動いていないので、身構える時間が要らない）
        if case .continueOffer(let remaining) = phase,
           RoundLifecycle.shouldResumeOffer(
               from: phase,
               isSuspendedByExternalUI: isSuspendedByExternalUI
           ) {
            startContinueCountdown(from: remaining)
            return
        }

        guard RoundLifecycle.shouldStartCountdown(
            from: phase,
            isSuspendedByExternalUI: isSuspendedByExternalUI
        ) else { return }
        startCountdown()
    }

    private var isCountingDown: Bool {
        if case .countdown = phase { return true }
        return false
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            guard let self else { return }
            for remaining in stride(from: GameConfig.resumeCountdownSeconds, through: 1, by: -1) {
                guard !Task.isCancelled, self.isCountingDown else { return }
                self.phase = .countdown(remaining: remaining)
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled, self.isCountingDown else { return }

            // 中断でタッチが失われ touchUp() が来ないので、ここで明示的に解除する
            // （復帰経路だけの処理。通常のラウンド進行では触らない）
            self.isTouchConsumed = false
            // 三角波の原点を再設定してから再開する（復帰直後の理不尽 MISS を構造的に排除）。
            // 判定表示中に中断された場合は displayedQuestion がまだ前の問題なので、
            // beginNextRound でまとめて engine.question に追従させる
            self.beginNextRound()
            self.phase = .playing
        }
    }
}
