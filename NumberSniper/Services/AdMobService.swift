import AppTrackingTransparency
import GoogleMobileAds
import UIKit
import NumberSniperCore

/// Google Mobile Ads SDK を `AdServing` の裏に閉じ込める実装。
///
/// `GameCenterService` と同じ「薄いラッパ ＋ コールバックで外部 UI を通知」の形。
/// SDK の型（`MobileAds` / `InterstitialAd` / `RewardedAd`）はこのファイルの外に出さない。
/// v12 以降は Swift 公開名から `GAD` 接頭辞が外れている（13.8.0 のヘッダで実体照合済み。
/// `NS_SWIFT_NAME(MobileAds)` 等）。
///
/// - Important: **プリロードはこの型の責務**（`AdServing` の注記どおり）。`start()` で
///   両フォーマットを 1 本ずつ読み、表示で消費したら即座に次を読む。読み込み失敗時は
///   リトライループを回さない — オフラインなら `isRewardedReady == false` でオファー自体が
///   隠れ、ゲームは通常どおり遊べる（2026-08-01 design §6 の方針）。読み直しの契機は
///   「次の表示要求」と「前景復帰」に限定して、無限リトライによる電池・帯域の浪費を避ける。
@MainActor
final class AdMobService: NSObject, AdServing {
    // MARK: - 広告ユニット ID

    /// Public portfolio build はDebug/ReleaseともGoogle公式テスト広告だけを使用する。
    /// https://developers.google.com/admob/ios/test-ads
    private static let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"
    private static let rewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"

    /// `present` を呼んでから広告が実際に画面に出るまでの猶予。
    /// SDK が present を握りつぶして delegate も呼ばない場合、この上限が無いと
    /// 呼び出し側の await が返らず、リザルトへの遷移とオファーの両方が固まる。
    /// **出画が確認できた後は打ち切らない** —
    /// リワードは 15〜30 秒流れるのが正常で、視聴時間に上限を掛けると完走を壊す。
    /// ゲームのチューニング定数ではないので `GameConfig` には置かない。
    private static let presentationTimeout: Duration = .seconds(5)

    var isRewardedReady: Bool { rewardedAd != nil }

    var onPresentationChanged: ((Bool) -> Void)?

    private var interstitialAd: InterstitialAd?
    private var rewardedAd: RewardedAd?
    private var isStarted = false
    private var isLoadingInterstitial = false
    private var isLoadingRewarded = false
    private var isRequestingTracking = false

    /// 表示中の広告が「実際に画面に出た」か。ウォッチドッグの誤発火防止に使う
    private var hasPresentationStarted = false
    /// 提示の世代。ウォッチドッグ Task はキャンセルされずに猶予いっぱい生き残るので、
    /// **自分が張った提示と現在の提示が同じか**をこれで照合する。無いと「提示 A が即失敗
    /// → 5 秒以内に提示 B 開始 → A の残存ウォッチドッグが B の continuation を早期 resume」
    /// が起き、リワード視聴中に false で返る経路になる
    private var presentationGeneration = 0
    /// いま await している提示の広告インスタンス。delegate の 3 コールバックはこれと
    /// `===` 照合してから効かせる。無照合だと
    /// ウォッチドッグ打ち切り後に遅れて出画した旧広告の通知が次の提示を巻き込む。
    /// ウォッチドッグが打ち切るときは nil 化して旧広告の通知を完全に無視する。
    /// 強参照は呼び出し側のローカル変数が提示中ずっと持っているので weak でよい
    private weak var presentingAd: (any FullScreenPresentingAd)?
    /// いま画面に出ているフルスクリーンコンテンツの深さ。`GADFullScreenContentDelegate.h` は
    /// 「1. 広告本体の提示 2. 広告タップで開くフルスクリーン（クリックスルー）」の**両方**で
    /// 同じ ad インスタンスから present / dismiss が届くと明記している。`===` 照合だけでは
    /// クリックスルーを閉じただけで「広告が閉じた」と誤認し、リワード視聴中に continuation を
    /// 早期 resume してしまう（再レビュー検出）— dismiss で深さが 0 に戻ったときだけ
    /// 広告本体が閉じたとみなす。クリックスルーの present が届かない非対称ケースでも
    /// 深さは負に振れるだけで、従来挙動より悪化しない
    private var presentationDepth = 0
    /// 広告が閉じられるのを待っている await の再開点。**resume は 1 回だけ**
    /// （`resumeDismissal()` が nil 化で多重 resume を防ぐ）
    private var dismissalContinuation: CheckedContinuation<Void, Never>?
    /// リワードの完走フラグ。`userDidEarnRewardHandler` から立てる
    private var didEarnReward = false

