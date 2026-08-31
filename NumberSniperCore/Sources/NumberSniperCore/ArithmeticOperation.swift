import Foundation

/// 四則演算お題（`QuestionType.arithmetic`）で使う演算子。
public enum ArithmeticOperation: String, Sendable, CaseIterable, Equatable {
    case add
    case subtract
    case multiply
    case divide

    /// 画面に出す記号。
    ///
    /// - Important: ASCII の `*` `/` `-` は使わない。`/` は分数お題（`2/3`）と
    ///   衝突し、`*` は算数の見た目にならない。減算は U+2212 MINUS SIGN。
    public var symbol: String {
        switch self {
        case .add: "+"
        case .subtract: "−"
        case .multiply: "×"
        case .divide: "÷"
        }
    }
}
