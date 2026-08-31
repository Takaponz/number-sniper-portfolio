import Foundation

/// 数直線の両端が表す値。目盛りは描かず、端の値だけを表示する。
public enum LineRange: Sendable, Equatable, Hashable {
    /// 0 〜 1
    case unit
    /// 整数 a 〜 b の変則レンジ
    case integers(lower: Int, upper: Int)

    public var lowerLabel: String {
        switch self {
        case .unit: "0"
        case .integers(let lower, _): "\(lower)"
        }
    }

    public var upperLabel: String {
        switch self {
        case .unit: "1"
        case .integers(_, let upper): "\(upper)"
        }
    }

    /// 整数の絶対値をお題にしてよいレンジか。
    public var allowsIntegerPrompts: Bool {
        if case .integers = self { return true }
        return false
    }

    /// 既定の 0〜1 レンジか。
    ///
    /// false のとき（変則レンジ）は、プレイヤーが 0〜1 や 0〜100 だと思い込んだまま
    /// 狙ってしまわないよう、**画面上でレンジを明示する必要がある**。
    public var isUnit: Bool {
        if case .unit = self { return true }
        return false
    }
}

/// お題の表示形式。
public enum QuestionType: String, Sendable, CaseIterable {
    /// 小数（0.62）
    case decimalValue
    /// 分数（2/3）
    case fraction
    /// パーセント（37%）
    case percent
    /// 変則レンジ上の整数（13〜63 で「50」）
    case customRange
    /// 無理数（√2/2）
    case irrational
    /// 四則演算の式（0〜100 で「3 × 20」）
    case arithmetic
    /// 分数の和（1/3 + 1/4）
    case fractionSum
    /// 変則レンジ上の小数（13〜63 で「41.5」）
    case customRangeDecimal
    /// 平方根（√0.49）
    case squareRoot

    /// このタイプが 0〜1 レンジを要求するか。
    /// お題タイプとレンジは必ずペアで生成するための制約。
    public var requiredRangeIsUnit: Bool {
        switch self {
        case .customRange, .arithmetic, .customRangeDecimal: false
        case .decimalValue, .fraction, .percent, .irrational, .fractionSum, .squareRoot: true
        }
    }
}

/// 1 問のお題。内部的には常に目標比率 `target` ∈ [0, 1] で保持し、
/// 表示形式だけがタイプごとに変わる。
public struct Question: Sendable, Equatable {
    public let type: QuestionType
    /// 画面に出す文字列（"0.62" / "2/3" / "37%" / "50" / "√2/2"）
    public let promptText: String
    public let range: LineRange
    /// 数直線の左端 = 0、右端 = 1 としたときの目標位置
    public let target: Double

    public init(type: QuestionType, promptText: String, range: LineRange, target: Double) {
        self.type = type
        self.promptText = promptText
        self.range = range
        self.target = target
    }
}
