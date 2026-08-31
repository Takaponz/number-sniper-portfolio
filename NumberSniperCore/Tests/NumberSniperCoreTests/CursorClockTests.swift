import Testing
import Foundation
@testable import NumberSniperCore

@Suite("カーソルの三角波")
struct CursorClockTests {
    @Test("原点で左端、片道時間で右端、往復周期で左端に戻る")
    func triangleWaveKeyPoints() {
        let s: TimeInterval = 2.0
        #expect(CursorClock.ratio(elapsed: 0, sweepDuration: s) == 0)
        #expect(abs(CursorClock.ratio(elapsed: 1.0, sweepDuration: s) - 0.5) < 1e-12)
        #expect(abs(CursorClock.ratio(elapsed: 2.0, sweepDuration: s) - 1.0) < 1e-12)
        #expect(abs(CursorClock.ratio(elapsed: 3.0, sweepDuration: s) - 0.5) < 1e-12)
        #expect(abs(CursorClock.ratio(elapsed: 4.0, sweepDuration: s)) < 1e-12)
    }

    @Test("常に 0〜1 に収まる")
    func staysInsideUnitInterval() {
        let s: TimeInterval = 1.7
        for step in 0..<2000 {
            let ratio = CursorClock.ratio(elapsed: Double(step) * 0.013, sweepDuration: s)
            #expect(ratio >= 0)
            #expect(ratio <= 1)
        }
    }

    @Test("周期性がある（往復周期ぶんずらしても同じ位置）")
    func isPeriodic() {
        let s: TimeInterval = 1.9
        for step in 0..<200 {
            let t = Double(step) * 0.037
            let a = CursorClock.ratio(elapsed: t, sweepDuration: s)
            let b = CursorClock.ratio(elapsed: t + 2 * s, sweepDuration: s)
            #expect(abs(a - b) < 1e-9)
        }
    }

    @Test("負の経過時間でも 0〜1 に収まる")
    func handlesNegativeElapsed() {
        let ratio = CursorClock.ratio(elapsed: -0.5, sweepDuration: 2.0)
        #expect(ratio >= 0 && ratio <= 1)
        #expect(abs(ratio - 0.25) < 1e-12)
    }

    @Test("スイープ時間が 0 以下なら 0 を返す（ゼロ除算を作らない）")
    func guardsAgainstZeroDuration() {
        #expect(CursorClock.ratio(elapsed: 1.0, sweepDuration: 0) == 0)
        #expect(CursorClock.ratio(elapsed: 1.0, sweepDuration: -1) == 0)
    }

    @Test("原点時刻を基準に位置を返す")
    func usesOriginTime() {
        let clock = CursorClock(originTime: 100.0)
        #expect(clock.ratio(at: 100.0, sweepDuration: 2.0) == 0)
        #expect(abs(clock.ratio(at: 102.0, sweepDuration: 2.0) - 1.0) < 1e-12)
    }

    @Test("復帰時に原点を再設定すると、カーソルは左端から再スタートする")
    func resumeRestartsFromLeftEdge() {
        var clock = CursorClock(originTime: 0)
        // 中途半端な位置で一時停止したとする
        #expect(abs(clock.ratio(at: 1.3, sweepDuration: 2.0) - 0.65) < 1e-12)

        // 復帰時刻 57.4 で原点を再設定する
        clock.resetOrigin(to: 57.4)
        #expect(clock.originTime == 57.4)
        #expect(clock.ratio(at: 57.4, sweepDuration: 2.0) == 0)
        #expect(abs(clock.ratio(at: 58.4, sweepDuration: 2.0) - 0.5) < 1e-12)
    }
}
