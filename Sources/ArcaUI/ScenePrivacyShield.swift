#if os(iOS)
import SwiftUI
import UIKit

/// Covers the entire window, including sheets, before app-switcher snapshots.
@available(iOS 17.0, *)
struct ScenePrivacyShield: UIViewRepresentable {
    func makeUIView(context: Context) -> ShieldAnchor { ShieldAnchor() }
    func updateUIView(_ uiView: ShieldAnchor, context: Context) {}

    final class ShieldAnchor: UIView {
        private var observers: [NSObjectProtocol] = []
        private var cover: UIView?
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.showCover() }
            })
            observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if self?.window?.windowScene?.activationState == .foregroundActive { self?.removeCover() }
                }
            })
            observers.append(center.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    if let scene = notification.object as? UIWindowScene, self?.window?.windowScene === scene { self?.showCover() }
                }
            })
            observers.append(center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    if let scene = notification.object as? UIWindowScene, self?.window?.windowScene === scene { self?.removeCover() }
                }
            })
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { removeCover() }
            else if window?.windowScene?.activationState != .foregroundActive { showCover() }
        }
        private func showCover() {
            guard cover == nil, let window else { return }
            let shield = UIView(frame: window.bounds)
            shield.backgroundColor = .systemBackground
            shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            let label = UILabel()
            label.text = "Arca"
            label.font = .preferredFont(forTextStyle: .largeTitle)
            label.translatesAutoresizingMaskIntoConstraints = false
            shield.addSubview(label)
            NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: shield.centerXAnchor), label.centerYAnchor.constraint(equalTo: shield.centerYAnchor)])
            window.addSubview(shield)
            cover = shield
        }
        private func removeCover() { cover?.removeFromSuperview(); cover = nil }
    }
}
#endif
