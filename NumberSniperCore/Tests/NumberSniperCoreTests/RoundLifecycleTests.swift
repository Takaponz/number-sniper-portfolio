import Testing
@testable import NumberSniperCore

@Suite("シーン遷移への反応")
struct RoundLifecycleTests {
    @Test("プレイ中に非アクティブになったらカウントダウン待ちに入る")
    func pausesWhilePlaying() {
        let next = RoundLifecycle.onSceneInactive(
            from: .playing, isSuspendedByExternalUI: false, isGameOverPending: false
        )
        #expect(next == .countdown(remaining: GameConfig.resumeCountdownSeconds))
    }

    @Test("カウントダウン中に再び非アクティブになったら最初からやり直す")
    func restartsCountdown() {
        let next = RoundLifecycle.onSceneInactive(
            from: .countdown(remaining: 1), isSuspendedByExternalUI: false, isGameOverPending: false
        )
        #expect(next == .countdown(remaining: GameConfig.resumeCountdownSeconds))
    }

    @Test("広告・ATT・Game Center の UI 表示中は一時停止しない")
    func doesNotPauseForExternalUI() {
        #expect(RoundLifecycle.onSceneInactive(
            from: .playing, isSuspendedByExternalUI: true, isGameOverPending: false
        ) == nil)
    }

    @Test("ゲームオーバーの判定表示中は一時停止しない")
    func doesNotPauseWhileRevealingGameOver() {
        #expect(RoundLifecycle.onSceneInactive(
            from: .playing, isSuspendedByExternalUI: false, isGameOverPending: true
        ) == nil)
    }

    @Test("ゲームオーバー後は一時停止しない")
    func doesNotPauseAfterGameOver() {
        #expect(RoundLifecycle.onSceneInactive(
            from: .gameOver, isSuspendedByExternalUI: false, isGameOverPending: false
        ) == nil)
    }

    @Test("カウントダウン待ちのときだけ復帰カウントダウンを始める")
    func startsCountdownOnlyWhenPending() {
        #expect(RoundLifecycle.shouldStartCountdown(
            from: .countdown(remaining: 3), isSuspendedByExternalUI: false
        ))
        #expect(!RoundLifecycle.shouldStartCountdown(
            from: .playing, isSuspendedByExternalUI: false
        ))
        #expect(!RoundLifecycle.shouldStartCountdown(
            from: .gameOver, isSuspendedByExternalUI: false
        ))
        #expect(!RoundLifecycle.shouldStartCountdown(
            from: .countdown(remaining: 3), isSuspendedByExternalUI: true
        ))
    }

    // MARK: - 復活オファー中の中断

    @Test("復活オファーの秒読み中に非アクティブになったら秒読みを止める")
    func stopsOfferCountdownWhenInactive() {
        // Task.sleep は端末が休んでいる間も進むので、止めないと電話 1 本で
        // オファーを取り逃がす
        #expect(RoundLifecycle.onSceneInactiveDuringOffer(from: .continueOffer(remaining: 5)))
    }

    @Test("オファー中以外では秒読み停止の判断は働かない")
    func doesNotStopOfferCountdownInOtherPhases() {
        #expect(!RoundLifecycle.onSceneInactiveDuringOffer(from: .playing))
        #expect(!RoundLifecycle.onSceneInactiveDuringOffer(from: .countdown(remaining: 3)))
        #expect(!RoundLifecycle.onSceneInactiveDuringOffer(from: .gameOver))
    }

    @Test("復帰したらオファーの秒読みを再開する")
    func resumesOfferAfterReturning() {
        #expect(RoundLifecycle.shouldResumeOffer(
            from: .continueOffer(remaining: 5), isSuspendedByExternalUI: false
        ))
    }

    @Test("広告 UI を出している間はオファーの秒読みを再開しない")
    func doesNotResumeOfferWhilePresentingAd() {
        // 「広告を見て復活」を押した直後の遷移で秒読みが復活すると、
        // 広告を見ている裏で 0 になりゲームオーバーが確定してしまう
        #expect(!RoundLifecycle.shouldResumeOffer(
            from: .continueOffer(remaining: 5), isSuspendedByExternalUI: true
        ))
    }

    @Test("オファー中以外では秒読み再開の判断は働かない")
    func doesNotResumeOfferInOtherPhases() {
        #expect(!RoundLifecycle.shouldResumeOffer(from: .playing, isSuspendedByExternalUI: false))
        #expect(!RoundLifecycle.shouldResumeOffer(
            from: .countdown(remaining: 3), isSuspendedByExternalUI: false
        ))
        #expect(!RoundLifecycle.shouldResumeOffer(from: .gameOver, isSuspendedByExternalUI: false))
    }

    @Test("復活オファー中は 3 秒の復帰カウントダウンを挟まない")
    func offerDoesNotTriggerResumeCountdown() {
        // まだ復活しておらずゲームが動いていないので、身構える時間は要らない。
        // 秒読みは残り秒数から再開する（shouldResumeOffer 側の役目）
        #expect(!RoundLifecycle.shouldStartCountdown(
            from: .continueOffer(remaining: 5), isSuspendedByExternalUI: false
        ))
    }

    @Test("復活オファー中は通常の一時停止経路に入らない")
    func offerIsNotHandledByNormalPause() {
        // オファー中は必ずライフ 0（isGameOverPending）。ここで .countdown へ移ると
        // 秒読みの残りが失われ、オファーが復帰カウントダウンに化ける
        #expect(RoundLifecycle.onSceneInactive(
            from: .continueOffer(remaining: 5),
            isSuspendedByExternalUI: false,
            isGameOverPending: true
        ) == nil)
        // isGameOverPending の早期 return に頼らず、phase 単体でも nil を返すこと
        #expect(RoundLifecycle.onSceneInactive(
            from: .continueOffer(remaining: 5),
            isSuspendedByExternalUI: false,
            isGameOverPending: false
        ) == nil)
    }

    // MARK: - オファーの手前（最後の判定を見せている間）の中断

    @Test("最後の判定を見せている間に非アクティブになったらオファーの判断を先送りする")
    func inactiveDuringFinalJudgementDefersOffer() {
        // phase はまだ .playing・engine だけライフ 0 という 0.45 秒の窓。
        // ここを畳まないと、誰も見ていない画面でオファーの秒読み 8 秒が消化される
        #expect(RoundLifecycle.onSceneInactiveBeforeOffer(
            from: .playing,
            isSuspendedByExternalUI: false,
            isGameOverPending: true
        ))
    }

    @Test("生きているラウンドの中断は先送りの対象にならない")
    func inactiveWhileAliveDoesNotDefer() {
        // ライフが残っているなら通常の一時停止（onSceneInactive）の担当
        #expect(!RoundLifecycle.onSceneInactiveBeforeOffer(
            from: .playing,
            isSuspendedByExternalUI: false,
            isGameOverPending: false
        ))
        // 判定表示より後ろの phase は、それぞれ専用の経路が持つ
        #expect(!RoundLifecycle.onSceneInactiveBeforeOffer(
            from: .continueOffer(remaining: 5),
            isSuspendedByExternalUI: false,
            isGameOverPending: true
        ))
        #expect(!RoundLifecycle.onSceneInactiveBeforeOffer(
            from: .gameOver,
            isSuspendedByExternalUI: false,
            isGameOverPending: true
        ))
        #expect(!RoundLifecycle.onSceneInactiveBeforeOffer(
            from: .countdown(remaining: 3),
            isSuspendedByExternalUI: false,
            isGameOverPending: true
        ))
    }

    @Test("広告・ATT・Game Center の UI 表示中は先送りしない")
    func externalUIDoesNotDeferOffer() {
        #expect(!RoundLifecycle.onSceneInactiveBeforeOffer(
            from: .playing,
            isSuspendedByExternalUI: true,
            isGameOverPending: true
        ))
    }

    @Test("復帰したら先送りしていた判断を再開する")
    func resumesDeferredOfferDecision() {
        #expect(RoundLifecycle.shouldResumeBeforeOffer(
            isOfferDecisionDeferred: true, isSuspendedByExternalUI: false
        ))
        // 先送りしていないなら何もしない（通常のラウンド進行を邪魔しない）
        #expect(!RoundLifecycle.shouldResumeBeforeOffer(
            isOfferDecisionDeferred: false, isSuspendedByExternalUI: false
        ))
        // 外部 UI が出ている間は再開しない（閉じた側が畳み直す）
        #expect(!RoundLifecycle.shouldResumeBeforeOffer(
            isOfferDecisionDeferred: true, isSuspendedByExternalUI: true
        ))
    }
}
