import Foundation
import NumberSniperCore

/// 広告を出さない `AdServing` 実装。**待つだけで何も表示しない。**
///
/// Public portfolio buildの既定実装であり、ネットワークへ広告要求を送らない。
/// **オファー表示・秒読み・復活後のプレイ継続・スコア継続・免除ロジック**を
/// 広告なしでシミュレータ検証できる。
///
/// - Note: 待ち時間は「広告が出ている間 UI がどう見えるか」を確かめるためのダミーで、
///   ゲームのチューニング定数ではない（`GameConfig` には置かない）。
@MainActor
final class StubAdService: AdServing {
    /// 未ロック状態の確認用スイッチ。false にすると復活オファーが出なくなることを確かめられる
    /// （シミュレータ確認 8）
    var isRewardedReady = true

    var onPresentationChanged: ((Bool) -> Void)?

    /// リワードの疑似尺。実物は 15〜30 秒だが、手動確認で毎回待つには長すぎる
    private static let rewardedDuration: Duration = .seconds(3)
    /// インタースティシャルの疑似尺。「次の画面の読み込み」に見える程度の間
    private static let interstitialDuration: Duration = .seconds(1)

    func start() async {}

    func didBecomeActive() async {}

    func showInterstitialIfNeeded(_ outcome: GameOverOutcome) async {
        guard outcome.shouldShowInterstitial else { return }
        await present(for: Self.interstitialDuration)
    }

    func showRewardedForContinue() async -> Bool {
        // 実 SDK でも「出せない広告は完走できない」ので false を返す形に揃える
        guard isRewardedReady else { return false }
        await present(for: Self.rewardedDuration)
        return true
    }

    /// 表示中フラグの上げ下げをここ 1 箇所に閉じる。
    /// **下げは `defer` で行う** — 途中で return する経路が増えても立ちっぱなしにならない
    /// （立ちっぱなしになると BGM が戻らず、復帰カウントダウンも二度と出なくなる）
    private func present(for duration: Duration) async {
        onPresentationChanged?(true)
        defer { onPresentationChanged?(false) }
        try? await Task.sleep(for: duration)
    }
}
