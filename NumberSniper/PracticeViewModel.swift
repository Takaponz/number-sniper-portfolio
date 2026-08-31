import Foundation
import NumberSniperCore

/// Core の `PracticeSession` と SwiftUI の橋渡し。
///
/// **判断を持たない。** 入力・復帰の分岐はすべて Core の `PracticeInput` に委ね、
/// ここは返ってきた action に従って副作用を実行するだけにする
/// （アプリターゲットにテストターゲットが無いため、判断をここに書くと自動テストで固定できない）。
///
/// スコアの永続化・ゲームオーバー集計・リーダーボードのどの型へも参照を持たない。
/// 練習が本編スコアを汚す経路が型のレベルで存在しない。
///
/// - Note: 補助の grep ゲート（spec の「スコア非汚染は型で保証」節）は、このファイルに
///   該当する識別子が 1 つも現れないことを機械的に見る。**説明のためであっても
///   ここに型名を書かないこと**（コメントで落ちる）。
@Observable
final class PracticeViewModel {
    private(set) var session: PracticeSession<SystemRandomNumberGenerator>

    /// 判定が確定したときに呼ばれる。ハプティクス・効果音を刺すための穴。
    /// **本編と同じサービスを鳴らす**（判定フィードバックの一貫性が学習ループの一部で、
    /// ここだけ無音だと「本編とは別物」の感覚になる）
    var onJudged: ((Judgement) -> Void)?

    private(set) var clock: CursorClock
    /// 判定表示中はここに止めた位置が入る。nil なら三角波で動いている
    private(set) var frozenCursorRatio: Double?

    private let now: () -> TimeInterval
    private var isTouchConsumed = false
    /// 判定表示が出た時刻。連打ガードの基準
    private var resultShownTime: TimeInterval?

    /// `TimelineView` が最後に描いたフレームの時刻。
    /// 「見えていた位置で採点する」ための基準（本編 `GameViewModel.lastDrawnTime` と同じ）。
    /// 毎フレーム書き換わるので `@ObservationIgnored`。
    @ObservationIgnored private var lastDrawnTime: TimeInterval?

    init(
        level: Int,
        now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
    ) {
        self.now = now
        self.clock = CursorClock(originTime: now())
        self.session = PracticeSession<SystemRandomNumberGenerator>(level: level)
    }

    /// 練習中のレベル。ヘッダ表示用
    var level: Int { session.level }
    /// 解いた問数
    var solvedCount: Int { session.solvedCount }
    var question: Question { session.question }
    var lastResult: PracticeResult? { session.lastResult }
    /// お題切り替え演出の目印
    var roundIndex: Int { session.roundIndex }

    /// 数直線に描く目盛。**練習モードだけ**に渡す
    var ticks: [LineTick] { session.question.range.practiceTicks() }

    /// 判定確定後だけ目標位置を見せる。本編 `GameViewModel.revealedTargetRatio` と同じ規律
    /// （判定後に正解位置が出ること自体は練習モードの核 ─ 止めた位置と正解位置の差を見るのが
    /// 校正のループ）
    var revealedTargetRatio: Double? {
        session.lastResult == nil ? nil : session.question.target
    }

    /// 描画時刻に対応するカーソル位置比率。ついでに描画時刻を記録する
    func cursorRatio(at time: TimeInterval) -> Double {
        if let frozenCursorRatio { return frozenCursorRatio }
        lastDrawnTime = time
        return clock.ratio(at: time, sweepDuration: session.sweepDuration)
    }

    /// タッチダウン。`DragGesture(minimumDistance: 0).onChanged` から呼ぶ。
    ///
    /// 判断は Core の `PracticeInput` が持つ。ここは action に従うだけ。
    func touchDown() {
        let secondsSinceResult = resultShownTime.map { now() - $0 } ?? 0
        let action = PracticeInput.onTouchDown(
            isTouchConsumed: isTouchConsumed,
            hasResult: session.lastResult != nil,
            secondsSinceResult: secondsSinceResult
        )

        // 「1 タッチ = 1 アクション」は**無条件に消費する**ことで担保する（戻すのは touchUp() だけ）。
        // `.ignore` でも消費すること: 連打ガード中に始まったタッチを消費しないと、指を置いたまま
        // ガードが明けた瞬間の onChanged 再発火が `.advance` に化け、離してタップし直していないのに
        // 次のお題へ進む（DragGesture(minimumDistance: 0) の onChanged は 1 タッチの間に
        // 指のジッタで繰り返し発火する）
        isTouchConsumed = true

        switch action {
        case .ignore:
            return

        case .submit:
            // 基準は「画面に最後に描かれたフレームの時刻」。Date() ではない
            let tapTime = (lastDrawnTime ?? now()) - GameConfig.inputLatencyCompensationSeconds
            let stopRatio = clock.ratio(at: tapTime, sweepDuration: session.sweepDuration)
            frozenCursorRatio = stopRatio
            let result = session.submit(stopRatio: stopRatio)
            resultShownTime = now()
            onJudged?(result.judgement)

        case .advance:
            session.advance()
            frozenCursorRatio = nil
            resultShownTime = nil
            clock.resetOrigin(to: now())
            // 原点を動かしたので前ラウンドの描画時刻は必ず捨てる。
            // 残すと、次のフレームより先にタップされたときに新しい原点より過去の時刻で
            // 位置を計算する。判定表示に制限時間が無い練習では lastDrawnTime が数十秒前で
            // 固まりうるので（frozenCursorRatio != nil の間は更新されない）、
            // elapsed が大きな負値になって折り返しで事実上ランダムな位置が採点される
            lastDrawnTime = nil
        }
    }

    /// タッチアップ。次のタッチダウンを受け付けられるようにする。
    ///
    /// 通常経路で `isTouchConsumed` を false に戻すのはここだけ（1 タッチ = 1 アクションの保証）。
    /// 例外は `resumeFromSceneChange()` で、中断で `touchUp()` が来なかったときに
    /// 入力がロックしたまま復帰するのを防ぐために無条件で解除する
    func touchUp() {
        isTouchConsumed = false
    }

    /// `.active` 復帰時に呼ぶ。
    func resumeFromSceneChange() {
        // 1. 全状態共通で無条件に解除する。中断でタッチが失われると touchUp() が来ず、
        //    判定表示中を「何もしない」で通すと以降のタップが全て弾かれて入力がロックする
        isTouchConsumed = false

        // 2. 時計の扱いだけ Core の判断に従う
        switch PracticeInput.onResume(hasResult: session.lastResult != nil) {
        case .resetCursor:
            lastDrawnTime = nil
            clock.resetOrigin(to: now())
        case .keepFrozen:
            // 判定表示中は時計に触れない（frozenCursorRatio で静止させたまま
            // resultShownTime も維持する）
            break
        }
    }
}
