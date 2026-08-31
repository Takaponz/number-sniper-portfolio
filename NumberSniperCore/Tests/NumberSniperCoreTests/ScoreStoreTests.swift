import Testing
import Foundation
@testable import NumberSniperCore

/// テスト用のインメモリ永続化。
final class InMemoryKeyValueStore: KeyValueStore {
    private var values: [String: Any] = [:]
    func integer(forKey defaultName: String) -> Int { values[defaultName] as? Int ?? 0 }
    func object(forKey defaultName: String) -> Any? { values[defaultName] }
    func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
    func set(_ value: Int, forKey defaultName: String) { values[defaultName] = value }
    func set(_ value: Any?, forKey defaultName: String) {
        if let value { values[defaultName] = value } else { values.removeValue(forKey: defaultName) }
    }
    func removeObject(forKey defaultName: String) { values.removeValue(forKey: defaultName) }
}

@Suite("永続化")
struct ScoreStoreTests {
    @Test("初回はハイスコア 0、未送信ベストなし")
    func emptyInitialState() {
        let store = ScoreStore(store: InMemoryKeyValueStore())
        #expect(store.highScore == 0)
        #expect(store.gameOverCount == 0)
        #expect(store.pendingLeaderboardScore == nil)
    }

    @Test("ベスト更新時だけハイスコアが書き換わる")
    func onlyUpdatesOnNewBest() {
        let store = ScoreStore(store: InMemoryKeyValueStore())
        #expect(store.recordGameOver(score: 500).isNewBest)
        #expect(store.highScore == 500)

        #expect(!store.recordGameOver(score: 400).isNewBest)
        #expect(store.highScore == 500)

        #expect(store.recordGameOver(score: 900).isNewBest)
        #expect(store.highScore == 900)
    }

    @Test("同点はベスト更新にならない")
    func tieIsNotNewBest() {
        let store = ScoreStore(store: InMemoryKeyValueStore())
        _ = store.recordGameOver(score: 500)
        #expect(!store.recordGameOver(score: 500).isNewBest)
    }

    @Test("ゲームオーバーのたびに広告を出す")
    func interstitialOnEveryGameOver() {
        // 期待値をリテラルで書くのは意図的。`gameOversPerInterstitial` から導出すると
        // 定数を変えたときにテストが追従して通ってしまい、頻度の回帰を検出できなくなる
        let store = ScoreStore(store: InMemoryKeyValueStore())
        #expect(store.recordGameOver(score: 10).shouldShowInterstitial)   // 1 回目
        #expect(store.recordGameOver(score: 20).shouldShowInterstitial)   // 2 回目
        #expect(store.recordGameOver(score: 30).shouldShowInterstitial)   // 3 回目
    }

    @Test("頻度 2 に戻したら 1 回おきに出る")
    func interstitialRespectsFrequency() {
        // 出荷値は 1（毎回）だが `count % 1 == 0` は恒真なので、`recordGameOver` 経由の
        // テストだけでは**この判定の false 側を一度も踏めない**（`!didRevive` と書き換えても
        // 全テストが通る）。頻度を注入して両側を固定し、「2 に戻すだけで調整できる」ことを保証する
        #expect(!ScoreStore.shouldShowInterstitial(gameOverCount: 1, frequency: 2, didRevive: false))
        #expect(ScoreStore.shouldShowInterstitial(gameOverCount: 2, frequency: 2, didRevive: false))
        #expect(!ScoreStore.shouldShowInterstitial(gameOverCount: 3, frequency: 2, didRevive: false))
        #expect(ScoreStore.shouldShowInterstitial(gameOverCount: 4, frequency: 2, didRevive: false))
    }

    @Test("復活の免除は頻度に関係なく効く")
    func revivedGameSkipsInterstitialAtAnyFrequency() {
        // 頻度側の条件を満たす回数でも didRevive が勝つこと（&& の両辺が生きている）
        #expect(!ScoreStore.shouldShowInterstitial(gameOverCount: 2, frequency: 2, didRevive: true))
        #expect(!ScoreStore.shouldShowInterstitial(gameOverCount: 1, frequency: 1, didRevive: true))
    }

    @Test("復活したプレイは終了後の広告を免除する")
    func revivedGameSkipsInterstitial() {
        let store = ScoreStore(store: InMemoryKeyValueStore())
        #expect(!store.recordGameOver(score: 10, didRevive: true).shouldShowInterstitial)
        // 免除は当該プレイだけ。次の通常プレイでは通常どおり出す
        #expect(store.recordGameOver(score: 20).shouldShowInterstitial)
    }

    @Test("復活したプレイでもゲームオーバー回数は進む")
    func revivedGameStillCountsAsGameOver() {
        let store = ScoreStore(store: InMemoryKeyValueStore())
        _ = store.recordGameOver(score: 10, didRevive: true)
        #expect(store.gameOverCount == 1, "広告を免除しても「終わった」事実は記録する")
    }

    @Test("復活したプレイでもベスト更新とリーダーボード送信は通常どおり")
    func revivedGameStillRecordsBest() {
        // 復活は 1 回上限でスコアの膨張が有界なので、リーダーボードを分けずに 1 本のまま扱う
        let store = ScoreStore(store: InMemoryKeyValueStore())
        let outcome = store.recordGameOver(score: 900, didRevive: true)
        #expect(outcome.isNewBest)
        #expect(outcome.pendingLeaderboardScore == 900)
        #expect(store.highScore == 900)
    }

