import SwiftUI

/// ライフ 0 のあとに出す復活オファー。`CountdownOverlayView` と同じ構造で、
/// 秒読みの間だけプレイ画面に重ねる。
///
/// - Note: タップ競合は `PlayView` 側で解決済み。数直線のジェスチャは
///   `including: phase == .playing ? .all : .none` で切れているので、ボタンが食われない。
struct ContinueOfferOverlayView: View {
    let remaining: Int
    /// ここまでのスコア。「失うもの」を見せないと復活の動機が伝わらない
    let score: Int
    /// 広告を出している最中は true。押しっぱなしの二重タップを見た目でも塞ぐ
    /// （実際の防止は `GameViewModel.acceptContinue()` のガード）
    let isPresentingAd: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.55))
                .ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text(AppStrings.continueTitle)
                        .font(.title2.weight(.bold))
                    Text("\(AppStrings.score) \(score)")
                        .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                }

                VStack(spacing: 10) {
                    Button(action: onAccept) {
                        Text(AppStrings.continueWatchAd)
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)

                    Text(AppStrings.continueCountdown(remaining: remaining))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(countsDown: true))

                    Button(action: onDecline) {
                        Text(AppStrings.continueDecline)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .disabled(isPresentingAd)
            .foregroundStyle(.white)
            .padding(.horizontal, 40)
        }
        .animation(.snappy, value: remaining)
    }
}

#Preview {
    ContinueOfferOverlayView(
        remaining: 8,
        score: 12_800,
        isPresentingAd: false,
        onAccept: {},
        onDecline: {}
    )
}
