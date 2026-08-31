import Foundation
import Testing
@testable import NumberSniperCore

@Suite("練習セッションの進行")
struct PracticeSessionTests {
    private func makeSession(
        level: Int,
        seed: UInt64 = 0x5EED_2026
    ) -> PracticeSession<SeededRandomNumberGenerator> {
        PracticeSession(level: level, rng: SeededRandomNumberGenerator(seed: seed))
    }

    @Test("初期値は 0 問・未判定")
    func initialState() {
        let session = makeSession(level: 6)
        #expect(session.solvedCount == 0)
        #expect(session.roundIndex == 0)
        #expect(session.lastResult == nil)
        #expect(session.level == 6)
    }

    @Test("何問解いてもレベルは進まない")
    func levelNeverAdvances() {
        var session = makeSession(level: 6)
        for _ in 0..<20 {
            session.submit(stopRatio: session.question.target)
            session.advance()
            #expect(session.level == 6)
        }
        #expect(session.solvedCount == 20)
        #expect(session.roundIndex == 20)
    }

    @Test("submit はお題を進めない（advance が進める）")
    func submitDoesNotAdvanceQuestion() {
        var session = makeSession(level: 9)
        let question = session.question
        session.submit(stopRatio: 0.5)
        #expect(session.question == question)
        session.advance()
        #expect(session.lastResult == nil)
    }

    @Test("判定は本編と同じ judge(deviation:) を通る")
    func judgementMatchesMainLine() {
        for stopRatio in [0.0, 0.13, 0.4, 0.5, 0.77, 1.0] {
            var session = makeSession(level: 7)
            let target = session.question.target
            let result = session.submit(stopRatio: stopRatio)
            #expect(result.judgement == judge(deviation: deviation(stopRatio: stopRatio, target: target)))
            #expect(result.signedDeviation == signedDeviation(stopRatio: stopRatio, target: target))
        }
    }

    @Test("カーソル速度は本編と同じ関数から引く")
    func sweepDurationMatchesMainLine() {
        // Lv6 は下限 1.35 に張り付かない帯（Lv12 で見ると誤った実装でも一致してしまう）
        #expect(makeSession(level: 6).sweepDuration == SweepSchedule.duration(level: 6))
        #expect(makeSession(level: 6).sweepDuration > LevelCurve.standard.minSweepSeconds)
        #expect(makeSession(level: 2).sweepDuration == SweepSchedule.duration(level: 2))
        #expect(makeSession(level: 11).sweepDuration == SweepSchedule.duration(level: 11))
    }

    @Test("判定表示中の submit は状態を変えず同じ結果を返す")
    func submitIsIdempotentWhileShowingResult() {
        var session = makeSession(level: 6)
        let question = session.question
        let first = session.submit(stopRatio: question.target)
        let second = session.submit(stopRatio: 0.0)   // 大きく外した値でも通らない
        #expect(second == first)
        #expect(session.solvedCount == 1)
        #expect(session.roundIndex == 0)
        #expect(session.question == question)
        #expect(session.lastResult == first)
    }

    @Test("未判定の advance は no-op")
    func advanceIsNoOpBeforeJudgement() {
        var session = makeSession(level: 6)
        let question = session.question
        session.advance()
        #expect(session.question == question)
        #expect(session.roundIndex == 0)
        #expect(session.solvedCount == 0)
        #expect(session.lastResult == nil)
    }

    @Test("レベルは 1〜maxLevel にクランプされる")
    func levelIsClamped() {
        #expect(makeSession(level: 0).level == 1)
        #expect(makeSession(level: -5).level == 1)
        #expect(makeSession(level: 99).level == GameConfig.maxLevel)
        #expect(makeSession(level: 99).sweepDuration
            == SweepSchedule.duration(level: GameConfig.maxLevel))
    }

    @Test("お題列は本編の生成器を同じ順で回した結果と一致する")
    func questionSequenceMatchesGeneratorDirectly() {
        // セッション同士の比較だけだと、両方が同じ誤った状態遷移をしても一致してしまう。
        // 生成器を独立に回した期待列と突き合わせて、「どのレベルで」「1 advance につき何問」
        // 生成しているかまで固定する
        var session = makeSession(level: 7, seed: 0xA11CE)
        var rng = SeededRandomNumberGenerator(seed: 0xA11CE)
        let generator = QuestionGenerator()
        for _ in 0..<10 {
            #expect(session.question == generator.make(level: 7, curve: .standard, using: &rng))
            session.submit(stopRatio: 0.5)
            session.advance()
        }
    }

    @Test("seed が同じなら同じお題列が再現する")
    func seededQuestionsAreReproducible() {
        var a = makeSession(level: 10, seed: 42)
        var b = makeSession(level: 10, seed: 42)
        var c = makeSession(level: 10, seed: 43)
        var differsFromOtherSeed = false
        for _ in 0..<10 {
            #expect(a.question == b.question)
            if a.question != c.question { differsFromOtherSeed = true }
            a.submit(stopRatio: 0.5); a.advance()
            b.submit(stopRatio: 0.5); b.advance()
            c.submit(stopRatio: 0.5); c.advance()
        }
        // seed が違えばどこかで列が分岐する（同一列を返す実装なら落ちる）
        #expect(differsFromOtherSeed)
    }

    @Test("練習のお題は本編と同じ生成器から出る（レベル帯の構成に従う）")
    func questionsFollowLevelStage() {
        var session = makeSession(level: 2)
        let types = LevelCurve.standard.stage(for: 2).types
        for _ in 0..<30 {
            #expect(types.contains(session.question.type))
            session.submit(stopRatio: 0.5)
            session.advance()
        }
    }

    @Test("advance のたびにお題切り替えの目印が進む")
    func roundIndexAdvances() {
        var session = makeSession(level: 6)
        session.submit(stopRatio: 0.5)
        session.advance()
        #expect(session.roundIndex == 1)
        session.advance()          // 未判定なので no-op
        #expect(session.roundIndex == 1)
        session.submit(stopRatio: 0.5)
        session.advance()
        #expect(session.roundIndex == 2)
    }
}
