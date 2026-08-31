import GameKit
import UIKit
import NumberSniperCore

/// Game Center リーダーボード 1 本ぶんの薄いラッパ。
///
/// - `authenticateHandler` は**代入した時点で認証が走る**ので、ATT ダイアログが
///   閉じるまで設定しない（システムアラートの競合回避）。
/// - サインイン UI はタイトル画面表示中にだけ提示する。プレイ中・リザルト中は出さない。
/// - 認証失敗時はランキング UI を隠すだけで、ゲームは通常どおり遊べる。
@MainActor
final class GameCenterService: NSObject {
    private(set) var isAuthenticated = false

    /// タイトル画面表示中だけ true にする。false の間はサインイン UI を保留する
    var canPresentSignInUI = false {
        didSet { if canPresentSignInUI { presentPendingSignInIfPossible() } }
    }

    var onAuthenticationChanged: ((Bool) -> Void)?
    /// Game Center の UI を出している間 true。シーン遷移の一時停止を抑止するために使う
    var onPresentationChanged: ((Bool) -> Void)?

    private let scoreStore: ScoreStore
    private var pendingSignInViewController: UIViewController?
    /// サインイン UI を提示中か。閉じたときに外部UIフラグを必ず戻すために持つ
    private var isPresentingSignIn = false

    init(scoreStore: ScoreStore) {
        self.scoreStore = scoreStore
        super.init()
    }

    /// ATT ダイアログの処理が終わったあとに 1 回だけ呼ぶ。
    func startAuthentication() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            // GameKit は通常このハンドラをメインスレッドで呼ぶが、それを前提にした
            // `MainActor.assumeIsolated` は前提が崩れた瞬間に fatalError になる。
            // ここは劣化ではなくクラッシュになる場所なので、ホップ 1 回を払って
            // 呼び出しスレッドに依存しない形にしておく
            Task { @MainActor in
                self?.handleAuthentication(viewController: viewController)
            }
        }
    }

    /// シーンが `.active` に戻ったときに呼ぶ。
    ///
    /// バックグラウンド中に `authenticateHandler` がサインイン UI を渡してきた場合、
    /// 提示先の foregroundActive なシーンが無いので保留される。保留の再試行契機は
    /// `authenticateHandler` の再呼び出しと `canPresentSignInUI` の didSet しかないため、
    /// タイトル表示中（既に `canPresentSignInUI == true`）だと前景に戻っても誰も
    /// 出し直さず、画面を離れて戻るまで認証が滞留する。ここが前景化の再試行契機になる。
    func didBecomeActive() {
        presentPendingSignInIfPossible()
    }

    /// ベスト更新時だけ送信する。失敗したら未送信ベストとして残す。
    func submitIfNeeded(_ outcome: GameOverOutcome) async {
        guard let score = outcome.pendingLeaderboardScore else { return }
        await submit(score: score)
    }

    /// 起動時・認証完了時に呼ぶ再送。
    func flushPendingScores() async {
        guard let score = scoreStore.pendingLeaderboardScore else { return }
        await submit(score: score)
    }

    /// ランキングを開く。タイトル画面・リザルト画面の両方から呼ばれる。
    func showLeaderboard() {
        guard isAuthenticated, let presenter = Self.topViewController() else { return }
        let controller = GKGameCenterViewController(
            leaderboardID: GameConfig.leaderboardID,
            playerScope: .global,
            timeScope: .allTime
        )
        controller.gameCenterDelegate = self
        onPresentationChanged?(true)
        presenter.present(controller, animated: true)
    }

    // MARK: - 内部

    private func handleAuthentication(viewController: UIViewController?) {
        if let viewController {
            pendingSignInViewController = viewController
            presentPendingSignInIfPossible()
            return
        }

        // viewController が nil で呼ばれた = サインイン UI が閉じた（成功・キャンセルとも）。
        // ここで外部UIフラグを必ず戻さないと、以降バックグラウンド復帰の
        // カウントダウンが二度と出なくなる
        if isPresentingSignIn {
            isPresentingSignIn = false
            onPresentationChanged?(false)
        }

        isAuthenticated = GKLocalPlayer.local.isAuthenticated
        onAuthenticationChanged?(isAuthenticated)
        if isAuthenticated {
            Task { await flushPendingScores() }
        }
    }

    private func presentPendingSignInIfPossible() {
        guard canPresentSignInUI,
              let viewController = pendingSignInViewController,
              let presenter = Self.topViewController() else { return }
        pendingSignInViewController = nil
        isPresentingSignIn = true
        onPresentationChanged?(true)
        presenter.present(viewController, animated: true)
    }

    private func submit(score: Int) async {
        guard isAuthenticated else { return }
        do {
            try await GKLeaderboard.submitScore(
                score,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [GameConfig.leaderboardID]
            )
            // 送信を待っている間に新しいベストが記録されていたら消さない
            scoreStore.clearPendingLeaderboardScore(ifEquals: score)
        } catch {
            // ローカルと Game Center のベスト不一致が恒久化しないよう、再送予約を残す
            scoreStore.markLeaderboardSendPending(score: score)
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

extension GameCenterService: GKGameCenterControllerDelegate {
    nonisolated func gameCenterViewControllerDidFinish(
        _ gameCenterViewController: GKGameCenterViewController
    ) {
        MainActor.assumeIsolated {
            gameCenterViewController.dismiss(animated: true)
            onPresentationChanged?(false)
        }
    }
}
