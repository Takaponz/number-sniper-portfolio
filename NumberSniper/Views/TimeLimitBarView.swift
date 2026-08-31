import SwiftUI
import NumberSniperCore

/// 画面最上部に出す残り時間バー。左から減っていく。
///
/// カーソルと同じく `TimelineView(.animation)` で描画時刻から残量を引く。
/// ViewModel を毎フレーム更新しないので、`@Observable` の再評価を巻き込まない。
struct TimeLimitBarView: View {
    /// 描画時刻 → 残り時間比率（1 = 満タン、0 = 時間切れ）
    let remainingRatio: (TimeInterval) -> Double

    /// 残量がこれを下回ったら警告色にする。
    ///
    /// `GameConfig` には置かない。あちらは Core パッケージにあり、ゲームの判定・スコア・
    /// 速度を決める定数の置き場所で、**UI の配色しきい値を入れると Core が表示の関心事を
    /// 持ってしまう**。同じ理由で `NumberLineView` の寸法定数もビュー側にある。
    /// ここを変えても判定・スコアは 1 ミリも動かない
    private let cautionRatio = 0.5
    private let dangerRatio = 0.25

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geometry in
                let ratio = remainingRatio(context.date.timeIntervalSinceReferenceDate)

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.secondary.opacity(0.18))

                    Rectangle()
                        .fill(color(for: ratio))
                        .frame(width: geometry.size.width * ratio)
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    private func color(for ratio: Double) -> Color {
        if ratio <= dangerRatio { return .red }
        if ratio <= cautionRatio { return .orange }
        return .green
    }
}

#Preview {
    VStack(spacing: 24) {
        TimeLimitBarView(remainingRatio: { _ in 0.85 })
        TimeLimitBarView(remainingRatio: { _ in 0.40 })
        TimeLimitBarView(remainingRatio: { _ in 0.12 })
    }
    .padding(.vertical, 40)
}
