import Foundation
import Observation
import LocalAuthentication

/// Device authentication gates access. A failed or interrupted prompt never unlocks the app.
@available(macOS 14.0, iOS 17.0, *)
@MainActor
@Observable
public final class LocalAppLock {
    public private(set) var enabled: Bool
    public private(set) var isLocked: Bool
    public private(set) var isAuthenticating = false
    public private(set) var errorMessage: String?
    private let defaults: UserDefaults
    private let preferenceKey: String
    private let authenticate: @MainActor (String) async throws -> Bool
    private var authenticationGeneration = 0
    private var isInBackground = false

    public init(defaults: UserDefaults = .standard, preferenceKey: String = "arca.appLock.enabled",
                authenticate: (@MainActor (String) async throws -> Bool)? = nil) {
        self.defaults = defaults
        self.preferenceKey = preferenceKey
        self.enabled = defaults.bool(forKey: preferenceKey)
        self.isLocked = defaults.bool(forKey: preferenceKey)
        self.authenticate = authenticate ?? { reason in
            let context = LAContext()
            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                throw error ?? NSError(domain: "ArcaAppLock", code: 1,
                                       userInfo: [NSLocalizedDescriptionKey: "Set a device passcode to use App Lock."])
            }
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        }
    }

    public func setEnabled(_ value: Bool) async {
        guard value != enabled, !isAuthenticating else { return }
        guard await verify(reason: value ? "Enable App Lock for your Arca records." : "Turn off Arca App Lock.") else { return }
        enabled = value
        isLocked = false
        defaults.set(value, forKey: preferenceKey)
    }

    public func unlock() async {
        guard enabled, isLocked, !isAuthenticating else { return }
        if await verify(reason: "Unlock your Arca records.") { isLocked = false }
    }

    public func enteredBackground() {
        isInBackground = true
        authenticationGeneration += 1
        if enabled { isLocked = true }
    }

    public func becameActive() { isInBackground = false }

    private func verify(reason: String) async -> Bool {
        guard !isInBackground else { return false }
        isAuthenticating = true
        errorMessage = nil
        let generation = authenticationGeneration
        defer { isAuthenticating = false }
        do {
            let passed = try await authenticate(reason)
            guard generation == authenticationGeneration, !isInBackground else { return false }
            if !passed { errorMessage = "Authentication did not complete. Try again." }
            return passed
        } catch {
            errorMessage = "Authentication did not complete. Unlock with your device credentials and try again."
            return false
        }
    }
}
