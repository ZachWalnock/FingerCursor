import Foundation
import CoreGraphics
import simd

struct MappingContext {
    var roi: CGRect
    var screenSize: CGSize
    var gain: Double
    var accelerationK: Double
    var velocityReference: Double
    var orientationHint: CGFloat?
    var orientationWeight: CGFloat
}

final class FingertipMapper {
    private var filter = OneEuroFilter()

    func reset() {
        filter.reset()
    }

    func map(point: CGPoint, within context: MappingContext) -> CGPoint {
        let normalized = normalize(point, in: context.roi)
        // Flip horizontally to counteract the mirrored camera feed so left/right match the cursor.
        let mirrored = CGPoint(x: 1 - normalized.x, y: normalized.y)
        let baseVertical = 1 - mirrored.y

        let blendedVertical: CGFloat
        if let hint = context.orientationHint {
            let weight = clamp01(context.orientationWeight)
            let clampedHint = clamp01(hint)
            blendedVertical = baseVertical * (1 - weight) + clampedHint * weight
        } else {
            blendedVertical = baseVertical
        }

        let screenPoint = CGPoint(
            x: mirrored.x * context.screenSize.width,
            y: blendedVertical * context.screenSize.height
        )
        let now = Date()
        let filtered = applyFilter(point: screenPoint, timestamp: now.timeIntervalSinceReferenceDate, context: context)
        return filtered
    }

    private func normalize(_ point: CGPoint, in roi: CGRect) -> CGPoint {
        guard roi.width > 0, roi.height > 0 else { return .zero }
        return CGPoint(
            x: (point.x - roi.origin.x) / roi.width,
            y: (point.y - roi.origin.y) / roi.height
        )
    }

    private func applyFilter(point: CGPoint, timestamp: Double, context: MappingContext) -> CGPoint {
        var workingFilter = filter
        workingFilter.minCutoff = context.gain
        workingFilter.beta = context.accelerationK
        workingFilter.dCutoff = context.velocityReference

        let vector = SIMD2<Double>(point)
        let filtered = workingFilter.filter(vector, timestamp: timestamp)
        filter = workingFilter
        return CGPoint(filtered)
    }

    private func clamp01(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

private extension SIMD2 where Scalar == Double {
    init(_ point: CGPoint) {
        self.init(point.x.native, point.y.native)
    }
}

private extension CGPoint {
    init(_ vector: SIMD2<Double>) {
        self.init(x: vector.x, y: vector.y)
    }
}
