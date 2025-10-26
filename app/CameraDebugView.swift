import SwiftUI

struct CameraDebugView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let frame = viewModel.latestDebugFrame {
                GeometryReader { proxy in
                    let size = proxy.size
                    ZStack {
                        Image(decorative: frame.image, scale: 1, orientation: .up)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .clipped()

                        CameraLandmarksOverlay(frame: frame)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Waiting for camera…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Text(viewModel.statusMessage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.45))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(8)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .background(.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct CameraLandmarksOverlay: View {
    let frame: CameraDebugFrame

    var body: some View {
        Canvas { context, size in
            guard let landmarks = frame.landmarks else { return }

            let palm = convert(landmarks.palmCenter, in: size)
            let indexTip = convert(landmarks.indexTip, in: size)

            var path = Path()
            path.move(to: palm)
            path.addLine(to: indexTip)
            context.stroke(path, with: .color(.blue.opacity(0.6)), lineWidth: 2)

            draw(point: landmarks.thumbTip, color: .orange, radius: 4, in: size, context: &context)
            draw(point: landmarks.indexTip, color: .blue, radius: 6, in: size, context: &context)
            draw(point: landmarks.middleTip, color: .green, radius: 4, in: size, context: &context)
            draw(point: landmarks.ringTip, color: .green, radius: 4, in: size, context: &context)
            draw(point: landmarks.littleTip, color: .pink, radius: 5, in: size, context: &context)
            draw(point: landmarks.palmCenter, color: .yellow, radius: 4, in: size, context: &context)
        }
        .allowsHitTesting(false)
    }

    private func draw(point: CGPoint, color: Color, radius: CGFloat, in size: CGSize, context: inout GraphicsContext) {
        let mapped = convert(point, in: size)
        let rect = CGRect(x: mapped.x - radius, y: mapped.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .color(color))
    }

    private func convert(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: point.x * size.width,
            y: (1 - point.y) * size.height
        )
    }
}