    @Test("広告カウンタは永続化され、再起動でリセットされない")
    func gameOverCountSurvivesRestart() {
        // `shouldShowInterstitial` で見ると頻度 1 では 1 回目も 2 回目も true になり、
        // 永続化されていなくても通ってしまう。カウンタそのものを見て弁別する
        let backing = InMemoryKeyValueStore()
        _ = ScoreStore(store: backing).recordGameOver(score: 10)  // 1 回目
        // 別インスタンス = 再起動相当
        _ = ScoreStore(store: backing).recordGameOver(score: 20)  // 2 回目
        #expect(ScoreStore(store: backing).gameOverCount == 2)
    }

    @Test("ハイスコアは永続化され、再起動で復元される")
    func highScoreSurvivesRestart() {
        let backing = InMemoryKeyValueStore()
        _ = ScoreStore(store: backing).recordGameOver(score: 900)
        #expect(ScoreStore(store: backing).highScore == 900)
    }

    @Test("ベスト更新時は未送信ベストが記録される")
    func newBestSchedulesLeaderboardSend() {
        let store = ScoreStore(store: InMemoryKeyValueStore())
        let outcome = store.recordGameOver(score: 700)
        #expect(outcome.pendingLeaderboardScore == 700)
        #expect(store.pendingLeaderboardScore == 700)
    }

    @Test("送信成功後にクリアでき、失敗時は再度記録できる")
    func clearAndRemarkPending() {
        let store = ScoreStore(store: InMemoryKeyValueStore())
        _ = store.recordGameOver(score: 700)
        store.clearPendingLeaderboardScore(ifEquals: 700)
        #expect(store.pendingLeaderboardScore == nil)

        store.markLeaderboardSendPending(score: 700)
        #expect(store.pendingLeaderboardScore == 700)
    }

    @Test("送信待ちの間に新しいベストが出たら、古いスコアの送信成功で消さない")
    func clearDoesNotDropNewerPending() {
        let store = ScoreStore(store: InMemoryKeyValueStore())
        _ = store.recordGameOver(score: 700)   // 700 の送信を開始したとする
        _ = store.recordGameOver(score: 900)   // 送信を待っている間に新ベスト
        store.clearPendingLeaderboardScore(ifEquals: 700)  // 700 の送信が成功
        #expect(store.pendingLeaderboardScore == 900)
    }

    @Test("送信失敗の完了順が入れ替わっても、未送信ベストが低いスコアに巻き戻らない")
    func markDoesNotRegressPending() {
        let store = ScoreStore(store: InMemoryKeyValueStore())
        _ = store.recordGameOver(score: 700)   // 700 の送信を開始
        _ = store.recordGameOver(score: 900)   // 送信中に新ベスト 900
        store.markLeaderboardSendPending(score: 900)  // 900 が先に失敗
        #expect(store.pendingLeaderboardScore == 900)

        store.markLeaderboardSendPending(score: 700)  // あとから 700 が失敗
        #expect(store.pendingLeaderboardScore == 900, "低いスコアに巻き戻った")
    }

    @Test("未送信ベストがない状態なら、失敗したスコアが再送予約される")
    func markRecordsWhenNothingPending() {
        let store = ScoreStore(store: InMemoryKeyValueStore())
        _ = store.recordGameOver(score: 700)
        store.clearPendingLeaderboardScore(ifEquals: 700)
        #expect(store.pendingLeaderboardScore == nil)

        store.markLeaderboardSendPending(score: 700)
        #expect(store.pendingLeaderboardScore == 700)
    }

    @Test("ベスト未更新のゲームオーバーは未送信ベストを壊さない")
    func lowerScoreDoesNotTouchPending() {
        let store = ScoreStore(store: InMemoryKeyValueStore())
        _ = store.recordGameOver(score: 700)
        let outcome = store.recordGameOver(score: 100)
        #expect(!outcome.isNewBest)
        #expect(store.pendingLeaderboardScore == 700)
    }

    @Test("リーダーボード ID は App Store Connect に登録する 1 本で固定")
    func leaderboardIDIsStable() {
        // リリース後は変えられない。App Store Connect の登録と一字一句合っていること
        #expect(GameConfig.leaderboardID == "com.example.numbersniper.highscore")
    }

    @Test("永続化キーはリリース済み v1.0 と同じ無サフィックス版")
    func usesUnsuffixedLegacyKeys() {
        // 書いて読み戻すテストだけではキー文字列の回帰を弁別できない
        // （難易度サフィックス付きに戻しても対称に壊れて全部通る）。
        // v1.0/v1.0.1 ユーザーのハイスコアを引き継ぐため、キーを直接固定する
        let backing = InMemoryKeyValueStore()
        backing.set(700, forKey: "number_sniper.high_score")
        backing.set(1, forKey: "number_sniper.game_over_count")
        backing.set(700, forKey: "number_sniper.pending_leaderboard_score")
        let store = ScoreStore(store: backing)
        #expect(store.highScore == 700)
        #expect(store.gameOverCount == 1)
        #expect(store.pendingLeaderboardScore == 700)
    }
}
