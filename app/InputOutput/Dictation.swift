import AVFoundation
import Speech

protocol DictationDelegate: AnyObject {
    func dictation(_ dictation: DictationController, didRecognize text: String)
    func dictationDidStart(_ dictation: DictationController)
    func dictationDidStop(_ dictation: DictationController)
    func dictation(_ dictation: DictationController, didFail error: Error)
}

enum DictationBackend {
    case appleSpeech
    case whisperCpp(modelPath: String)
}

enum DictationControllerError: Error {
    case unauthorized
    case recognizerUnavailable
}

final class DictationController: NSObject {
    weak var delegate: DictationDelegate?

    private let speechRecognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func start(languageCode: String, inputID: String?) {
        requestPermissions { [weak self] granted in
            guard let self else { return }
            guard granted else {
                delegate?.dictation(self, didFail: DictationControllerError.unauthorized)
                return
            }
            self.beginRecognition(languageCode: languageCode, inputID: inputID)
        }
    }

    func stop() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        delegate?.dictationDidStop(self)
    }

    private func beginRecognition(languageCode: String, inputID: String?) {
        guard let speechRecognizer else {
            delegate?.dictation(self, didFail: DictationControllerError.recognizerUnavailable)
            return
        }

        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: 0)
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest!, resultHandler: { [weak self] result, error in
            guard let self else { return }
            if let result {
                delegate?.dictation(self, didRecognize: result.bestTranscription.formattedString)
            }
            if error != nil || result?.isFinal == true {
                self.stop()
            }
        })

        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            delegate?.dictationDidStart(self)
        } catch {
            delegate?.dictation(self, didFail: error)
        }
    }

    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            completion(status == .authorized)
        }
    }
}
