import Foundation

/// カーソル位置を時刻から決定論的に計算する三角波。
///
/// 位置は原点時刻からの経過時間だけで決まるので、フレームレートや描画の
/// タイミングに依存しない。タップ時刻を渡せば、描画とは独立に停止位置を再現できる。
public struct CursorClock: Sendable, Equatable {
    /// この時刻でカーソルは左端（比率 0）にいる。
    public private(set) var originTime: TimeInterval

    public init(originTime: TimeInterval) {
        self.originTime = originTime
    }

    /// 一時停止からの復帰時に呼ぶ。カーソルは左端から再スタートする。
    ///
    /// 復帰直後の理不尽な MISS を構造的に排除するための処理。位相を保存せず
    /// 必ず左端に戻すことで、「バックグラウンドから戻ったらカーソルが目標の
    /// 真横にいて即 MISS」という状況が起きなくなる。
    public mutating func resetOrigin(to time: TimeInterval) {
        originTime = time
    }

    /// 指定時刻のカーソル位置比率（0 = 左端、1 = 右端）。
    public func ratio(at time: TimeInterval, sweepDuration: TimeInterval) -> Double {
        Self.ratio(elapsed: time - originTime, sweepDuration: sweepDuration)
    }

    /// 経過時間からカーソル位置比率を求める三角波。往復周期は 2 × sweepDuration。
    public static func ratio(elapsed: TimeInterval, sweepDuration: TimeInterval) -> Double {
        guard sweepDuration > 0 else { return 0 }
        let period = 2 * sweepDuration
        var phase = elapsed.truncatingRemainder(dividingBy: period)
        if phase < 0 { phase += period }
        return phase <= sweepDuration
            ? phase / sweepDuration
            : (period - phase) / sweepDuration
    }
}
