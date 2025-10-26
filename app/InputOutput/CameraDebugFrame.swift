import CoreGraphics
import CoreMedia

struct CameraDebugFrame {
    let image: CGImage
    let landmarks: HandLandmarks?
    let timestamp: CMTime
}
