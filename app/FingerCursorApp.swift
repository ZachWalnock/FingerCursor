import SwiftUI
import Combine
import ApplicationServices

@main
struct FingerCursorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()

    init() {
        Logger.lifecycle.debug("FingerCursorApp init")
    }

    var body: some Scene {
        MenuBarExtra("FingerCursor", systemImage: viewModel.menuBarSymbol) {
            MenuBarView(viewModel: viewModel)
                .frame(width: 260)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}

final class AppViewModel: ObservableObject {
    @Published private(set) var trackingEnabled = false
    @Published private(set) var dictationActive = false
    @Published var statusMessage = "Idle"
    @Published var showDiagnostics = false
    @Published var showCameraDebug = false
    @Published private(set) var latestDebugFrame: CameraDebugFrame?
    @Published var gestureDebug = GestureDebugState()

    let configStore: ConfigStore
    private let trackingCoordinator: TrackingCoordinator
    private let dictationController: DictationController
    private var cancellables = Set<AnyCancellable>()
    private var lastDictationText: String = ""
    private var dictationRequested = false

    init(configStore: ConfigStore = ConfigStore()) {
        self.configStore = configStore
        self.trackingCoordinator = TrackingCoordinator(configStore: configStore)
        self.dictationController = DictationController()
        self.dictationController.delegate = self
        setupBindings()

        $showCameraDebug
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.toggleCameraDebug(enabled)
            }
            .store(in: &cancellables)

        setTracking(true)
    }

    var menuBarSymbol: String {
        if dictationActive { return "waveform" }
        return trackingEnabled ? "hand.tap" : "hand.raised"
    }

    func setTracking(_ enabled: Bool) {
        if enabled {
            statusMessage = "Preparing camera..."
            trackingCoordinator.start()
        } else {
            trackingCoordinator.stop()
        }
    }

    func setDictation(_ active: Bool) {
        if active {
            startDictationIfNeeded()
        } else {
            stopDictationIfNeeded()
        }
    }

    private func setupBindings() {
        trackingCoordinator.statusHandler = { [weak self] status in
            guard let self else { return }
            switch status {
            case .idle:
                self.trackingEnabled = false
                self.statusMessage = "Idle"
            case .cameraUnauthorized:
                self.trackingEnabled = false
                self.statusMessage = "Camera access required"
            case .preparing:
                self.trackingEnabled = true
                self.statusMessage = "Preparing camera..."
            case .searchingHand:
                self.trackingEnabled = true
                self.statusMessage = "Searching for hand..."
            case .tracking:
                self.trackingEnabled = true
                self.statusMessage = "Tracking"
            }
        }

        trackingCoordinator.gestureEventHandler = { [weak self] event in
            self?.handleGesture(event)
        }

        trackingCoordinator.gestureDebugHandler = { [weak self] state in
            self?.gestureDebug = state
        }
    }

    private func handleGesture(_ event: GestureEvent) {
        switch event {
        case .dictationStart:
            startDictationIfNeeded()
        case .dictationStop:
            stopDictationIfNeeded()
        case .swipe:
            break
        default:
            break
        }
    }

    private func startDictationIfNeeded() {
        guard !dictationRequested else { return }
        lastDictationText = ""
        dictationRequested = true
        dictationController.start(
            languageCode: configStore.config.dictation.languageCode,
            inputID: configStore.config.dictation.microphoneID
        )
    }

    private func stopDictationIfNeeded() {
        guard dictationRequested else { return }
        dictationRequested = false
        lastDictationText = ""
        dictationController.stop()
    }

    private func typeText(_ text: String) {
        guard !text.isEmpty else { return }
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        down?.keyboardSetUnicodeString(string: text)
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        up?.keyboardSetUnicodeString(string: text)
        up?.post(tap: .cghidEventTap)
    }

    private func toggleCameraDebug(_ enabled: Bool) {
        if enabled {
            trackingCoordinator.setDebugFrameHandler { [weak self] frame in
                self?.latestDebugFrame = frame
            }
        } else {
            trackingCoordinator.setDebugFrameHandler(nil)
            latestDebugFrame = nil
        }
    }
}

extension AppViewModel: DictationDelegate {
    func dictation(_ dictation: DictationController, didRecognize text: String) {
        let common = text.commonPrefix(with: lastDictationText)
        let suffix = String(text.dropFirst(common.count))
        lastDictationText = text
        if suffix.isEmpty { return }
        DispatchQueue.main.async {
            self.typeText(suffix)
        }
    }

    func dictationDidStart(_ dictation: DictationController) {
        DispatchQueue.main.async {
            self.lastDictationText = ""
            self.dictationActive = true
        }
    }

    func dictationDidStop(_ dictation: DictationController) {
        DispatchQueue.main.async {
            self.dictationRequested = false
            self.lastDictationText = ""
            self.dictationActive = false
        }
    }

    func dictation(_ dictation: DictationController, didFail error: Error) {
        DispatchQueue.main.async {
            self.dictationRequested = false
            self.lastDictationText = ""
            self.dictationActive = false
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Logger.lifecycle.debug("Application launched")
    }
}
