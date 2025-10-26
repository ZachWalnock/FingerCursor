import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: viewModel.menuBarSymbol)
                    .foregroundStyle(.blue)
                Text(viewModel.statusMessage)
                    .font(.headline)
            }

            Toggle("Tracking", isOn: Binding(
                get: { viewModel.trackingEnabled },
                set: { viewModel.setTracking($0) }
            ))
            .toggleStyle(.switch)

            Toggle("Dictation", isOn: Binding(
                get: { viewModel.dictationActive },
                set: { viewModel.setDictation($0) }
            ))
            .toggleStyle(.switch)

            Toggle("Camera Visual", isOn: Binding(
                get: { viewModel.showCameraDebug },
                set: { viewModel.showCameraDebug = $0 }
            ))
            .toggleStyle(.switch)

        if viewModel.showCameraDebug {
            CameraDebugView(viewModel: viewModel)
                .transition(.opacity)
        }

        Divider()

        GestureThresholdSection(viewModel: viewModel)

        Divider()

        Button(viewModel.showDiagnostics ? "Hide Diagnostics" : "Show Diagnostics") {
            viewModel.showDiagnostics.toggle()
        }

            Divider()

            Button("Quit FingerCursor") {
                NSApp.terminate(nil)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GestureThresholdSection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Gesture Thresholds")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            GestureThresholdSlider(
                title: "Pinky Sensitivity",
                value: Binding(
                    get: { viewModel.configStore.config.gestureThresholds.pinchPixels },
                    set: { newValue in
                        viewModel.configStore.update { $0.gestureThresholds.pinchPixels = newValue }
                    }
                ),
                range: 5...80,
                formatValue: { "\(Int($0)) px" }
            )

            GestureThresholdSlider(
                title: "Two Finger Gap",
                value: Binding(
                    get: { viewModel.configStore.config.gestureThresholds.twoFingerPixels },
                    set: { newValue in
                        viewModel.configStore.update { $0.gestureThresholds.twoFingerPixels = newValue }
                    }
                ),
                range: 5...80,
                formatValue: { "\(Int($0)) px" }
            )

            GestureThresholdSlider(
                title: "Palm Openness",
                value: Binding(
                    get: { viewModel.configStore.config.gestureThresholds.palmAreaMinimum },
                    set: { newValue in
                        viewModel.configStore.update { $0.gestureThresholds.palmAreaMinimum = newValue }
                    }
                ),
                range: 60...220,
                formatValue: { "\(Int($0))" }
            )

            GestureActivityRow(state: viewModel.gestureDebug)
        }
    }
}

private struct GestureThresholdSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let formatValue: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(formatValue(value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: 1)
        }
    }
}

private struct GestureActivityRow: View {
    let state: GestureDebugState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gesture Activity")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                GestureIndicator(label: "Left Click", active: state.pinkyRaised)
                GestureIndicator(label: "Right Click", active: state.twoFingerActive)
                GestureIndicator(label: "Dictation", active: state.palmOpen)
                GestureIndicator(label: "Fist", active: state.fistClosed)
            }
        }
        .padding(.top, 6)
    }
}

private struct GestureIndicator: View {
    let label: String
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 10, height: 10)
                .shadow(color: active ? .green.opacity(0.6) : .clear, radius: 3)
            Text(label)
                .font(.caption)
                .foregroundStyle(active ? .primary : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(active ? Color.green.opacity(0.12) : Color.secondary.opacity(0.08))
        )
    }
}
