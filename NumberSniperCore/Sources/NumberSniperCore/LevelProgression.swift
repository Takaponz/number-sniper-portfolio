import Foundation

/// 正解数からレベルを決める。
public enum LevelProgression {
    /// 3 問正解ごとに 1 レベル上がる。Lv n 到達は 3×(n−1) 問正解後。
    /// `GameConfig.maxLevel` が上限で、以降は「スコアレース」フェーズになる。
    public static func level(correctCount: Int) -> Int {
        let raw = 1 + max(0, correctCount) / GameConfig.correctAnswersPerLevel
        return min(GameConfig.maxLevel, raw)
    }
}
