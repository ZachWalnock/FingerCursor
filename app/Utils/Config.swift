import Foundation
import Combine
import CoreGraphics

/// Application-wide configuration values persisted to disk.
struct AppConfig: Codable, Equatable {
    struct GestureThresholds: Codable, Equatable {
        var pinchPixels: Double
        var twoFingerPixels: Double
        var palmAreaMinimum: Double
        var debounceMillis: Int
        var holdMillis: Int
        var refractoryMillis: Int
    }

    struct SmoothingSettings: Codable, Equatable {
        var minCutoff: Double
        var beta: Double
        var derivativeCutoff: Double
    }

    struct CursorSettings: Codable, Equatable {
        var baseGain: Double
        var accelerationK: Double
        var velocityReference: Double
    }

    struct DictationSettings: Codable, Equatable {
        enum Backend: String, Codable, CaseIterable {
            case appleSpeech
            case whisperCpp
        }
        var backend: Backend
        var languageCode: String
        var autoStopSilenceSeconds: Double
        var microphoneID: String?
    }

    struct CalibrationProfile: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var createdAt: Date
        var fingertipMap: [CGPointCodable]
        var cameraIntrinsic: CalibrationIntrinsics
        var deskDistanceMillimeters: Double
    }

    var gestureThresholds: GestureThresholds
    var smoothing: SmoothingSettings
    var cursor: CursorSettings
    var dictation: DictationSettings
    var activeProfileID: UUID?
    var profiles: [CalibrationProfile]
    var hotkeys: [HotkeyAction: HotkeyBinding]
    var diagnosticsEnabled: Bool
    var autoStartOnLogin: Bool

    static let `default` = AppConfig(
        gestureThresholds: .init(
            pinchPixels: 25,
            twoFingerPixels: 25,
            palmAreaMinimum: 190,
            debounceMillis: 120,
            holdMillis: 80,
            refractoryMillis: 200
        ),
        smoothing: .init(minCutoff: 1.2, beta: 0.007, derivativeCutoff: 1.0),
        cursor: .init(baseGain: 1.0, accelerationK: 0.35, velocityReference: 950),
        dictation: .init(backend: .appleSpeech, languageCode: "en-US", autoStopSilenceSeconds: 1.2, microphoneID: nil),
        activeProfileID: nil,
        profiles: [],
        hotkeys: HotkeyAction.defaultBindings,
        diagnosticsEnabled: false,
        autoStartOnLogin: false
    )
}

struct CalibrationIntrinsics: Codable, Equatable {
    var fx: Double
    var fy: Double
    var cx: Double
    var cy: Double
}

struct CGPointCodable: Codable, Equatable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

enum HotkeyAction: String, Codable, CaseIterable, Hashable {
    case toggleTracking
    case toggleDictation
    case pauseAll
    case showDiagnostics

    static var defaultBindings: [HotkeyAction: HotkeyBinding] {
        [
            .toggleTracking: .init(modifiers: [.option, .command], key: "T"),
            .toggleDictation: .init(modifiers: [.option, .command], key: "D"),
            .pauseAll: .init(modifiers: [.option, .command], key: "P"),
            .showDiagnostics: .init(modifiers: [.option, .command], key: "O")
        ]
    }
}

struct HotkeyBinding: Codable, Equatable {
    enum Modifier: String, Codable, CaseIterable, Hashable {
        case command
        case option
        case control
        case shift
    }
    var modifiers: Set<Modifier>
    var key: String
}

final class ConfigStore: ObservableObject {
    @Published private(set) var config: AppConfig
    private let storageURL: URL

    init(fileManager: FileManager = .default) {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = directory.appendingPathComponent("FingerCursor", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        storageURL = folder.appendingPathComponent("config.json")

        if let data = try? Data(contentsOf: storageURL), let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = decoded
        } else {
            config = .default
            persist()
        }
    }

    func update(_ block: (inout AppConfig) -> Void) {
        block(&config)
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            Logger.config.error("Failed to save configuration: \(error.localizedDescription)")
        }
    }
}
