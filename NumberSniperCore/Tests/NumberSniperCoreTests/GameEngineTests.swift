import Testing
import Foundation
@testable import NumberSniperCore

@Suite("GameEngine")
struct GameEngineTests {
    /// テスト用: 指定した判定を必ず出す停止位置を作る
    private func stopRatio(for judgement: Judgement, target: Double) -> Double {
        let offset: Double
        switch judgement {
        case .perfect: offset = 0
        case .great: offset = 0.02
        case .good: offset = 0.05
        case .miss: offset = 0.30
        }
        // 目標が右寄りなら左にずらす（0〜1 をはみ出さないため）
        return target + (target > 0.5 ? -offset : offset)
    }

    private func makeEngine(seed: UInt64 = 1) -> GameEngine<SeededRandomNumberGenerator> {
        GameEngine(rng: SeededRandomNumberGenerator(seed: seed))
    }

    @Test("初期状態はライフ3・スコア0・コンボ0・Lv1・お題あり")
    func initialState() {
        let engine = makeEngine()
        #expect(engine.lives == GameConfig.initialLives)
        #expect(engine.score == 0)
        #expect(engine.combo == 0)
        #expect(engine.correctCount == 0)
        #expect(engine.level == 1)
        #expect(!engine.isGameOver)
        // 最初のお題は Lv1 の帯から出る（帯の型集合そのものは LevelCurveTests が固定）
        #expect(LevelCurve.standard.stage(for: 1).types.contains(engine.question.type))
    }

    @Test("Lv1・コンボ0 の PERFECT は 1000 点入る")
    func firstPerfectScores1000() {
        var engine = makeEngine()
        let result = engine.submit(stopRatio: engine.question.target)
        #expect(result.judgement == .perfect)
        #expect(result.deviation == 0)
        #expect(result.gainedPoints == 1000)
        #expect(engine.score == 1000)
        #expect(engine.combo == 2)
    }

    @Test("獲得点はコンボ更新前の値で計算される")
    func pointsUseComboBeforeUpdate() {
        var engine = makeEngine()
        // 1 問目 PERFECT: コンボ 0 → 1000 点、コンボは 2 になる
        _ = engine.submit(stopRatio: engine.question.target)
        #expect(engine.combo == 2)
        // 2 問目 PERFECT: コンボ 2（120%）・Lv1 → 1000 * 1 * 120 / 100 = 1200 点
        let second = engine.submit(stopRatio: engine.question.target)
        #expect(second.gainedPoints == 1200)
        #expect(engine.score == 2200)
        #expect(engine.combo == 4)
    }

    @Test("3 問正解でレベルが上がり、3 問目はまだ Lv1 で採点される")
    func levelsUpAfterThreeCorrect() {
        var engine = makeEngine()
        var results: [RoundResult] = []
        for _ in 0..<3 {
            results.append(engine.submit(stopRatio: engine.question.target))
        }
        // 3 問目までは Lv1 倍率（レベルアップは採点後）
        #expect(results[2].gainedPoints == 1000 * 1 * comboMultiplierPercent(combo: 4) / 100)
        #expect(results[2].didLevelUp)
        #expect(engine.level == 2)
        #expect(engine.correctCount == 3)
    }

    @Test("MISS でライフが減り、コンボが 0 に戻り、正解数は増えない")
    func missCostsALife() {
        var engine = makeEngine()
        _ = engine.submit(stopRatio: engine.question.target)  // PERFECT
        #expect(engine.combo == 2)

        let result = engine.submit(stopRatio: stopRatio(for: .miss, target: engine.question.target))
        #expect(result.judgement == .miss)
        #expect(result.gainedPoints == 0)
        #expect(engine.lives == GameConfig.initialLives - 1)
        #expect(engine.combo == 0)
        #expect(engine.correctCount == 1)
        #expect(!engine.isGameOver)
    }

    @Test("GOOD はコンボをリセットするがライフは減らない")
    func goodResetsComboWithoutLosingLife() {
        var engine = makeEngine()
        _ = engine.submit(stopRatio: engine.question.target)  // PERFECT → combo 2

        let result = engine.submit(stopRatio: stopRatio(for: .good, target: engine.question.target))
        #expect(result.judgement == .good)
        #expect(engine.lives == GameConfig.initialLives)
        #expect(engine.combo == 0)
        #expect(engine.correctCount == 2)
    }

