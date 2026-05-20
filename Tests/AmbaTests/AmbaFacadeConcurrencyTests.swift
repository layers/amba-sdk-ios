//
//  AmbaFacadeConcurrencyTests.swift
//
//  Concurrency tests for the static `Amba` facade's lock guarding
//  the singleton slot (item #13 / C-4).
//
//  Pre-fix the slot was `nonisolated(unsafe) static var` — Swift's
//  strict concurrency checker tolerated it but concurrent
//  configure-vs-read crashed under load in practice. Post-fix the
//  slot is NSLock-guarded + `configure(...)` is single-write
//  (throws `.alreadyConfigured` on second call without an
//  intervening `reset()`).
//
//  These tests use `Amba._installForTesting(...)` — an internal
//  install-when-empty helper — to exercise the lock semantics
//  without going through `AmbaClient(apiKey:...)` (which would
//  hit the Rust core's own single-init guard and dominate the
//  test as a confounding variable).
//

import XCTest
@testable import Amba

final class AmbaFacadeConcurrencyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Each test starts from a clean facade state.
        Amba.reset()
    }

    override func tearDown() {
        Amba.reset()
        super.tearDown()
    }

    private func makeClient() -> AmbaClient {
        AmbaClient(core: MockAmbaCore())
    }

    // 1. Single-thread baseline: install once → success, install again →
    //    .alreadyConfigured. Sanity-check the lock + check semantics
    //    before exercising concurrency.
    func testSingleThreadInstallThenInstallThrowsAlreadyConfigured() throws {
        let c1 = makeClient()
        try Amba._installForTesting(c1)
        XCTAssertTrue(Amba.isConfigured)

        XCTAssertThrowsError(try Amba._installForTesting(makeClient())) { err in
            XCTAssertEqual(err as? AmbaSwiftError, .alreadyConfigured)
        }
    }

    // 2. reset clears the slot and a subsequent install succeeds.
    func testResetClearsAndAllowsReInstall() throws {
        try Amba._installForTesting(makeClient())
        XCTAssertTrue(Amba.isConfigured)

        Amba.reset()
        XCTAssertFalse(Amba.isConfigured)

        try Amba._installForTesting(makeClient())
        XCTAssertTrue(Amba.isConfigured)
    }

    // 3. THE main lock-race test: 100 tasks race to install
    //    simultaneously (per team-lead's Cycle 0 R2 spec).
    //    Exactly 1 succeeds, 99 throw .alreadyConfigured.
    //    Pre-fix this would have:
    //      - Either silently let multiple installs through (UB), or
    //      - Crashed reading sharedClient mid-write (torn reference).
    func testHundredConcurrentInstallsExactlyOneWins() async throws {
        let attempts = 100
        let successes = ManagedAtomicInt()
        let alreadyConfigured = ManagedAtomicInt()
        let otherErrors = ManagedAtomicInt()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<attempts {
                group.addTask {
                    let c = AmbaClient(core: MockAmbaCore())
                    do {
                        try Amba._installForTesting(c)
                        successes.increment()
                    } catch AmbaSwiftError.alreadyConfigured {
                        alreadyConfigured.increment()
                    } catch {
                        otherErrors.increment()
                    }
                }
            }
        }

        XCTAssertEqual(successes.value, 1, "exactly one install must win the race")
        XCTAssertEqual(alreadyConfigured.value, attempts - 1, "every loser must see .alreadyConfigured (not torn read / crash)")
        XCTAssertEqual(otherErrors.value, 0, "no spurious errors")
        XCTAssertTrue(Amba.isConfigured, "facade ends up configured")
    }

    // 4. Many concurrent reads during/after configure don't crash and
    //    see a consistent view.
    //    Strategy: install one client, then spawn 100 tasks each
    //    reading `Amba.anonymousId` / `Amba.appUserId` /
    //    `Amba.isAuthenticated` in a tight loop. With the lock
    //    correctly held, every read either sees nil-before-install or
    //    the installed client — never a torn reference.
    func testHundredConcurrentReadsAfterInstallDoNotCrash() async throws {
        let mock = MockAmbaCore()
        mock.anonId = "stable-anon-id"
        mock.appUid = "stable-app-uid"
        mock.authed = true
        try Amba._installForTesting(AmbaClient(core: mock))

        let readers = 100
        let iterations = 50
        let consistentReads = ManagedAtomicInt()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<readers {
                group.addTask {
                    for _ in 0..<iterations {
                        // Three reads back-to-back — if the slot got
                        // torn or cleared mid-flight any of these
                        // could nil-deref. The test passes if no
                        // crash happens; we also assert each read's
                        // value matches the installed mock to catch
                        // accidental nil returns.
                        let anon = Amba.anonymousId
                        let uid = Amba.appUserId
                        let auth = Amba.isAuthenticated
                        if anon == "stable-anon-id"
                            && uid == "stable-app-uid"
                            && auth == true {
                            consistentReads.increment()
                        }
                    }
                }
            }
        }

        XCTAssertEqual(consistentReads.value, readers * iterations,
                       "every read after install must see the installed client's values")
    }

    // 5. Reads racing with reset (the trickiest case): reset clears
    //    sharedClient → nil. Concurrent reads must see either the
    //    pre-reset client or nil — never a torn reference / crash.
    //    Without the lock this would crash on some architectures
    //    because the class-reference write isn't atomic.
    func testConcurrentReadsRacingWithResetDoNotCrash() async throws {
        try Amba._installForTesting(makeClient())
        let readers = 50
        let iterations = 100
        let safeReads = ManagedAtomicInt()

        await withTaskGroup(of: Void.self) { group in
            // Reader tasks
            for _ in 0..<readers {
                group.addTask {
                    for _ in 0..<iterations {
                        // Read shouldn't crash whether slot is set or nil.
                        _ = Amba.anonymousId
                        _ = Amba.isConfigured
                        safeReads.increment()
                    }
                }
            }
            // Single writer task that resets + re-installs in a loop,
            // concurrent with the readers above.
            group.addTask {
                for _ in 0..<10 {
                    Amba.reset()
                    _ = try? Amba._installForTesting(AmbaClient(core: MockAmbaCore()))
                    // Yield so readers get scheduled between mutations.
                    await Task.yield()
                }
            }
        }

        XCTAssertEqual(safeReads.value, readers * iterations,
                       "every read during reset/install storm completed without crashing")
    }

    // 6. configure(apiKey: "") still validates apiKey before touching
    //    the lock — the .invalidConfig fast-path is preserved by the
    //    AmbaClient constructor, so a malformed configure attempt
    //    doesn't even reach the slot.
    func testInvalidConfigStillRejectedAndDoesNotInstallAnything() {
        XCTAssertThrowsError(try Amba.configure(apiKey: "")) { err in
            guard case AmbaSwiftError.invalidConfig = err else {
                XCTFail("expected invalidConfig, got \(err)")
                return
            }
        }
        XCTAssertFalse(Amba.isConfigured, "failed configure must not install anything")
    }
}

// MARK: - ManagedAtomicInt (minimal stand-in)
//
// XCTest doesn't ship with `Atomics`. For these tests we just need
// concurrent increments and a final read. A serial DispatchQueue
// gives the same guarantee without pulling in a third-party dep
// and works on every Apple platform we target.
final class ManagedAtomicInt: @unchecked Sendable {
    private var _value: Int = 0
    private let lock = NSLock()

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func increment() {
        lock.lock()
        _value += 1
        lock.unlock()
    }
}
