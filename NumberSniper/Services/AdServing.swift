import Foundation
import NumberSniperCore

/// 広告 SDK を隔離する 1 枚の境界。
///
/// `GameCenterService` と同じ「薄いラッパ ＋ コールバックで外部 UI を通知」の形に揃えてある。
/// アプリ側はこのプロトコルしか知らないので、AdMob SDK がなくても
/// `StubAdService` で広告表示を伴うゲームフローを検証できる。
///
/// - Important: **プリロードはこの型の責務。** `isRewardedReady` が意味を持つには
///   プレイ中にあらかじめ読み込んでおく必要がある（ライフ 0 になってから読み始めると
///   秒読み 8 秒に間に合わない）。`start()` で 1 本読み、
///   `showRewardedForContinue()` で消費したら即座に次を読む。
@MainActor
protocol AdServing: AnyObject {
    /// リワード広告を今すぐ出せるか。false のときは復活オファー自体を出さない
    /// （押してから「広告がありません」を見せるのが最悪の体験）
    var isRewardedReady: Bool { get }

    /// 広告 UI を表示している間の通知。`GameCenterService.onPresentationChanged` と同じ用途に加えて、
    /// BGM の抑止にも使う（`.ambient` は他の音とミックスするので、止めないと広告の音声と重なる）
    var onPresentationChanged: ((Bool) -> Void)? { get set }

    /// 起動時に 1 回。ATT → SDK 初期化 → 事前読み込み。
    /// **Game Center の認証より先に呼ぶ**（ATT ダイアログとサインイン UI の競合回避）
    func start() async

    /// シーンが `.active` に戻ったときに呼ぶ。起動時に出せなかった ATT ダイアログの出し直し
    func didBecomeActive() async

    /// 終了後インタースティシャル。出すかどうかの判断は Core が決めた
    /// `outcome.shouldShowInterstitial` に従う（復活したプレイは免除される）
    func showInterstitialIfNeeded(_ outcome: GameOverOutcome) async

    /// 復活用のリワード広告を出す。**完走したときだけ true**
    func showRewardedForContinue() async -> Bool
}