    @Test("ライフ 0 でゲームオーバーになり、お題は更新されない")
    func gameOverAfterThreeMisses() {
        var engine = makeEngine()
        var lastResult: RoundResult?
        for _ in 0..<GameConfig.initialLives {
            let questionBefore = engine.question
            lastResult = engine.submit(stopRatio: stopRatio(for: .miss, target: questionBefore.target))
        }
        #expect(engine.lives == 0)
        #expect(engine.isGameOver)
        #expect(lastResult?.isGameOver == true)
    }

    @Test("スイープ時間は現在レベルのスケジュールに従う")
    func sweepDurationFollowsLevel() {
        var engine = makeEngine()
        #expect(engine.sweepDuration == SweepSchedule.duration(level: 1))
        for _ in 0..<3 { _ = engine.submit(stopRatio: engine.question.target) }
        #expect(engine.level == 2)
        #expect(engine.sweepDuration == SweepSchedule.duration(level: 2))
    }

    @Test("次のお題は新しいレベルのタイプで生成される")
    func nextQuestionUsesNewLevel() {
        var engine = makeEngine()
        for _ in 0..<3 { _ = engine.submit(stopRatio: engine.question.target) }
        #expect(engine.level == 2)
        #expect(engine.question.type == .fraction)
    }

    @Test("最高レベル到達後はレベルが上がらない")
    func stopsAtMaxLevel() {
        var engine = makeEngine()
        for _ in 0..<(GameConfig.correctAnswersPerLevel * (GameConfig.maxLevel - 1) + 10) {
            _ = engine.submit(stopRatio: engine.question.target)
        }
        #expect(engine.level == GameConfig.maxLevel)
        #expect(!engine.isGameOver)
    }

    @Test("同じ seed なら同じ進行になる")
    func isDeterministic() {
        func run(seed: UInt64) -> [String] {
            var engine = GameEngine(rng: SeededRandomNumberGenerator(seed: seed))
            var prompts: [String] = []
            for _ in 0..<15 {
                prompts.append(engine.question.promptText)
                _ = engine.submit(stopRatio: engine.question.target)
            }
            return prompts
        }
        #expect(run(seed: 99) == run(seed: 99))
    }

    // MARK: - 制限時間切れ

    @Test("時間切れは MISS 扱い。ライフが減りコンボが消え、点は入らない")
    func timeUpIsTreatedAsMiss() {
        var engine = makeEngine()
        // 先に 1 問 PERFECT でコンボを立てておく
        _ = engine.submit(stopRatio: engine.question.target)
        #expect(engine.combo == 2)
        let scoreBeforeTimeUp = engine.score

        let result = engine.timeUp()
        #expect(result.judgement == .miss)
        #expect(result.isTimeUp)
        #expect(result.gainedPoints == 0)
        #expect(engine.score == scoreBeforeTimeUp)
        #expect(engine.combo == 0)
        #expect(engine.lives == GameConfig.initialLives - 1)
    }

    @Test("時間切れは正解数に数えず、レベルも上げない")
    func timeUpDoesNotAdvanceLevel() {
        var engine = makeEngine()
        _ = engine.timeUp()
        #expect(engine.correctCount == 0)
        #expect(engine.level == 1)
    }

    @Test("時間切れでも次のお題に進む")
    func timeUpAdvancesQuestion() {
        var engine = makeEngine()
        let before = engine.question
        _ = engine.timeUp()
        #expect(engine.question != before)
    }

    @Test("目標が中央付近でも時間切れが正解に化けない")
    func timeUpNeverBecomesCorrectNearCenter() {
        // 時間切れの瞬間、カーソルは必ず数直線の中央（比率 0.5）にいる
        // （制限時間 2.5S ÷ 往復周期 2S → 位相 0.5S → 比率 0.5。SweepScheduleTests で固定）。
        // 位置から判定すると目標が 0.43〜0.57 のお題で GOOD 以上に化ける。
        // 中央ちょうどの目標なら PERFECT にすらなることを先に示しておく
        #expect(judge(deviation: deviation(stopRatio: 0.5, target: 0.5)) == .perfect)

        // 危険域のお題が出るまで PERFECT で進める。PERFECT はライフを減らさないので
        // 終了条件が「危険域が出ること」だけになる。**必ず上限付きで回す**
        // （お題タイプの構成を変えると危険域が出なくなり、無限ループになりうる）
        var engine = makeEngine(seed: 7)
        var didCheckDangerousTarget = false
        for _ in 0..<200 {
            if abs(engine.question.target - 0.5) <= 0.07 {
                let livesBefore = engine.lives
                let result = engine.timeUp()
                #expect(result.judgement == .miss)
                #expect(!result.judgement.isCorrect)
                #expect(engine.lives == livesBefore - 1)
                didCheckDangerousTarget = true
                break
            }
            _ = engine.submit(stopRatio: engine.question.target)
        }
        #expect(didCheckDangerousTarget, "危険域（目標 0.43〜0.57）のお題が 200 問以内に出なかった")
    }

