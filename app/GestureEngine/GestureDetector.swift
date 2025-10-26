import CoreGraphics
import Foundation

struct GestureDebugState: Equatable {
    var pinkyRaised: Bool = false
    var twoFingerActive: Bool = false
    var palmOpen: Bool = false
    var fistClosed: Bool = false
}

struct GestureState: OptionSet, Hashable {
    let rawValue: Int

    static let leftClick = GestureState(rawValue: 1 << 0)
    static let twoFinger = GestureState(rawValue: 1 << 1)
    static let palmOpen = GestureState(rawValue: 1 << 2)
}

enum GestureEvent {
    case leftClick
    case rightClick
    case dictationStart
    case dictationStop
    case swipe(direction: SwipeDirection)
}

enum SwipeDirection {
    case left
    case right
    case up
    case down
}

final class GestureDetector {
    struct Parameters {
        var twoFingerThreshold: CGFloat
        var palmAreaMinimum: CGFloat
        var debounce: TimeInterval
        var hold: TimeInterval
        var refractory: TimeInterval
        var pinkyLiftRatio: CGFloat
        var pinkyLiftDelta: CGFloat
        var pinkyLiftMinimum: CGFloat
        var pinkySeparation: CGFloat
        var pinkyStraightnessThreshold: CGFloat
        var fistMaximumExtension: CGFloat
    }

    func reset() {
        state = []
        timers.removeAll()
        lastEventTimestamp.removeAll()
        debugState = GestureDebugState()
        lastPalmActive = false
    }

    private var state: GestureState = []
    private var timers: [GestureState: Date] = [:]
    private var lastEventTimestamp: [GestureEvent: Date] = [:]
    private let clock: () -> Date
    private(set) var debugState = GestureDebugState()
    private var lastPalmActive = false

    init(clock: @escaping () -> Date = { Date() }) {
        self.clock = clock
    }

    func update(landmarks: HandLandmarks, parameters: Parameters) -> [GestureEvent] {
        guard landmarks.visibility > 0.1 else {
            state = []
            timers.removeAll()
            debugState = GestureDebugState()
            lastPalmActive = false
            return []
        }

        let now = clock()
        var triggered: [GestureEvent] = []

        let twoFingerActive = distance(landmarks.indexTip, landmarks.middleTip) < parameters.twoFingerThreshold
        let palmActive = averageFingerExtension(landmarks: landmarks) > parameters.palmAreaMinimum
        let pinkyRaised = isPinkyRaised(landmarks: landmarks, parameters: parameters)
        let fistActive = isFistClosed(landmarks: landmarks, maximumExtension: parameters.fistMaximumExtension)
        debugState = GestureDebugState(
            pinkyRaised: palmActive ? false : pinkyRaised,
            twoFingerActive: palmActive ? false : twoFingerActive,
            palmOpen: palmActive,
            fistClosed: fistActive
        )

        process(stateFlag: .palmOpen, isActive: palmActive, now: now, debounce: parameters.debounce, hold: parameters.hold) {
            triggered.append(.dictationStart)
        }

        if palmActive {
            timers[.leftClick] = nil
            timers[.twoFinger] = nil
            state.remove([.leftClick, .twoFinger])
        } else {
            process(stateFlag: .leftClick, isActive: pinkyRaised, now: now, debounce: parameters.debounce, hold: parameters.hold) {
                if self.canEmit(event: .leftClick, refractory: parameters.refractory, now: now) {
                    triggered.append(.leftClick)
                }
            }

            process(stateFlag: .twoFinger, isActive: twoFingerActive, now: now, debounce: parameters.debounce, hold: parameters.hold) {
                if self.canEmit(event: .rightClick, refractory: parameters.refractory, now: now) {
                    triggered.append(.rightClick)
                }
            }
        }

        if lastPalmActive && !palmActive {
            triggered.append(.dictationStop)
        }
        lastPalmActive = palmActive

        return triggered
    }

    private func process(stateFlag: GestureState, isActive: Bool, now: Date, debounce: TimeInterval, hold: TimeInterval, onTrigger: () -> Void) {
        if isActive {
            if timers[stateFlag] == nil {
                timers[stateFlag] = now
            }

            if let start = timers[stateFlag], now.timeIntervalSince(start) >= debounce + hold, !state.contains(stateFlag) {
                state.insert(stateFlag)
                onTrigger()
            }
        } else {
            timers[stateFlag] = nil
            state.remove(stateFlag)
        }
    }

    private func canEmit(event: GestureEvent, refractory: TimeInterval, now: Date) -> Bool {
        if let last = lastEventTimestamp[event], now.timeIntervalSince(last) < refractory {
            return false
        }
        lastEventTimestamp[event] = now
        return true
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func averageFingerExtension(landmarks: HandLandmarks) -> CGFloat {
        let tips = [landmarks.indexTip, landmarks.middleTip, landmarks.ringTip, landmarks.littleTip]
        let distances = tips.map { hypot($0.x - landmarks.palmCenter.x, $0.y - landmarks.palmCenter.y) }
        guard !distances.isEmpty else { return 0 }
        return distances.reduce(0, +) / CGFloat(distances.count)
    }

    private func isPinkyRaised(landmarks: HandLandmarks, parameters: Parameters) -> Bool {
        let ringExtension = fingerExtension(of: landmarks.ringTip, from: landmarks.palmCenter)
        let indexExtension = fingerExtension(of: landmarks.indexTip, from: landmarks.palmCenter)
        let middleExtension = fingerExtension(of: landmarks.middleTip, from: landmarks.palmCenter)
        let pinkyExtension = fingerExtension(of: landmarks.littleTip, from: landmarks.palmCenter)

        let averageOther = (ringExtension + indexExtension + middleExtension) / 3.0
        let exceedsAverage = pinkyExtension > averageOther * parameters.pinkyLiftRatio
        let exceedsRing = (pinkyExtension - ringExtension) > parameters.pinkyLiftDelta
        let exceedsMinimum = pinkyExtension > parameters.pinkyLiftMinimum
        let separated = distance(landmarks.littleTip, landmarks.ringTip) > parameters.pinkySeparation
        let straightness = pinkyStraightness(landmarks: landmarks)

        return exceedsMinimum
            && straightness > parameters.pinkyStraightnessThreshold
            && (exceedsAverage || exceedsRing || separated)
    }

    private func fingerExtension(of tip: CGPoint, from palmCenter: CGPoint) -> CGFloat {
        hypot(tip.x - palmCenter.x, tip.y - palmCenter.y)
    }

    private func pinkyStraightness(landmarks: HandLandmarks) -> CGFloat {
        guard let proximal = normalizedDirection(from: landmarks.littleMCP, to: landmarks.littlePIP),
              let distal = normalizedDirection(from: landmarks.littlePIP, to: landmarks.littleTip) else {
            return 0
        }
        return dot(proximal, distal)
    }

    private func normalizedDirection(from start: CGPoint, to end: CGPoint) -> CGPoint? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 1e-5 else { return nil }
        return CGPoint(x: dx / length, y: dy / length)
    }

    private func dot(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        (lhs.x * rhs.x) + (lhs.y * rhs.y)
    }

    private func isFistClosed(landmarks: HandLandmarks, maximumExtension: CGFloat) -> Bool {
        let tips = [landmarks.indexTip, landmarks.middleTip, landmarks.ringTip, landmarks.littleTip]
        let extensions = tips.map { fingerExtension(of: $0, from: landmarks.palmCenter) }
        guard !extensions.isEmpty else { return false }
        let average = extensions.reduce(0, +) / CGFloat(extensions.count)
        return average < maximumExtension
    }
}