    // MARK: - AdServing

    func start() async {
        // ATT を先に完了させる（Game Center の authenticateHandler との競合回避は
        // RootView 側が「ads.start() を await してから認証開始」で担保している）
        await requestTrackingIfNeeded()
        guard !isStarted else { return }
        isStarted = true
        _ = await MobileAds.shared.start()
        loadInterstitial()
        loadRewarded()
    }

    func didBecomeActive() async {
        // 起動時にシーンがまだ active でなかった場合、ATT ダイアログは表示されずに
        // .notDetermined のまま返ってくる。前景化がその出し直しの契機
        await requestTrackingIfNeeded()
        // 読み込み失敗ぶんの読み直しもここが契機（オフライン → 復帰のケース）
        if isStarted {
            loadInterstitial()
            loadRewarded()
        }
    }

    func showInterstitialIfNeeded(_ outcome: GameOverOutcome) async {
        guard outcome.shouldShowInterstitial else { return }
        guard let ad = interstitialAd else {
            // 読めていなければ出さずスキップ（広告ロード失敗は無視してゲーム続行）。
            // 次の機会に備えて読み直しだけ仕掛ける
            loadInterstitial()
            return
        }
        interstitialAd = nil
        onPresentationChanged?(true)
        defer {
            onPresentationChanged?(false)
            loadInterstitial()
        }
        ad.fullScreenContentDelegate = self
        await presentAndAwaitDismissal(of: ad) {
            // rootViewController は nil で SDK に任せる（main window の top VC から出る）。
            // GameCenterService.topViewController() と違い、広告はどの画面からでも出してよい
            ad.present(from: nil)
        }
    }

    func showRewardedForContinue() async -> Bool {
        guard let ad = rewardedAd else { return false }
        rewardedAd = nil
        didEarnReward = false
        onPresentationChanged?(true)
        defer {
            onPresentationChanged?(false)
            loadRewarded()
        }
        ad.fullScreenContentDelegate = self
        await presentAndAwaitDismissal(of: ad) {
            ad.present(from: nil) { [weak self] in
                // 完走したかどうかだけを見る。報酬の数値（adReward.amount）は使わない
                //（管理画面の設定値で、ゲーム側の意味を持たせていない — ads spec）
                self?.didEarnReward = true
            }
        }
        return didEarnReward
    }

    // MARK: - 表示の共通経路

