import Foundation
import Testing
@testable import NumberSniperCore

@Suite("練習モードの判定結果")
struct PracticeResultTests {
    private func makeSession(
        level: Int = 6,
        seed: UInt64 = 0x0FF5_2026
    ) -> PracticeSession<SeededRandomNumberGenerator> {
        PracticeSession(level: level, rng: SeededRandomNumberGenerator(seed: seed))
    }

    @Test("目標より左で止めたら .left")
    func directionLeft() {
        var session = makeSession()
        let result = session.submit(stopRatio: session.question.target - 0.02)
        #expect(result.direction == .left)
        #expect(result.signedDeviation < 0)
    }

    @Test("目標より右で止めたら .right")
    func directionRight() {
        var session = makeSession()
        let result = session.submit(stopRatio: session.question.target + 0.02)
        #expect(result.direction == .right)
        #expect(result.signedDeviation > 0)
    }

    @Test("ぴったりなら .exact")
    func directionExact() {
        var session = makeSession()
        let result = session.submit(stopRatio: session.question.target)
        #expect(result.direction == .exact)
        #expect(result.signedDeviation == 0)
        #expect(result.offset.scaled == 0)
        #expect(result.offsetPercent == 0)
        #expect(result.judgement == .perfect)
    }

    @Test("副表示の % は整数除算の切り捨て")
    func offsetPercentTruncates() {
        // d = 99 → 0、d = 100 → 1、d = 650 → 6
        for (delta, expected) in [(0.0099, 0), (0.01, 1), (0.065, 6)] {
            var session = makeSession()
            let target = session.question.target
            let result = session.submit(stopRatio: target + delta)
            #expect(result.offsetPercent == expected)
        }
    }

    @Test("副表示の % に符号は漏れない")
    func offsetPercentIsUnsigned() {
        var session = makeSession()
        let result = session.submit(stopRatio: session.question.target - 0.065)
        #expect(result.direction == .left)
        #expect(result.offsetPercent == 6)
        #expect(result.offset.scaled >= 0)
        #expect(!result.offset.magnitudeText.hasPrefix("-"))
    }

    @Test("解いた問数は初回 submit でだけ増える")
    func solvedCountIncrementsOnce() {
        var session = makeSession()
        #expect(session.solvedCount == 0)
        session.submit(stopRatio: 0.5)
        #expect(session.solvedCount == 1)
        session.submit(stopRatio: 0.5)      // 冪等な再 submit
        session.submit(stopRatio: 0.9)
        #expect(session.solvedCount == 1)
        session.advance()
        session.submit(stopRatio: 0.5)
        #expect(session.solvedCount == 2)
    }

    @Test("advance で lastResult が消える")
    func lastResultClearsOnAdvance() {
        var session = makeSession()
        session.submit(stopRatio: 0.5)
        #expect(session.lastResult != nil)
        session.advance()
        #expect(session.lastResult == nil)
    }

    @Test("ズレの実数値はレンジ上の値として出る")
    func offsetIsMeasuredInRangeUnits() {
        // `question.range.offsetValue(...)` と突き合わせると submit の式の再評価になり、
        // 丸め・桁数・レンジ幅換算のどのバグも検出できない（恒真）。seed を固定して
        // 実測値をリテラルで置く
        var session = makeSession(level: 11, seed: 0x0FF5_2026)   // 3 桁レンジ帯
        let question = session.question
        #expect(question.range == .integers(lower: 204, upper: 572))   // W = 368 → n = 0
        let result = session.submit(stopRatio: question.target + 0.1)  // d = 1000
        // (1000 · 368 · 10^0 + 5000) / 10000 = 37
        #expect(result.signedDeviation == 1_000)
        #expect(result.offset == LineValue(scaled: 37, decimals: 0))
        #expect(result.offset.magnitudeText == "37")
    }

    @Test("判定は本編と同じしきい値で切り替わる")
    func judgementThresholds() {
        let cases: [(Double, Judgement)] = [
            (0.005, .perfect),   // d = 50
            (0.02, .great),      // d = 200
            (0.05, .good),       // d = 500
            (0.5, .miss),        // d = 5000
        ]
        for (delta, expected) in cases {
            var session = makeSession()
            let result = session.submit(stopRatio: session.question.target + delta)
            #expect(result.judgement == expected)
        }
    }
}
