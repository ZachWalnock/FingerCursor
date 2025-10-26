import AppKit
import AVFoundation
import Combine
import CoreGraphics
import CoreImage
import Vision

enum TrackingStatus: Equatable {
    case idle
    case cameraUnauthorized
    case preparing
    case searchingHand
    case tracking
}

/// Coordinates camera capture, hand detection, gesture recognition, and cursor control.
final class TrackingCoordinator: NSObject {
    var statusHandler: ((TrackingStatus) -> Void)?
    var gestureEventHandler: ((GestureEvent) -> Void)?
    var gestureDebugHandler: ((GestureDebugState) -> Void)?

    private let cameraCapture = CameraCapture()
    private let cursorControl = CursorControl()
    private let handPoseProcessor = HandPoseProcessor()
    private let gestureDetector = GestureDetector()
    private var mapper = FingertipMapper()
    private let ciContext = CIContext()
    private let frameSemaphore = DispatchSemaphore(value: 1)

    private let processingQueue = DispatchQueue(label: "com.fingercursor.tracking-coordinator")
    private let configStore: ConfigStore
    private var configCancellable: AnyCancellable?
    private var currentConfig: AppConfig

    private var trackingActive = false
    private var lastHandObservation: Date?
    private var lastFilteredPoint: CGPoint?
    private var lastCursorPosition: CGPoint?
    private var lastTimestamp: Double?
    private var debugFrameHandler: ((CameraDebugFrame) -> Void)?
    private let clickDelay: TimeInterval = 0
    private var smoothedOrientation: CGFloat?
    private var lastGestureDebug = GestureDebugState()
    private var fistSwipeOrigin: CGPoint?
    private var fistSwipeTimestamp: Double?

    private let handLossTimeout: TimeInterval = 0.2

    init(configStore: ConfigStore) {
        self.configStore = configStore
        self.currentConfig = configStore.config
        super.init()

        cameraCapture.delegate = self
        observeConfig()
    }

    func start() {
        guard !trackingActive else { return }
        trackingActive = true

        Task { @MainActor in
            statusHandler?(.preparing)
        }

        requestCameraAccess { [weak self] granted in
            guard let self else { return }
            if !granted {
                self.stopInternal(reason: .cameraUnauthorized)
                return
            }

            self.processingQueue.async {
                self.mapper.reset()
                self.cursorControl.setPaused(false)
                self.cursorControl.requestAccessibilityPermissionIfNeeded()
                self.lastFilteredPoint = nil
                self.lastCursorPosition = nil
                self.lastTimestamp = nil
                self.lastHandObservation = nil
                self.cameraCapture.start()
                self.notifyStatus(.searchingHand)
            }
        }
    }

    func stop() {
        stopInternal(reason: .idle)
    }

    func setDebugFrameHandler(_ handler: ((CameraDebugFrame) -> Void)?) {
        processingQueue.async {
            self.debugFrameHandler = handler
        }
    }

    private func stopInternal(reason: TrackingStatus) {
        processingQueue.async {
            guard self.trackingActive else { return }
            self.cameraCapture.stop()
            self.cursorControl.setPaused(true)
            self.trackingActive = false
            self.lastFilteredPoint = nil
            self.lastCursorPosition = nil
            self.lastTimestamp = nil
            self.lastHandObservation = nil
            self.gestureDetector.reset()
            self.notifyStatus(reason)
        }
    }

    private func observeConfig() {
        configCancellable = configStore.$config
            .receive(on: DispatchQueue.main)
            .sink { [weak self] config in
                self?.currentConfig = config
            }
    }

    private func notifyStatus(_ status: TrackingStatus) {
        Task { @MainActor in
            self.statusHandler?(status)
        }
    }

