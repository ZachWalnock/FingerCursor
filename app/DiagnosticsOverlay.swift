import SwiftUI

struct DiagnosticsOverlay: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diagnostics")
                .font(.headline)
            Text("Tracking: \(viewModel.trackingEnabled ? "On" : "Off")")
            Text("Dictation: \(viewModel.dictationActive ? "On" : "Off")")
            Text("Status: \(viewModel.statusMessage)")
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 6)
        .padding()
    }
}
