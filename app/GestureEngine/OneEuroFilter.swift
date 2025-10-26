import Foundation
import simd

struct OneEuroFilter {
    var minCutoff: Double = 1.2
    var beta: Double = 0.007
    var dCutoff: Double = 1.0

    private var xPrev: SIMD2<Double>?
    private var dxPrev: SIMD2<Double>?
    private var tPrev: Double?

    mutating func reset() {
        xPrev = nil
        dxPrev = nil
        tPrev = nil
    }

    mutating func filter(_ point: SIMD2<Double>, timestamp: Double) -> SIMD2<Double> {
        guard let tPrev, let xPrev, let dxPrev else {
            self.tPrev = timestamp
            self.xPrev = point
            self.dxPrev = .zero
            return point
        }

        let dt = max(1e-3, timestamp - tPrev)
        let dx = (point - xPrev) / dt
        let edx = lowpass(previous: dxPrev, current: dx, alpha: alpha(cutoff: dCutoff, dt: dt))
        let cutoff = minCutoff + beta * length(edx)
        let filtered = lowpass(previous: xPrev, current: point, alpha: alpha(cutoff: cutoff, dt: dt))

        self.tPrev = timestamp
        self.xPrev = filtered
        self.dxPrev = edx

        return filtered
    }

    private func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2.0 * Double.pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    private func lowpass(previous: SIMD2<Double>, current: SIMD2<Double>, alpha: Double) -> SIMD2<Double> {
        alpha * current + (1 - alpha) * previous
    }
}
