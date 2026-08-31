import Foundation

/// ラウンドの進行状態。
public enum RoundPhase: Sendable, Equatable {
    case playing
    /// バックグラウンド復帰待ち（カウントダウン表示中も含む）
    case countdown(remaining: Int)
    /// ライフ 0 のあと、リワード広告での復活を提案している最中（秒読み表示中）。
    /// ここから `.playing`（復活）か `.gameOver`（辞退・タイムアウト）へ抜ける
    case continueOffer(remaining: Int)
    case gameOver
}

/// シーン遷移に対して進行状態をどう動かすかの判断。純粋関数だけを持つ。
public enum RoundLifecycle {
    /// シーンが非アクティブ（`.inactive` / `.background`）になったときの遷移先。
    /// `nil` は「何もしない」。
    ///
    /// - Parameters:
    ///   - isSuspendedByExternalUI: 広告・ATT・Game Center の UI を出している間は true。
    ///     これらによるシーン遷移で一時停止すると、UI を閉じた直後に不要な
    ///     カウントダウンが挟まる
    ///   - isGameOverPending: ゲームオーバーの判定を見せている最中は true。
    ///     ここで一時停止に入るとライフ 0 のままプレイ状態へ復帰してしまう
    public static func onSceneInactive(
        from phase: RoundPhase,
        isSuspendedByExternalUI: Bool,
        isGameOverPending: Bool
    ) -> RoundPhase? {
        guard !isSuspendedByExternalUI, !isGameOverPending else { return nil }
        switch phase {
        case .playing, .countdown:
            // カウントダウン途中の再中断も、必ず最初からやり直す
            return .countdown(remaining: GameConfig.resumeCountdownSeconds)
        case .continueOffer:
            // オファー中は engine がライフ 0（= isGameOverPending）なので、実際には上の
            // guard で弾かれてここへは来ない。復活オファーの中断は
            // `onSceneInactiveDuringOffer` が専用に扱う（秒読みだけ止めて phase は保つ）
            return nil
        case .gameOver:
            return nil
        }
    }

    /// シーンが `.active` に戻ったときに、復帰カウントダウンを始めてよいか。
    public static func shouldStartCountdown(
        from phase: RoundPhase,
        isSuspendedByExternalUI: Bool
    ) -> Bool {
        guard !isSuspendedByExternalUI else { return false }
        if case .countdown = phase { return true }
        return false
    }

    // MARK: - 復活オファーの手前（最後の判定を見せている間）の中断

    /// 最後の判定を見せている `interRoundPauseSeconds` の間にシーンが非アクティブになったら、
    /// **復活オファーを出すかどうかの判断を復帰まで先送りすべきか**。
    ///
    /// この窓では phase はまだ `.playing` のままで、`engine` だけがライフ 0 になっている。
    /// そのため `onSceneInactive` は `isGameOverPending` で早期 return し（＝ phase を動かさないのが正しい）、
    /// `onSceneInactiveDuringOffer` はまだ `.continueOffer` になっていないので false を返す。
    /// **どちらも畳まないので、放っておくと誰も見ていない画面でオファーの秒読み 8 秒が
    /// 丸ごと消化されてしまう**（`Task.sleep` は端末が休んでいる間も進む）。
    ///
    /// - Note: 先送りしている間も phase は `.playing` のまま。復帰したら遅延を張り直して
    ///   同じ分岐（オファー or ゲームオーバー確定）をやり直す。
    public static func onSceneInactiveBeforeOffer(
        from phase: RoundPhase,
        isSuspendedByExternalUI: Bool,
        isGameOverPending: Bool
    ) -> Bool {
        guard !isSuspendedByExternalUI, isGameOverPending else { return false }
        return phase == .playing
    }

    /// 先送りしていた判断を、シーンが `.active` に戻ったところで再開してよいか。
    ///
    /// - Parameter isOfferDecisionDeferred: `onSceneInactiveBeforeOffer` で先送りした状態か
    public static func shouldResumeBeforeOffer(
        isOfferDecisionDeferred: Bool,
        isSuspendedByExternalUI: Bool
    ) -> Bool {
        guard !isSuspendedByExternalUI else { return false }
        return isOfferDecisionDeferred
    }

    // MARK: - 復活オファー中の中断

    /// 復活オファーの秒読み中にシーンが非アクティブになったら、秒読みを止めるべきか。
    ///
    /// `Task.sleep` は端末が休んでいる間も進むので、止めないと**電話 1 本でオファーを
    /// 取り逃がす**。`onSceneInactive` は `isGameOverPending`（ライフ 0）で早期 return する
    /// 作りで、オファー中は必ずライフ 0 なのでそちらでは扱えない。
    ///
    /// - Note: 戻り値が true でも `phase` は `.continueOffer(remaining:)` のまま保つ。
    ///   復帰時に**残り秒数から**張り直すため（`shouldResumeOffer`）。
    public static func onSceneInactiveDuringOffer(from phase: RoundPhase) -> Bool {
        if case .continueOffer = phase { return true }
        return false
    }

    /// シーンが `.active` に戻ったときに、オファーの秒読みを残り秒数から再開してよいか。
    ///
    /// - Note: 通常の復帰と違って 3 秒の復帰カウントダウンは挟まない。**まだ復活しておらず
    ///   ゲームが動いていない**ので、身構える時間が要らない。
    public static func shouldResumeOffer(
        from phase: RoundPhase,
        isSuspendedByExternalUI: Bool
    ) -> Bool {
        guard !isSuspendedByExternalUI else { return false }
        if case .continueOffer = phase { return true }
        return false
    }
}
