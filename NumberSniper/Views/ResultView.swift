import SwiftUI
import NumberSniperCore

struct ResultView: View {
    let score: Int
    let highScore: Int
    let isNewBest: Bool
    let onRetry: () -> Void
    let onBackToTitle: () -> Void
    let onShowRanking: (() -> Void)?
    /// 練習モードへの導線。**ゲームオーバーの文脈があるここにだけ置く**
    /// （恒常メニューに置くと、目盛りのない目測という背骨を削る）
    let onStartPractice: () -> Void
    let onShowSettings: () -> Void

    var body: some View {
        // 見た目の正本は `SettingsGearOverlay.swift`。タイトルと同じものを呼ぶ
        content.settingsGearOverlay(action: onShowSettings)
    }

    private var content: some View {
        VStack(spacing: 28) {
            Spacer()

            Text(AppStrings.gameOver)
                .font(.title3.weight(.bold))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(AppStrings.score)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(score)")
                    .font(.system(size: 56, weight: .heavy, design: .rounded).monospacedDigit())

                if isNewBest {
                    Text(AppStrings.newBest)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.yellow)
                } else {
                    Text("\(AppStrings.best) \(highScore)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: onRetry) {
                    Text(AppStrings.retry)
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onStartPractice) {
                    Text(AppStrings.practice)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)

                ShareLink(item: AppStrings.shareMessage(score: score)) {
                    Text(AppStrings.share)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)

                if let onShowRanking {
                    Button(AppStrings.ranking, action: onShowRanking)
                        .font(.body.weight(.semibold))
                }

                // タイトルへ戻る導線。シェアと同じ枠線ボタンに揃えて、
                // ボタンとして認識できる見た目にする
                Button(action: onBackToTitle) {
                    Text(AppStrings.backToTitle)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 48)
        }
    }
}

#Preview {
    ResultView(
        score: 15_400,
        highScore: 12_800,
        isNewBest: true,
        onRetry: {},
        onBackToTitle: {},
        onShowRanking: {},
        onStartPractice: {},
        onShowSettings: {}
    )
}
