import SwiftUI
import UIKit

// MARK: - TouchDownTapArea
// Fires the instant a finger lands (touchesBegan), not when it lifts like a
// SwiftUI Button. Passes the UITouch timestamp (CACurrentMediaTime clock, same
// as CADisplayLink) so the game can score the exact moment of contact.
//
// Accessibility: exposed as a button labelled `accessibilityLabel` so VoiceOver,
// Switch Control and XCUITest (`app.buttons["TAP!"]`) keep working.

struct TouchDownTapArea<Content: View>: View {
    let accessibilityLabel: String
    let onTouchDown: (CFTimeInterval) -> Void
    @ViewBuilder let content: () -> Content

    @State private var isPressed = false

    var body: some View {
        content()
            .scaleEffect(isPressed ? 0.94 : 1.0)
            .opacity(isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .overlay(
                TouchDownCatcher(
                    accessibilityLabel: accessibilityLabel,
                    onTouchDown: onTouchDown,
                    onPressChanged: { isPressed = $0 }
                )
            )
    }
}

private struct TouchDownCatcher: UIViewRepresentable {
    let accessibilityLabel: String
    let onTouchDown: (CFTimeInterval) -> Void
    let onPressChanged: (Bool) -> Void

    func makeUIView(context: Context) -> TouchDownView {
        let view = TouchDownView()
        view.backgroundColor = .clear
        // One finger = one tap: a second simultaneous finger used to score twice.
        view.isMultipleTouchEnabled = false
        view.isAccessibilityElement = true
        view.accessibilityTraits = .button
        update(view)
        return view
    }

    func updateUIView(_ view: TouchDownView, context: Context) {
        update(view)
    }

    private func update(_ view: TouchDownView) {
        view.accessibilityLabel = accessibilityLabel
        view.onTouchDown = onTouchDown
        view.onPressChanged = onPressChanged
    }
}

final class TouchDownView: UIView {
    var onTouchDown: ((CFTimeInterval) -> Void)?
    var onPressChanged: ((Bool) -> Void)?
    private var activeTouches = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // One tap per new finger, each scored at its own contact time.
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            onTouchDown?(touch.timestamp)
        }
        activeTouches += touches.count
        onPressChanged?(true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        release(touches.count)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        release(touches.count)
    }

    private func release(_ count: Int) {
        activeTouches = max(0, activeTouches - count)
        if activeTouches == 0 { onPressChanged?(false) }
    }

    // VoiceOver double-tap / Switch Control activation.
    override func accessibilityActivate() -> Bool {
        onTouchDown?(CACurrentMediaTime())
        return true
    }
}
