import AVFoundation

protocol CameraCaptureDelegate: AnyObject {
    func cameraCapture(_ capture: CameraCapture, didOutput buffer: CVPixelBuffer, at timestamp: CMTime)
    func cameraCapture(_ capture: CameraCapture, didFail error: Error)
}

enum CameraCaptureError: Error {
    case unauthorized
    case configurationFailed
}

final class CameraCapture: NSObject {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.fingercursor.camera")
    private var videoOutput = AVCaptureVideoDataOutput()

    weak var delegate: CameraCaptureDelegate?

    func start() {
        queue.async { [weak self] in
            self?.configureIfNeeded()
            self?.session.startRunning()
            Logger.lifecycle.debug("Camera capture started")
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.session.stopRunning()
            Logger.lifecycle.debug("Camera capture stopped")
        }
    }

    private func configureIfNeeded() {
        guard session.inputs.isEmpty else { return }

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            delegate?.cameraCapture(self, didFail: CameraCaptureError.configurationFailed)
            session.commitConfiguration()
            return
        }

        do {
            try device.lockForConfiguration()

            if let range = device.activeFormat.videoSupportedFrameRateRanges
                .sorted(by: { $0.maxFrameRate > $1.maxFrameRate })
                .first {

                let targetFrameRate = min(60.0, range.maxFrameRate)
                let durationSeconds = 1.0 / targetFrameRate
                let minDurationSeconds = CMTimeGetSeconds(range.minFrameDuration)
                let maxDurationSeconds = CMTimeGetSeconds(range.maxFrameDuration)

                let epsilon = 1e-6
                let clampedDurationSeconds: Double

                if durationSeconds >= minDurationSeconds - epsilon && durationSeconds <= maxDurationSeconds + epsilon {
                    clampedDurationSeconds = durationSeconds
                } else {
                    Logger.tracking.error("Desired frame duration \(durationSeconds) outside supported range \(minDurationSeconds)...\(maxDurationSeconds)")
                    clampedDurationSeconds = minDurationSeconds
                }

                let duration = CMTimeMakeWithSeconds(clampedDurationSeconds, preferredTimescale: 600)
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
            }

            device.unlockForConfiguration()
        } catch {
            Logger.tracking.error("Failed to configure camera: \(error.localizedDescription)")
        }

        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            delegate?.cameraCapture(self, didFail: CameraCaptureError.configurationFailed)
            session.commitConfiguration()
            return
        }

        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

        guard session.canAddOutput(videoOutput) else {
            delegate?.cameraCapture(self, didFail: CameraCaptureError.configurationFailed)
            session.commitConfiguration()
            return
        }

        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }

        session.commitConfiguration()
    }
}

extension CameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        delegate?.cameraCapture(self, didOutput: buffer, at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
}
