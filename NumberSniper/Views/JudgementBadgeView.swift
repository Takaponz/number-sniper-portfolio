import SwiftUI
import NumberSniperCore

/// 判定結果の演出。PERFECT を最も派手にする。
///
/// 本編（`RoundResult`）と練習モード（得点なし）の両方から使うため、
/// 判定・得点・時間切れを個別に受け取る形にしてある。本編の呼び出しは
/// `init(result:)` でそのまま通る。
struct JudgementBadgeView: View {
    let judgement: Judgement
    /// 得点表示。練習モードでは nil（スコアの概念が無い）
    let gainedPoints: Int?
    let isTimeUp: Bool

    init(judgement: Judgement, gainedPoints: Int? = nil, isTimeUp: Bool = false) {
        self.judgement = judgement
        self.gainedPoints = gainedPoints
        self.isTimeUp = isTimeUp
    }

    /// 本編用。既存の呼び出しを不変に保つ
    init(result: RoundResult) {
        self.init(
            judgement: result.judgement,
            gainedPoints: result.gainedPoints,
            isTimeUp: result.isTimeUp
        )
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: judgement == .perfect ? 46 : 34, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .shadow(color: color.opacity(judgement == .perfect ? 0.7 : 0), radius: 12)

            if let gainedPoints, gainedPoints > 0 {
                Text("+\(gainedPoints)")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(color.opacity(0.9))
            }
        }
        .transition(.scale(scale: 1.4).combined(with: .opacity))
    }

    private var label: String {
        isTimeUp ? AppStrings.timeUp : AppStrings.judgementLabel(judgement)
    }

    private var color: Color { Self.color(for: judgement) }

    /// 判定色。`PracticeView` のズレ表示でも同じ色を使う
    static func color(for judgement: Judgement) -> Color {
        switch judgement {
        case .perfect: .yellow
        case .great: .cyan
        case .good: .green
        case .miss: .red
        }
    }
}

#Preview {
    VStack(spacing: 32) {
        ForEach(Judgement.allCases, id: \.self) { judgement in
            JudgementBadgeView(
                result: RoundResult(
                    judgement: judgement,
                    deviation: 0,
                    gainedPoints: judgement.accuracyPoints,
                    didLevelUp: false,
                    isGameOver: false
                )
            )
        }
        JudgementBadgeView(
            result: RoundResult(
                judgement: .miss,
                deviation: 10_000,
                gainedPoints: 0,
                didLevelUp: false,
                isGameOver: false,
                isTimeUp: true
            )
        )
    }
}
