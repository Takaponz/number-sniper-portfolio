import Testing
import Foundation
@testable import NumberSniperCore

@Suite("カーソル速度スケジュール")
struct SweepScheduleTests {
    // 出荷カーブ（r=0.94 / min 1.35 / 本数 3.5→2.5）の数表・段差・判定窓・
    // チャンス回数の検証は LevelCurveTests に集約してある。ここはカーブに依らない
    // 引数の扱いだけを見る

    @Test("レベル 0 以下でも Lv1 として扱う")
    func clampsLowLevels() {
        #expect(SweepSchedule.duration(level: 0) == SweepSchedule.duration(level: 1))
        #expect(SweepSchedule.duration(level: -5) == SweepSchedule.duration(level: 1))
    }

    @Test("最高レベルを超えても最高レベルとして扱う")
    func clampsHighLevels() {
        let top = SweepSchedule.duration(level: GameConfig.maxLevel)
        #expect(SweepSchedule.duration(level: GameConfig.maxLevel + 1) == top)
        // 制限時間はステージ経由で引くので、範囲外レベルでも最高レベルの本数になる
        #expect(
            SweepSchedule.roundTimeLimit(level: GameConfig.maxLevel + 10)
                == SweepSchedule.roundTimeLimit(level: GameConfig.maxLevel)
        )
    }

    @Test("上限クランプは下限に張り付かないカーブでも効く")
    func clampsHighLevelsWithoutFloorClamp() {
        // 出荷カーブは Lv12 で下限 1.35 に張り付くため、指数計算を maxLevel の先まで
        // 続けても max(minSweepSeconds, raw) が同じ値を返し、クランプ漏れが隠れる。
        // 張り付かないカーブで「最高レベル超過 = 最高レベル」を弁別する
        let curve = LevelCurve(
            minSweepSeconds: 0.5,
            sweepDecayRate: 0.99,
            stages: [
                LevelStage(
                    levels: 1...GameConfig.maxLevel,
                    types: [.decimalValue],
                    parameters: QuestionParameters(),
                    roundTimeLimitSweeps: 2.5
                )
            ]
        )
        #expect(SweepSchedule.duration(level: GameConfig.maxLevel, curve: curve) > curve.minSweepSeconds)
        #expect(
            SweepSchedule.duration(level: GameConfig.maxLevel + 1, curve: curve)
                == SweepSchedule.duration(level: GameConfig.maxLevel, curve: curve)
        )
    }

    @Test("引数を省略すると出荷カーブが使われる")
    func defaultsToStandardCurve() {
        for level in 1...GameConfig.maxLevel {
            #expect(SweepSchedule.duration(level: level) == SweepSchedule.duration(level: level, curve: .standard))
            #expect(
                SweepSchedule.roundTimeLimit(level: level)
                    == SweepSchedule.roundTimeLimit(level: level, curve: .standard)
            )
        }
    }
}
