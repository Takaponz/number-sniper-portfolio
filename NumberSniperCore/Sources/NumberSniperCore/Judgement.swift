import Foundation

/// 1 回のタップの判定結果。
public enum Judgement: String, Sendable, CaseIterable {
    case perfect
    case great
    case good
    case miss

    /// 「正解」とは MISS 以外（PERFECT / GREAT / GOOD）を指す。
    /// レベルアップの進捗カウントはこの定義に従う。
    public var isCorrect: Bool { self != .miss }

    /// 判定別の精度点（固定値）。
    public var accuracyPoints: Int {
        switch self {
        case .perfect: GameConfig.perfectPoints
        case .great: GameConfig.greatPoints
        case .good: GameConfig.goodPoints
        case .miss: 0
        }
    }
}

/// ズレ d を上から順に評価し、最初にマッチした判定を返す（カスケード評価）。
public func judge(deviation d: Int) -> Judgement {
    if d <= GameConfig.perfectThreshold { return .perfect }
    if d <= GameConfig.greatThreshold { return .great }
    if d <= GameConfig.goodThreshold { return .good }
    return .miss
}