    @Test("時間切れ 3 回でゲームオーバーになる")
    func threeTimeUpsEndTheGame() {
        var engine = makeEngine()
        _ = engine.timeUp()
        _ = engine.timeUp()
        let last = engine.timeUp()
        #expect(last.isGameOver)
        #expect(last.isTimeUp)
        #expect(engine.isGameOver)
        #expect(engine.lives == 0)
    }

    @Test("タップの MISS は isTimeUp が false のまま")
    func tappedMissIsNotFlaggedAsTimeUp() {
        var engine = makeEngine()
        let result = engine.submit(stopRatio: stopRatio(for: .miss, target: engine.question.target))
        #expect(result.judgement == .miss)
        #expect(!result.isTimeUp)
    }

    @Test("制限時間は現在レベルの往復周期")
    func roundTimeLimitFollowsLevel() {
        var engine = makeEngine()
        #expect(engine.roundTimeLimit == SweepSchedule.roundTimeLimit(level: 1))
        for _ in 0..<3 { _ = engine.submit(stopRatio: engine.question.target) }
        #expect(engine.level == 2)
        #expect(engine.roundTimeLimit == SweepSchedule.roundTimeLimit(level: 2))
    }

    // MARK: - カーブ

    @Test("エンジンは出荷カーブの速度・お題構成を使う")
    func usesStandardCurve() {
        let engine = GameEngine(rng: SeededRandomNumberGenerator(seed: 1))
        #expect(engine.sweepDuration == SweepSchedule.duration(level: 1, curve: .standard))
        #expect(engine.roundTimeLimit == SweepSchedule.roundTimeLimit(level: 1, curve: .standard))
        #expect(LevelCurve.standard.stage(for: 1).types.contains(engine.question.type))
    }

    @Test("注入したカーブの速度・制限時間・お題構成が使われる")
    func usesInjectedCurve() {
        // Lv1 の速さはカーブ非依存（初速は GameConfig）なので、出荷カーブとの比較だけでは
        // 「内部で .standard に固定する」回帰を弁別できない。出荷値と違うカーブを注入して、
        // 本数（4.5 ≠ 3.5）・型（decimalValue ≠ percent）・Lv2 の速度（r 0.9 ≠ 0.94）で見る
        let curve = LevelCurve(
            minSweepSeconds: 0.5,
            sweepDecayRate: 0.9,
            stages: [
                LevelStage(
                    levels: 1...GameConfig.maxLevel,
                    types: [.decimalValue],
                    parameters: QuestionParameters(),
                    roundTimeLimitSweeps: 4.5
                )
            ]
        )
        var engine = GameEngine(curve: curve, rng: SeededRandomNumberGenerator(seed: 1))
        #expect(engine.roundTimeLimit == SweepSchedule.roundTimeLimit(level: 1, curve: curve))
        #expect(engine.question.type == .decimalValue)

        for _ in 0..<GameConfig.correctAnswersPerLevel {
            engine.submit(stopRatio: engine.question.target)
        }
        #expect(engine.level == 2)
        #expect(engine.sweepDuration == SweepSchedule.duration(level: 2, curve: curve))
        #expect(engine.question.type == .decimalValue)
    }

    @Test("レベルが上がると速度も制限時間もそのレベルのものになる")
    func speedFollowsLevelUp() {
        var engine = GameEngine(rng: SeededRandomNumberGenerator(seed: 3))
        for _ in 0..<GameConfig.correctAnswersPerLevel {
            engine.submit(stopRatio: engine.question.target)
        }
        #expect(engine.level == 2)
        #expect(engine.sweepDuration == SweepSchedule.duration(level: 2, curve: .standard))
        #expect(engine.roundTimeLimit == SweepSchedule.roundTimeLimit(level: 2, curve: .standard))
    }

    // 時間切れ 3 回のゲームオーバーは threeTimeUpsEndTheGame（isTimeUp・lives まで
    // 検証する上位互換）が既にあるので、ここには置かない
}
