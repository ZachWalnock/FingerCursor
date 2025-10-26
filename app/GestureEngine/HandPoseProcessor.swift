import AVFoundation
import Vision
import CoreGraphics

/// Processes camera frames to extract hand landmarks using Vision.
final class HandPoseProcessor {
    private let request: VNDetectHumanHandPoseRequest
    private let handler = VNSequenceRequestHandler()
    private let detectionQueue = DispatchQueue(label: "com.fingercursor.handpose")

    init(maximumHands: Int = 2) {
        request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = maximumHands
    }

    /// Runs the hand pose request and returns the tracking state.
    func process(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> HandPoseState {
        var resultState: HandPoseState = .none

        detectionQueue.sync {
            do {
                try handler.perform([request], on: pixelBuffer, orientation: orientation)
                let observations = (request.results ?? []).prefix(request.maximumHandCount)
                let landmarksList = observations.compactMap { self.makeLandmarks(from: $0) }
                resultState = landmarksList.isEmpty ? .none : .tracking(landmarksList)
            } catch {
                Logger.tracking.error("Vision hand pose failed: \(error.localizedDescription)")
                resultState = .none
            }
        }

        return resultState
    }

    private func makeLandmarks(from observation: VNHumanHandPoseObservation) -> HandLandmarks? {
        do {
            let thumbTip = try observation.recognizedPoint(.thumbTip)
            let indexTip = try observation.recognizedPoint(.indexTip)
            let indexPIP = try observation.recognizedPoint(.indexPIP)
            let indexMCP = try observation.recognizedPoint(.indexMCP)
            let middleTip = try observation.recognizedPoint(.middleTip)
            let ringTip = try observation.recognizedPoint(.ringTip)
            let littleTip = try observation.recognizedPoint(.littleTip)
            let littlePIP = try observation.recognizedPoint(.littlePIP)
            let littleMCP = try observation.recognizedPoint(.littleMCP)
            let wrist = try observation.recognizedPoint(.wrist)

            let points = [
                thumbTip, indexTip, indexPIP, indexMCP,
                middleTip, ringTip,
                littleTip, littlePIP, littleMCP,
                wrist
            ]

            guard points.allSatisfy({ $0.confidence > 0.2 }) else {
                return nil
            }

            let convert: (VNRecognizedPoint) -> CGPoint = { point in
                point.location
            }

            let palmCenter = computePalmCenter(from: observation)
            let visibility = points.reduce(0.0) { $0 + Double($1.confidence) } / Double(points.count)

            return HandLandmarks(
                thumbTip: convert(thumbTip),
                indexTip: convert(indexTip),
                indexPIP: convert(indexPIP),
                indexMCP: convert(indexMCP),
                middleTip: convert(middleTip),
                ringTip: convert(ringTip),
                littleTip: convert(littleTip),
                littlePIP: convert(littlePIP),
                littleMCP: convert(littleMCP),
                wrist: convert(wrist),
                palmCenter: palmCenter ?? convert(wrist),
                visibility: visibility
            )
        } catch {
            Logger.tracking.error("Failed to extract hand landmarks: \(error.localizedDescription)")
            return nil
        }
    }

    /// Calculates an approximate palm center using key landmarks.
    private func computePalmCenter(from observation: VNHumanHandPoseObservation) -> CGPoint? {
        let keys: [VNHumanHandPoseObservation.JointName] = [
            .wrist, .indexMCP, .middleMCP, .ringMCP, .littleMCP
        ]

        let points: [VNRecognizedPoint] = keys.compactMap { try? observation.recognizedPoint($0) }
        guard !points.isEmpty else { return nil }

        let averaged = points.reduce(CGPoint.zero) { partial, point in
            return CGPoint(x: partial.x + point.location.x, y: partial.y + point.location.y)
        }

        return CGPoint(x: averaged.x / CGFloat(points.count), y: averaged.y / CGFloat(points.count))
    }
}
