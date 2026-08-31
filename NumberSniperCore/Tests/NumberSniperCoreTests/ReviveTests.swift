import Testing
import Foundation
@testable import NumberSniperCore

@Suite("復活（リワード広告コンティニュー）")
struct ReviveTests {
    private func makeEngine(seed: UInt64 = 1) -> GameEngine<SeededRandomNumberGenerator> {
        GameEngine(rng: SeededRandomNumberGenerator(seed: seed))
    }

    /// 確実に MISS になる停止位置（`GameEngineTests` と同じ作り方）
    private func missRatio(target: Double) -> Double {
        target + (target > 0.5 ? -0.30 : 0.30)
    }

    /// ライフを 0 にして終わらせる。`correctFirst` の回数だけ先に PERFECT する
    private func playUntilGameOver(
        _ engine: inout GameEngine<SeededRandomNumberGenerator>,
        correctFirst: Int
    ) {
        for _ in 0..<correctFirst {
            engine.submit(stopRatio: engine.question.target)
        }
        while !engine.isGameOver {
            engine.submit(stopRatio: missRatio(target: engine.question.target))
        }
    }

    // MARK: - canRevive の遷移

    @Test("プレイ中は復活を提案しない")
    func cannotReviveWhileAlive() {
        var engine = makeEngine()
        #expect(!engine.canRevive)

        engine.submit(stopRatio: engine.question.target)
        #expect(!engine.canRevive, "生きている間は提案しない")
    }

    @Test("1 問以上正解してライフ 0 になったら提案する")
    func canReviveAfterGameOverWithCorrectAnswer() {
        var engine = makeEngine()
        playUntilGameOver(&engine, correctFirst: 1)
        #expect(engine.isGameOver)
        #expect(engine.correctCount == 1)
        #expect(engine.canRevive)
    }

    @Test("1 問も正解していないゲームオーバーでは提案しない")
    func cannotReviveWithoutAnyCorrectAnswer() {
        var engine = makeEngine()
        playUntilGameOver(&engine, correctFirst: 0)
        #expect(engine.isGameOver)
        #expect(engine.correctCount == 0)
        #expect(!engine.canRevive, "開幕 3 連続 MISS では失うものが無く、復活の動機が無い")
    }

    @Test("上限まで使ったら二度と提案しない")
    func cannotReviveBeyondLimit() {
        var engine = makeEngine()
        playUntilGameOver(&engine, correctFirst: 1)

        for _ in 0..<GameConfig.maxRevivesPerGame {
            #expect(engine.canRevive)
            engine.revive()
            while !engine.isGameOver {
                engine.submit(stopRatio: missRatio(target: engine.question.target))
            }
        }
        #expect(engine.reviveCount == GameConfig.maxRevivesPerGame)
        #expect(!engine.canRevive, "上限に達したら提案しない")
    }

    // MARK: - revive() の効果

    @Test("復活でライフが戻りゲームオーバーが取り消される")
    func reviveRestoresLife() {
        var engine = makeEngine()
        playUntilGameOver(&engine, correctFirst: 1)
        #expect(engine.lives == 0)

        engine.revive()
        #expect(engine.lives == GameConfig.livesOnRevive)
        #expect(!engine.isGameOver)
        #expect(engine.reviveCount == 1)
    }

    @Test("復活すると次のお題に進む（死んだ時のお題を再出題しない）")
    func reviveAdvancesQuestion() {
        var engine = makeEngine()
        playUntilGameOver(&engine, correctFirst: 1)
        let questionAtDeath = engine.question

        engine.revive()
        // 時間切れで死ぬと画面に目標マーカーが出たまま残るので、同じお題を再出題すると
        // 正解位置を見た状態で撃てて確実に PERFECT になる
        #expect(engine.question != questionAtDeath)
    }

    @Test("どの seed でも復活後のお題が死んだ時のお題と一致しない")
    func reviveNeverRepeatsTheQuestionAtDeath() {
        // 1 系列だけの検証では「引き直した結果がたまたま同じ」を検出できない。
        // 生成は乱数なので、お題空間の狭い低レベルでは数 % の確率で衝突する。
        // 衝突すると時間切れ死のときに正解位置を見た状態で撃てるので、多数の seed で固定する
        for seed in UInt64(1)...80 {
            var engine = makeEngine(seed: seed)
            playUntilGameOver(&engine, correctFirst: 1)
            let questionAtDeath = engine.question

            engine.revive()
            #expect(engine.question != questionAtDeath, "seed \(seed) で死んだ時と同じお題が出た")
        }
    }

