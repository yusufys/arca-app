import SwiftUI

#if os(iOS)
import UIKit

/// A non-consuming tap recognizer dismisses the keyboard outside editable controls.
/// Attaching to the current window also covers sheets without changing their gestures.
struct KeyboardDismissal: UIViewRepresentable {
    func makeUIView(context: Context) -> DismissalView { DismissalView() }
    func updateUIView(_ uiView: DismissalView, context: Context) {}

    final class DismissalView: UIView, UIGestureRecognizerDelegate {
        private weak var installedWindow: UIWindow?
        private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))

        override func didMoveToWindow() {
            super.didMoveToWindow()
            installedWindow?.removeGestureRecognizer(tap)
            installedWindow = window
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window?.addGestureRecognizer(tap)
        }

        @objc private func dismissKeyboard() { installedWindow?.endEditing(true) }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                // Preserve cursor placement, selection, and moving between inputs.
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}
#endif
