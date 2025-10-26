import CoreGraphics

struct HandLandmarks: Equatable {
    let thumbTip: CGPoint
    let indexTip: CGPoint
    let indexPIP: CGPoint
    let indexMCP: CGPoint
    let middleTip: CGPoint
    let ringTip: CGPoint
    let littleTip: CGPoint
    let littlePIP: CGPoint
    let littleMCP: CGPoint
    let wrist: CGPoint
    let palmCenter: CGPoint
    let visibility: Double

    static let none = HandLandmarks(
        thumbTip: .zero,
        indexTip: .zero,
        indexPIP: .zero,
        indexMCP: .zero,
        middleTip: .zero,
        ringTip: .zero,
        littleTip: .zero,
        littlePIP: .zero,
        littleMCP: .zero,
        wrist: .zero,
        palmCenter: .zero,
        visibility: 0
    )
}

enum HandPoseState: Equatable {
    case none
    case tracking([HandLandmarks])
}
