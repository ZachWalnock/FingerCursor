import XCTest
@testable import FingerCursor

final class GestureDetectorTests: XCTestCase {
    func testGestureDoesNotTriggerWhenInvisible() {
        let detector = GestureDetector()
        let parameters = GestureDetector.Parameters(
            twoFingerThreshold: 25,
            palmAreaMinimum: 115,
            debounce: 0.12,
            hold: 0.08,
            refractory: 0.2,
            pinkyLiftRatio: 1.05,
            pinkyLiftDelta: 0.02,
            pinkyLiftMinimum: 0.08,
            pinkySeparation: 0.035,
            pinkyStraightnessThreshold: 0.6,
            fistMaximumExtension: 0.065
        )
        let landmarks = HandLandmarks.none
        let events = detector.update(landmarks: landmarks, parameters: parameters)
        XCTAssertTrue(events.isEmpty)
    }
}
