import AVFoundation

protocol MicCaptureDelegate: AnyObject {
    func micCapture(_ capture: MicCapture, didOutput buffer: AVAudioPCMBuffer, when time: AVAudioTime)
    func micCapture(_ capture: MicCapture, didFail error: Error)
}

enum MicCaptureError: Error {
    case unauthorized
    case configurationFailed
}

final class MicCapture {
    private let engine = AVAudioEngine()
    weak var delegate: MicCaptureDelegate?

    func start(inputID: String? = nil) throws {
#if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, options: [.allowBluetooth, .allowBluetoothA2DP])
        try session.setPreferredSampleRate(44100)
        try session.setActive(true)

        if let inputID, let availableInput = session.availableInputs?.first(where: { $0.uid == inputID }) {
            try session.setPreferredInput(availableInput)
        }
#endif
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, time in
            guard let self else { return }
            delegate?.micCapture(self, didOutput: buffer, when: time)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
#if !os(macOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
    }
}