    private func requestCameraAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                completion(granted)
            }
        default:
            completion(false)
        }
    }

    private func handleHandState(_ state: HandPoseState, timestamp: CMTime) {
        switch state {
        case .none:
            handleHandLost()
        case .tracking(let landmarks):
            lastHandObservation = Date()
            processLandmarks(landmarks, timestamp: timestamp)
        }
    }

    private func handleHandLost() {
        let now = Date()
        if let lastSeen = lastHandObservation, now.timeIntervalSince(lastSeen) < handLossTimeout {
            return
        }

        mapper.reset()
        lastFilteredPoint = nil
        lastCursorPosition = nil
        lastTimestamp = nil
        notifyStatus(.searchingHand)
        gestureDetector.reset()
        smoothedOrientation = nil
        lastGestureDebug = GestureDebugState()
        fistSwipeOrigin = nil
        fistSwipeTimestamp = nil
    }

    private func processLandmarks(_ landmarks: HandLandmarks, timestamp: CMTime) {
        guard let screenFrame = virtualScreenBounds() else { return }

        let orientationHint = computeOrientationHint(for: landmarks)
        if let hint = orientationHint {
            if let current = smoothedOrientation {
                smoothedOrientation = current + (hint - current) * 0.25
            } else {
                smoothedOrientation = hint
            }
        } else {
            smoothedOrientation = nil
        }

        let mappingContext = MappingContext(
            roi: CGRect(x: 0, y: 0, width: 1, height: 1),
            screenSize: screenFrame.size,
            gain: currentConfig.smoothing.minCutoff,
            accelerationK: currentConfig.smoothing.beta,
            velocityReference: currentConfig.smoothing.derivativeCutoff,
            orientationHint: smoothedOrientation,
            orientationWeight: 0.18
        )

        let fingertipPoint = mapper.map(point: landmarks.indexTip, within: mappingContext)
        let clamped = clamp(point: fingertipPoint, to: screenFrame)

        let timestampSeconds = CMTimeGetSeconds(timestamp)
        let cursorPoint = applyCursorDynamics(target: clamped, timestamp: timestampSeconds)

        cursorControl.moveCursor(to: cursorPoint)
        notifyStatus(.tracking)

        dispatchGestures(for: landmarks)
    }

    private func applyCursorDynamics(target: CGPoint, timestamp: Double) -> CGPoint {
        let cursorConfig = currentConfig.cursor

        guard let previousFiltered = lastFilteredPoint,
              let previousCursor = lastCursorPosition,
              let previousTimestamp = lastTimestamp else {
            lastFilteredPoint = target
            lastCursorPosition = target
            lastTimestamp = timestamp
            return target
        }

        let dt = max(0.001, timestamp - previousTimestamp)
        var delta = CGPoint(x: target.x - previousFiltered.x, y: target.y - previousFiltered.y)
        let rawDistance = hypot(delta.x, delta.y)
        if rawDistance > 0 {
            let maxStep: CGFloat = 140
            if rawDistance > maxStep {
                let scale = maxStep / rawDistance
                delta = CGPoint(x: delta.x * scale, y: delta.y * scale)
            }
        }
        let distance = hypot(delta.x, delta.y)
        let velocity = distance / dt

        let gain = cursorConfig.baseGain * (1 + cursorConfig.accelerationK * min(velocity / cursorConfig.velocityReference, 1))

        let next = CGPoint(
            x: previousCursor.x + delta.x * gain,
            y: previousCursor.y + delta.y * gain
        )

        lastFilteredPoint = target
        lastCursorPosition = next
        lastTimestamp = timestamp

        let fallbackFrame = CGRect(
            origin: .zero,
            size: CGSize(width: max(target.x, 1), height: max(target.y, 1))
        )
        return clamp(point: next, to: virtualScreenBounds() ?? fallbackFrame)
    }

    private func dispatchGestures(for landmarks: HandLandmarks) {
        let pinkySetting = min(max(currentConfig.gestureThresholds.pinchPixels, 5), 80)
        let pinkyScale = CGFloat((pinkySetting - 5) / 75)
        let pinkyLiftMinimum = CGFloat(0.06 + pinkyScale * 0.12)
        let pinkyLiftDelta = CGFloat(0.015 + pinkyScale * 0.045)
        let pinkySeparation = CGFloat(0.028 + pinkyScale * 0.02)
        let pinkyStraightnessThreshold = CGFloat(0.5 + pinkyScale * 0.3)

        let params = GestureDetector.Parameters(
            twoFingerThreshold: CGFloat(currentConfig.gestureThresholds.twoFingerPixels / 720.0),
            palmAreaMinimum: CGFloat(currentConfig.gestureThresholds.palmAreaMinimum / 720.0),
            debounce: TimeInterval(currentConfig.gestureThresholds.debounceMillis) / 1000.0,
            hold: TimeInterval(currentConfig.gestureThresholds.holdMillis) / 1000.0,
            refractory: TimeInterval(currentConfig.gestureThresholds.refractoryMillis) / 1000.0,
            pinkyLiftRatio: CGFloat(1.05),
            pinkyLiftDelta: pinkyLiftDelta,
            pinkyLiftMinimum: pinkyLiftMinimum,
            pinkySeparation: pinkySeparation,
            pinkyStraightnessThreshold: pinkyStraightnessThreshold,
            fistMaximumExtension: 0.065
        )

        var events = gestureDetector.update(landmarks: landmarks, parameters: params)
        let debugState = gestureDetector.debugState

        if let swipe = detectFistSwipe(at: cursorPoint, timestamp: timestampSeconds, debugState: debugState) {
            events.append(swipe)
        }

        if let debugHandler = gestureDebugHandler {
            Task { @MainActor in debugHandler(debugState) }
        }

        for event in events {
            switch event {
            case .leftClick, .rightClick:
                scheduleClick(event, at: lastCursorPosition)
                if let handler = gestureEventHandler {
                    Task { @MainActor in handler(event) }
                }
            case .dictationStart, .dictationStop:
                if let handler = gestureEventHandler {
                    Task { @MainActor in handler(event) }
                }
            case .swipe(let direction):
                cursorControl.performSwipe(direction)
                if let handler = gestureEventHandler {
                    Task { @MainActor in handler(event) }
                }
            }
        }

        lastGestureDebug = debugState
    }

    private func clamp(point: CGPoint, to frame: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, frame.minX), frame.maxX),
            y: min(max(point.y, frame.minY), frame.maxY)
        )
    }

    private func computeOrientationHint(for landmarks: HandLandmarks) -> CGFloat? {
        guard let proximal = normalizedDirection(from: landmarks.indexMCP, to: landmarks.indexPIP),
              let distal = normalizedDirection(from: landmarks.indexPIP, to: landmarks.indexTip) else {
            return nil
        }

        var combined = CGPoint(x: proximal.x + distal.x, y: proximal.y + distal.y)
        let length = hypot(combined.x, combined.y)
        guard length > 1e-5 else { return nil }
        combined.x /= length
        combined.y /= length

        let clampedY = max(CGFloat(-1), min(CGFloat(1), combined.y))
        return 0.5 * (1 - clampedY)
    }

    private func normalizedDirection(from start: CGPoint, to end: CGPoint) -> CGPoint? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 1e-5 else { return nil }
        return CGPoint(x: dx / length, y: dy / length)
    }

    private func detectFistSwipe(at point: CGPoint, timestamp: Double, debugState: GestureDebugState) -> GestureEvent? {
        if debugState.fistClosed {
            if fistSwipeOrigin == nil {
                fistSwipeOrigin = point
                fistSwipeTimestamp = timestamp
                return nil
            }

            guard let origin = fistSwipeOrigin, let start = fistSwipeTimestamp else { return nil }
            let dx = point.x - origin.x
            let dy = point.y - origin.y
            let distance = hypot(dx, dy)

            let swipeDistance: CGFloat = 180
            let swipeDuration: Double = 0.45

            if distance >= swipeDistance && (timestamp - start) <= swipeDuration {
                fistSwipeOrigin = nil
                fistSwipeTimestamp = nil

                if abs(dx) > abs(dy) {
                    return .swipe(direction: dx > 0 ? .right : .left)
                } else {
                    return .swipe(direction: dy > 0 ? .up : .down)
                }
            }
        } else {
            fistSwipeOrigin = nil
            fistSwipeTimestamp = nil
        }

        return nil
    }

    private func scheduleClick(_ event: GestureEvent, at location: CGPoint?) {
        let execute = { [weak self] in
            guard let self else { return }
            let resolvedLocation = location ?? NSEvent.mouseLocation
            self.cursorControl.click(type: event, at: resolvedLocation)
        }

        if clickDelay <= 0 {
            DispatchQueue.main.async(execute: execute)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + clickDelay, execute: execute)
        }
    }

    private func virtualScreenBounds() -> CGRect? {
        let computeBounds: () -> CGRect? = {
            let frames = NSScreen.screens.map { $0.frame }
            guard let first = frames.first else { return nil }
            return frames.dropFirst().reduce(first) { partial, next in
                partial.union(next)
            }
        }

        if Thread.isMainThread {
            return computeBounds()
        } else {
            return DispatchQueue.main.sync {
                computeBounds()
            }
        }
    }

    private func emitDebugFrame(buffer: CVPixelBuffer, state: HandPoseState, orientation: CGImagePropertyOrientation, timestamp: CMTime) {
        guard let handler = debugFrameHandler else { return }

        let ciImage = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        let landmarks: HandLandmarks?
        switch state {
        case .none:
            landmarks = nil
        case .tracking(let detail):
            landmarks = detail
        }

        let frame = CameraDebugFrame(image: cgImage, landmarks: landmarks, timestamp: timestamp)

        Task { @MainActor in
            handler(frame)
        }
    }
}

extension TrackingCoordinator: CameraCaptureDelegate {
    func cameraCapture(_ capture: CameraCapture, didOutput buffer: CVPixelBuffer, at timestamp: CMTime) {
        guard trackingActive else { return }
        guard frameSemaphore.wait(timeout: .now()) == .success else { return }
        processingQueue.async {
            defer { self.frameSemaphore.signal() }
            let orientation: CGImagePropertyOrientation = .upMirrored
            let handState = self.handPoseProcessor.process(pixelBuffer: buffer, orientation: orientation)
            self.handleHandState(handState, timestamp: timestamp)
            self.emitDebugFrame(buffer: buffer, state: handState, orientation: orientation, timestamp: timestamp)
        }
    }

    func cameraCapture(_ capture: CameraCapture, didFail error: Error) {
        Logger.tracking.error("Camera capture error: \(error.localizedDescription)")
        stopInternal(reason: .cameraUnauthorized)
    }
}