    @Test("時間切れで死んだ場合も復活後のお題が変わる")
    func reviveAfterTimeUpNeverRepeatsTheQuestion() {
        // 時間切れは目標マーカーが画面に残ったまま死ぬ経路なので、ここの衝突が一番効く
        for seed in UInt64(1)...80 {
            var engine = makeEngine(seed: seed)
            engine.submit(stopRatio: engine.question.target)
            while !engine.isGameOver {
                engine.timeUp()
            }
            let questionAtDeath = engine.question

            engine.revive()
            #expect(engine.question != questionAtDeath, "seed \(seed) で死んだ時と同じお題が出た")
        }
    }

    @Test("復活してもスコア・レベル・正解数は継続する")
    func reviveKeepsProgress() {
        var engine = makeEngine()
        // レベルが上がるところまで進めてから死なせる
        playUntilGameOver(&engine, correctFirst: GameConfig.correctAnswersPerLevel)
        let score = engine.score
        let level = engine.level
        let correctCount = engine.correctCount
        #expect(level > 1, "レベルが上がった状態で検証する")

        engine.revive()
        #expect(engine.score == score)
        #expect(engine.level == level)
        #expect(engine.correctCount == correctCount)
        // コンボは死因の MISS で既に 0 になっている（revive では触らない）
        #expect(engine.combo == 0)
    }

    @Test("復活後は通常どおり submit できる")
    func canSubmitAfterRevive() {
        var engine = makeEngine()
        playUntilGameOver(&engine, correctFirst: 1)
        let scoreBefore = engine.score

        engine.revive()
        let result = engine.submit(stopRatio: engine.question.target)
        #expect(result.judgement == .perfect)
        #expect(engine.score > scoreBefore)
        #expect(engine.correctCount == 2)
    }

    @Test("復活後にライフを使い切ったら二度目は提案されない")
    func secondGameOverAfterReviveOffersNothing() {
        var engine = makeEngine()
        playUntilGameOver(&engine, correctFirst: 1)
        engine.revive()

        while !engine.isGameOver {
            engine.submit(stopRatio: missRatio(target: engine.question.target))
        }
        #expect(engine.isGameOver)
        #expect(engine.correctCount > 0, "正解数の条件は満たしたまま")
        #expect(!engine.canRevive, "落ちる理由は回数上限だけであること")
    }

    @Test("復活したライフ 1 は 1 回の MISS で尽きる")
    func revivedLifeIsSpentByOneMiss() {
        var engine = makeEngine()
        playUntilGameOver(&engine, correctFirst: 1)
        engine.revive()
        #expect(engine.lives == 1)

        let result = engine.submit(stopRatio: missRatio(target: engine.question.target))
        #expect(result.isGameOver)
        #expect(engine.lives == 0)
    }

    @Test("時間切れで死んだあとも復活できる")
    func canReviveAfterTimeUp() {
        var engine = makeEngine()
        engine.submit(stopRatio: engine.question.target)   // 1 問正解しておく
        while !engine.isGameOver {
            engine.timeUp()
        }
        #expect(engine.canRevive)

        engine.revive()
        #expect(!engine.isGameOver)
        #expect(engine.lives == GameConfig.livesOnRevive)
    }

    // MARK: - 決定性

    @Test("同じ seed なら復活後のお題列も再現する")
    func reviveIsDeterministic() {
        func run(seed: UInt64) -> [String] {
            var engine = GameEngine(rng: SeededRandomNumberGenerator(seed: seed))
            playUntilGameOver(&engine, correctFirst: 1)
            engine.revive()

            var prompts: [String] = [engine.question.promptText]
            for _ in 0..<5 {
                engine.submit(stopRatio: engine.question.target)
                prompts.append(engine.question.promptText)
            }
            return prompts
        }
        #expect(run(seed: 42) == run(seed: 42))
    }
}
