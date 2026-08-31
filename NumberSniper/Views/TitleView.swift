import SwiftUI

struct TitleView: View {
    let highScore: Int
    let onStart: () -> Void
    let onShowRanking: (() -> Void)?
    let onShowSettings: () -> Void

    var body: some View {
        // 見た目の正本は `SettingsGearOverlay.swift`。リザルトと同じものを呼ぶ
        content.settingsGearOverlay(action: onShowSettings)
    }

    private var content: some View {
        VStack(spacing: 32) {
            Spacer()

            Text(AppStrings.displayName)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)

            VStack(spacing: 4) {
                Text(AppStrings.best)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(highScore)")
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: highScore)
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: onStart) {
                    Text(AppStrings.start)
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)

                if let onShowRanking {
                    Button(AppStrings.ranking, action: onShowRanking)
                        .font(.body.weight(.semibold))
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 48)
        }
    }
}

#Preview {
    TitleView(highScore: 12_800, onStart: {}, onShowRanking: {}, onShowSettings: {})
}
