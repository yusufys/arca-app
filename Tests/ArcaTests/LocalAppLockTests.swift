import XCTest
@testable import ArcaUI

@MainActor
final class LocalAppLockTests: XCTestCase {
    func testEnablingPersistsAndRelaunchRequiresAuthentication() async throws {
        let suite = "ArcaLockTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let lock = LocalAppLock(defaults: defaults, authenticate: { _ in true })
        await lock.setEnabled(true)
        XCTAssertTrue(lock.enabled)
        XCTAssertFalse(lock.isLocked)
        let relaunched = LocalAppLock(defaults: defaults, authenticate: { _ in false })
        XCTAssertTrue(relaunched.enabled)
        XCTAssertTrue(relaunched.isLocked)
        await relaunched.unlock()
        XCTAssertTrue(relaunched.isLocked, "A failed prompt must leave records locked")
        await relaunched.setEnabled(false)
        XCTAssertTrue(relaunched.enabled, "Disabling App Lock also requires authentication")
    }

    func testBackgroundRelocksAndSuccessfulAuthenticationUnlocks() async throws {
        let suite = "ArcaLockTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let lock = LocalAppLock(defaults: defaults, authenticate: { _ in true })
        await lock.setEnabled(true)
        lock.enteredBackground()
        XCTAssertTrue(lock.isLocked)
        await lock.unlock()
        XCTAssertTrue(lock.isLocked, "Background authentication must be refused")
        lock.becameActive()
        await lock.unlock()
        XCTAssertFalse(lock.isLocked)
    }

    func testBackgroundInvalidatesAuthenticationAlreadyInFlight() async throws {
        let suite = "ArcaLockTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "arca.appLock.enabled")
        var continuation: CheckedContinuation<Bool, Never>?
        let lock = LocalAppLock(defaults: defaults, authenticate: { _ in
            await withCheckedContinuation { continuation = $0 }
        })
        let task = Task { await lock.unlock() }
        while continuation == nil { await Task.yield() }
        lock.enteredBackground()
        lock.becameActive()
        continuation?.resume(returning: true)
        await task.value
        XCTAssertTrue(lock.isLocked, "A stale successful prompt cannot unlock after backgrounding")
    }
}
