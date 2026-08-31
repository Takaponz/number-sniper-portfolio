import Foundation

/// キー・バリュー永続化の最小インターフェース。
/// `UserDefaults` はこの 6 メソッドをそのまま持っているので、空の extension で適合する。
///
/// - Note: 文字列の書き込みは `set(_ value: Any?, forKey:)` を使う。`UserDefaults` に
///   `String` 専用のオーバーロードは存在しない（`Int` / `Float` / `Double` / `Bool` /
///   `URL` / `Any?` のみ）ため、`set(_ value: String, forKey:)` を要求すると
///   空 extension での適合が壊れる。
public protocol KeyValueStore: AnyObject {
    func integer(forKey defaultName: String) -> Int
    func object(forKey defaultName: String) -> Any?
    func string(forKey defaultName: String) -> String?
    func set(_ value: Int, forKey defaultName: String)
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
}

/// ゲームオーバー時に決まること。
public struct GameOverOutcome: Sendable, Equatable {
    public let isNewBest: Bool
    public let shouldShowInterstitial: Bool
    /// Game Center へ送るべきスコア。送信成功したら
    /// `clearPendingLeaderboardScore(ifEquals:)` を呼ぶ
    public let pendingLeaderboardScore: Int?

    public init(
        isNewBest: Bool,
        shouldShowInterstitial: Bool,
        pendingLeaderboardScore: Int?
    ) {
        self.isNewBest = isNewBest
        self.shouldShowInterstitial = shouldShowInterstitial
        self.pendingLeaderboardScore = pendingLeaderboardScore
    }
}

/// ハイスコア・広告表示カウンタ・Game Center 未送信ベストの永続化。
///
/// 難易度選択を廃止したので、ハイスコアも未送信ベストもリーダーボードも **1 本**。
public final class ScoreStore {
    private enum Key {
        static let highScore = "number_sniper.high_score"
        static let gameOverCount = "number_sniper.game_over_count"
        static let pendingLeaderboardScore = "number_sniper.pending_leaderboard_score"
    }

    private let store: KeyValueStore

    public init(store: KeyValueStore) {
        self.store = store
    }

    public var highScore: Int { store.integer(forKey: Key.highScore) }

    public var gameOverCount: Int { store.integer(forKey: Key.gameOverCount) }

    /// Game Center へ未送信のベストスコア。送信失敗が恒久化しないように永続化する。
    public var pendingLeaderboardScore: Int? {
        store.object(forKey: Key.pendingLeaderboardScore) as? Int
    }

    /// 送信に成功したら呼ぶ。
    ///
    /// - Important: 送信を待っている間に新しいベストが記録されている可能性があるため、
    ///   「今も同じスコアが未送信として残っている」ときだけ消す。無条件に消すと、
    ///   古いスコアの送信成功が新しい未送信ベストを取りこぼす。
    public func clearPendingLeaderboardScore(ifEquals score: Int) {
        guard pendingLeaderboardScore == score else { return }
        store.removeObject(forKey: Key.pendingLeaderboardScore)
    }

    /// 送信に失敗したときの再送予約。
    ///
    /// - Important: 現在の未送信ベストより低いスコアでは**上書きしない**。送信は非同期なので
    ///   完了順が入れ替わりうる（700 の送信中に 900 が新ベストになり、900 が先に失敗、
    ///   あとから 700 が失敗する）。無条件に上書きすると、この順序で未送信の 900 が
    ///   700 に巻き戻って再送対象から消える。
    public func markLeaderboardSendPending(score: Int) {
        guard score > (pendingLeaderboardScore ?? 0) else { return }
        store.set(score, forKey: Key.pendingLeaderboardScore)
    }

    /// ゲームオーバーを記録する。ベスト更新判定と広告表示判定をまとめて返す。
    ///
    /// - Parameter didRevive: このプレイでリワード広告を見て復活したか。true なら
    ///   終了後インタースティシャルを**免除する**（1 プレイで広告 2 本は多すぎる）。
    ///   `gameOverCount` は「ゲームオーバーの回数」という事実なので didRevive でも進める。
    /// - Note: 復活したプレイでも `highScore` とリーダーボードは通常どおり更新する。
    ///   復活が 1 回上限でスコアの膨張が有界なため、リーダーボードを分けずに済む。
    @discardableResult
    public func recordGameOver(score: Int, didRevive: Bool = false) -> GameOverOutcome {
        let isNewBest = score > highScore
        if isNewBest {
            store.set(score, forKey: Key.highScore)
            store.set(score, forKey: Key.pendingLeaderboardScore)
        }

        // カウンタは再起動での回避・リセットを防ぐため必ず永続化する
        let count = gameOverCount + 1
        store.set(count, forKey: Key.gameOverCount)

        return GameOverOutcome(
            isNewBest: isNewBest,
            shouldShowInterstitial: Self.shouldShowInterstitial(
                gameOverCount: count,
                frequency: GameConfig.gameOversPerInterstitial,
                didRevive: didRevive
            ),
            pendingLeaderboardScore: pendingLeaderboardScore
        )
    }

    /// 終了後インタースティシャルを出すかの判断。
    ///
    /// - Important: **頻度を引数で受ける純粋関数にしてある。** `GameConfig` の定数を直読みすると、
    ///   出荷値の頻度 1（毎回）では `count % 1 == 0` が恒真になり、**この判定の false 側を踏む
    ///   テストが 1 つも書けなくなる**（`shouldShowInterstitial: !didRevive` と書き換えても
    ///   全テストが通ってしまい、「頻度を 2 に戻すだけで調整できる」というロールバック計画の
    ///   動作保証が消える）。頻度を注入できる形にして両側を固定する。
    /// - Note: `frequency` が 0 だと `%` がゼロ除算でクラッシュする。invariant は
    ///   `GameConfigTests` が固定しているが、注入経路ができたのでここでも弾く。
    static func shouldShowInterstitial(gameOverCount: Int, frequency: Int, didRevive: Bool) -> Bool {
        precondition(frequency >= 1, "広告頻度は 1 以上（0 は剰余がゼロ除算になる）")

        return gameOverCount % frequency == 0 && !didRevive
    }
}