    /// present を呼び、広告が閉じられる（または出せないと判明する）まで待つ。
    ///
    /// 再開経路は 3 つで、どれが来ても `resumeDismissal()` の nil 化により 1 回しか進まない:
    /// 1. `adDidDismissFullScreenContent`（正常系: ユーザーが閉じた）
    /// 2. `didFailToPresentFullScreenContentWithError`（SDK が失敗を報告してきた）
    /// 3. ウォッチドッグ（`presentationTimeout` 内に出画も失敗報告も無い —
    ///    「実 SDK が返らないと固まる」対策。出画済みなら発火しない）
    ///
    /// 1・2 は delegate 側で `presentingAd` と `===` 照合済みの通知だけが届く。
    /// 3 が発火したときは `presentingAd` を nil 化し、打ち切った提示の広告が
    /// 遅れて出画・クローズしても以降の提示に干渉できないようにする
    private func presentAndAwaitDismissal(
        of ad: any FullScreenPresentingAd, _ present: () -> Void
    ) async {
        hasPresentationStarted = false
        presentationDepth = 0
        presentationGeneration += 1
        let generation = presentationGeneration
        presentingAd = ad
        await withCheckedContinuation { continuation in
            dismissalContinuation = continuation
            present()
            Task { [weak self] in
                try? await Task.sleep(for: Self.presentationTimeout)
                guard let self,
                      generation == self.presentationGeneration,
                      !self.hasPresentationStarted else { return }
                self.presentingAd = nil
                self.resumeDismissal()
            }
        }
    }

    private func resumeDismissal() {
        dismissalContinuation?.resume()
        dismissalContinuation = nil
    }

    // MARK: - 読み込み

    private func loadInterstitial() {
        guard interstitialAd == nil, !isLoadingInterstitial else { return }
        isLoadingInterstitial = true
        Task {
            defer { isLoadingInterstitial = false }
            do {
                interstitialAd = try await InterstitialAd.load(
                    with: Self.interstitialAdUnitID, request: Request()
                )
            } catch {
                // 失敗は握りつぶしてよい（機能が隠れるだけ）が、実機確認で
                // no-fill / ユニット ID 誤り / 初期化前を切り分けられるよう痕跡は残す
                #if DEBUG
                print("AdMobService: interstitial load failed: \(error)")
                #endif
            }
        }
    }

    private func loadRewarded() {
        guard rewardedAd == nil, !isLoadingRewarded else { return }
        isLoadingRewarded = true
        Task {
            defer { isLoadingRewarded = false }
            do {
                rewardedAd = try await RewardedAd.load(
                    with: Self.rewardedAdUnitID, request: Request()
                )
            } catch {
                #if DEBUG
                print("AdMobService: rewarded load failed: \(error)")
                #endif
            }
        }
    }

    // MARK: - ATT

    private func requestTrackingIfNeeded() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        guard !isRequestingTracking else { return }
        isRequestingTracking = true
        defer { isRequestingTracking = false }
        // 拒否でも SDK は非パーソナライズ広告で動くので、結果で分岐するのは下の 1 点だけ。
        // IDFA を直接読むコードはこのアプリに無い
        let status = await ATTrackingManager.requestTrackingAuthorization()
        if status == .authorized, isStarted {
            // .notDetermined の間に読んでしまった在庫は非パーソナライズのまま消費される
            // （起動時にダイアログを出せなかった場合、SDK 初期化とプリロードが ATT より
            // 先行する）。許可ユーザーの初回セッションにそれを見せないよう捨てて読み直す。
            // このメソッドが走るのは start() / didBecomeActive() だけで提示中とは重ならない
            interstitialAd = nil
            rewardedAd = nil
            loadInterstitial()
            loadRewarded()
        }
    }
}

// MARK: - FullScreenContentDelegate

extension AdMobService: FullScreenContentDelegate {
    // どのコールバックも「いま await している提示の広告」からの通知だけを効かせる
    //（ガードの理由は `presentingAd` の doc コメント参照）

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        guard ad === presentingAd else { return }
        // 出画が確認できたのでウォッチドッグを無効化（以降は「閉じた」通知だけを待つ）
        hasPresentationStarted = true
        presentationDepth += 1
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        guard ad === presentingAd else { return }
        presentationDepth -= 1
        // クリックスルー画面（広告タップで開いた方）を閉じただけなら広告本体はまだ出ている
        guard presentationDepth <= 0 else { return }
        presentingAd = nil
        resumeDismissal()
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        guard ad === presentingAd else { return }
        presentingAd = nil
        #if DEBUG
        print("AdMobService: present failed: \(error)")
        #endif
        resumeDismissal()
    }
}
