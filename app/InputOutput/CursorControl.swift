import Cocoa
import CoreGraphics
import ApplicationServices

final class CursorControl {
    private var paused: Bool = false
    private static var hasPromptedForAccessibility = false

    func setPaused(_ paused: Bool) {
        self.paused = paused
    }

    func requestAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        promptForAccessibility()
    }

    func moveCursor(to point: CGPoint) {
        guard !paused else { return }
        guard ensureAccessibilityPermission() else { return }
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
            Logger.permissions.error("Failed to create mouse move event")
            return
        }
        event.post(tap: CGEventTapLocation.cghidEventTap)
    }

    func click(type: GestureEvent, at location: CGPoint? = nil) {
        guard !paused else { return }
        guard ensureAccessibilityPermission() else { return }

        let targetLocation = location ?? NSEvent.mouseLocation

        switch type {
        case .leftClick:
            click(button: .left, downType: .leftMouseDown, upType: .leftMouseUp, at: targetLocation)
        case .rightClick:
            click(button: .right, downType: .rightMouseDown, upType: .rightMouseUp, at: targetLocation)
        case .dictationStart, .dictationStop:
            break
        case .swipe(_):
            break
        }
    }

    func performSwipe(_ direction: SwipeDirection) {
        guard !paused else { return }
        guard ensureAccessibilityPermission() else { return }

        let keyCode: CGKeyCode
        switch direction {
        case .left:
            keyCode = 0x7B
        case .right:
            keyCode = 0x7C
        case .down:
            keyCode = 0x7D
        case .up:
            keyCode = 0x7E
        }

        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let controlDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x3B), keyDown: true)
        controlDown?.post(tap: CGEventTapLocation.cghidEventTap)

        let controlUp: () -> Void = {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x3B), keyDown: false)
            event?.post(tap: CGEventTapLocation.cghidEventTap)
        }

        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = [.maskControl]
        down?.post(tap: CGEventTapLocation.cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = [.maskControl]
        up?.post(tap: CGEventTapLocation.cghidEventTap)

        controlUp()
    }

    func scroll(by delta: CGFloat) {
        guard !paused else { return }
        guard ensureAccessibilityPermission() else { return }

        let amount = Int32(delta.rounded())
        guard amount != 0 else { return }

        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: amount, wheel2: 0, wheel3: 0) {
            event.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }

    private func click(button: CGMouseButton, downType: CGEventType, upType: CGEventType, at location: CGPoint) {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: location, mouseButton: button),
              let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: location, mouseButton: button) else {
            Logger.permissions.error("Failed to create mouse click event")
            return
        }
        down.post(tap: CGEventTapLocation.cghidEventTap)
        up.post(tap: CGEventTapLocation.cghidEventTap)
    }

    private func ensureAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        Logger.permissions.error("Accessibility permission required to control the cursor.")

        promptForAccessibility()

        return false
    }

    private func promptForAccessibility() {
        guard !Self.hasPromptedForAccessibility else { return }
        Self.hasPromptedForAccessibility = true
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: CFDictionary = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
