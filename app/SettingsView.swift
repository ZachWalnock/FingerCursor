import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("Smoothing") {
                Slider(value: Binding(
                    get: { viewModel.configStore.config.smoothing.minCutoff },
                    set: { value in viewModel.configStore.update { $0.smoothing.minCutoff = value } }
                ), in: 0.2...5.0) {
                    Text("Min Cutoff")
                }
                Slider(value: Binding(
                    get: { viewModel.configStore.config.smoothing.beta },
                    set: { value in viewModel.configStore.update { $0.smoothing.beta = value } }
                ), in: 0...0.05) {
                    Text("Beta")
                }
                Slider(value: Binding(
                    get: { viewModel.configStore.config.smoothing.derivativeCutoff },
                    set: { value in viewModel.configStore.update { $0.smoothing.derivativeCutoff = value } }
                ), in: 0.5...5.0) {
                    Text("Derivative Cutoff")
                }
            }

            Section("Gestures") {
                Stepper(value: Binding(
                    get: { viewModel.configStore.config.gestureThresholds.pinchPixels },
                    set: { value in viewModel.configStore.update { $0.gestureThresholds.pinchPixels = value } }
                ), in: 5...80, step: 1) {
                    Text("Pinky Lift Sensitivity: \(Int(viewModel.configStore.config.gestureThresholds.pinchPixels)) px")
                }
                Stepper(value: Binding(
                    get: { viewModel.configStore.config.gestureThresholds.twoFingerPixels },
                    set: { value in viewModel.configStore.update { $0.gestureThresholds.twoFingerPixels = value } }
                ), in: 5...80, step: 1) {
                    Text("Two Finger Threshold: \(Int(viewModel.configStore.config.gestureThresholds.twoFingerPixels)) px")
                }
            }

            Section("Diagnostics") {
                Toggle("Enable Diagnostics", isOn: Binding(
                    get: { viewModel.configStore.config.diagnosticsEnabled },
                    set: { toggle in viewModel.configStore.update { $0.diagnosticsEnabled = toggle } }
                ))
            }
        }
        .padding(20)
        .frame(width: 400, alignment: .leading)
    }
}
