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
littleMCP: .zero,** BUILD FAILED **
        
        
        The following build commands failed:
                SwiftCompile normal arm64 Compiling\ HandLandmarks.swift,\ CameraCapture.swift,\ CursorControl.swift /Users/zach/Applications/finger-cursor/app/GestureEngine/HandLandmarks.swift /Users/zach/Applications/finger-cursor/app/InputOutput/CameraCapture.swift /Users/zach/Applications/finger-cursor/app/InputOutput/CursorControl.swift (in target 'FingerCursor' from project 'FingerCursor')
                SwiftCompile normal arm64 /Users/zach/Applications/finger-cursor/app/InputOutput/CursorControl.swift (in target 'FingerCursor' from project 'FingerCursor')
                SwiftCompile normal arm64 Compiling\ Dictation.swift,\ OneEuroFilter.swift,\ Logging.swift /Users/zach/Applications/finger-cursor/app/InputOutput/Dictation.swift /Users/zach/Applications/finger-cursor/app/GestureEngine/OneEuroFilter.swift /Users/zach/Applications/finger-cursor/app/Utils/Logging.swift (in target 'FingerCursor' from project 'FingerCursor')
                Building project FingerCursor with scheme FingerCursor and configuration Debug
        (4 failures)        wrist: .zero,
        palmCenter: .zero,
        visibility: 0
    )
}

enum HandPoseState: Equatable {
    case none
    case tracking([HandLandmarks])
}
