import Foundation

public struct IrrationalConstant: Sendable, Equatable {
    public let text: String
    public let value: Double

    public init(text: String, value: Double) {
        self.text = text
        self.value = value
    }
}

/// Lv11 の無理数お題テーブル。
/// 値が 0.05〜0.95 に収まる定数だけを載せている（`QuestionModelTests` で固定）。
public enum IrrationalConstants {
    public static let all: [IrrationalConstant] = [
        IrrationalConstant(text: "√2/2", value: 2.0.squareRoot() / 2),        // ≈ 0.707
        IrrationalConstant(text: "√3/2", value: 3.0.squareRoot() / 2),        // ≈ 0.866
        IrrationalConstant(text: "√2−1", value: 2.0.squareRoot() - 1),        // ≈ 0.414
        IrrationalConstant(text: "√3−1", value: 3.0.squareRoot() - 1),        // ≈ 0.732
        IrrationalConstant(text: "√5−2", value: 5.0.squareRoot() - 2),        // ≈ 0.236
        IrrationalConstant(text: "(√5−1)/2", value: (5.0.squareRoot() - 1) / 2), // ≈ 0.618
        IrrationalConstant(text: "π/4", value: Double.pi / 4),                // ≈ 0.785
        IrrationalConstant(text: "π/6", value: Double.pi / 6),                // ≈ 0.524
        IrrationalConstant(text: "1/π", value: 1 / Double.pi),                // ≈ 0.318
        IrrationalConstant(text: "1/e", value: 1 / exp(1.0)),                 // ≈ 0.368
        IrrationalConstant(text: "e/4", value: exp(1.0) / 4),                 // ≈ 0.680
        IrrationalConstant(text: "ln2", value: log(2.0)),                     // ≈ 0.693
    ]
}
