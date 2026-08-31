import SwiftUI

struct CountdownOverlayView: View {
    let remaining: Int

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.55))
                .ignoresSafeArea()

            VStack(spacing: 8) {
                Text("\(remaining)")
                    .font(.system(size: 96, weight: .heavy, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                Text("\(remaining)\(AppStrings.resumeCountdownSuffix)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
        }
        .animation(.snappy, value: remaining)
    }
}

#Preview {
    CountdownOverlayView(remaining: 3)
}
