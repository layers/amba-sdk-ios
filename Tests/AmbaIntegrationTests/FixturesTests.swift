//
//  FixturesTests.swift — Unit tests for the smoke fixture loader.
//
//  Pure env-parsing logic — no HTTP, no native lib, no fixture data
//  needed. Lives under `Tests/AmbaIntegrationTests/` next to
//  Fixtures.swift but unlike SmokeTests it runs cleanly in BOTH
//  `swift test` (default) and `swift test --filter
//  AmbaIntegrationTests` (CI smoke job) — no skip, no env required,
//  every test injects its own synthetic env map.
//
//  Mirrors `unity/Tests/Integration/FixturesTest.cs` test-for-test
//  to keep the cross-platform contract verifiable.
//

import XCTest
// Fixtures.swift lives in the same `AmbaIntegrationTests` test
// target — same-module visibility, no `@testable import` needed.

final class FixturesTests: XCTestCase {
    private func allEnv() -> [String: String] {
        [
            "AMBA_SMOKE_COLLECTION_ID": "coll_smoke_runs_123",
            "AMBA_SMOKE_COLLECTION_NAME": "smoke_runs",
            "AMBA_SMOKE_AI_PROMPT_ID": "prompt_smoke_abc",
            "AMBA_SMOKE_AI_PROMPT_KEY": "smoke-prompt",
            "AMBA_SMOKE_STORAGE_BUCKET": "smoke-bucket",
        ]
    }

    // ── AMBA_REQUIRE_FIXTURES unset / "0" — tolerant mode ────────

    func testLoadReturnsNilsWhenEnvEmpty() throws {
        let f = try loadSmokeFixtures(env: [:])
        XCTAssertNil(f.collectionId)
        XCTAssertNil(f.collectionName)
        XCTAssertNil(f.aiPromptId)
        XCTAssertNil(f.aiPromptKey)
        XCTAssertNil(f.storageBucket)
        XCTAssertFalse(f.allPresent)
    }

    func testLoadReturnsNilsWhenRequireFixturesIsZero() throws {
        // Explicit opt-out of strictness. No throw, even with no
        // other fixture vars present.
        let f = try loadSmokeFixtures(env: ["AMBA_REQUIRE_FIXTURES": "0"])
        XCTAssertFalse(f.allPresent)
    }

    func testLoadReadsPresentVarsLeavesMissingAsNil() throws {
        let f = try loadSmokeFixtures(env: [
            "AMBA_SMOKE_COLLECTION_ID": "coll_partial",
            // others omitted
        ])
        XCTAssertEqual(f.collectionId, "coll_partial")
        XCTAssertNil(f.collectionName)
        XCTAssertFalse(f.allPresent)
    }

    // ── AMBA_REQUIRE_FIXTURES=1 — strict mode ────────────────────

    func testLoadReturnsFullyPopulatedWhenAllEnvPresent() throws {
        var env = allEnv()
        env["AMBA_REQUIRE_FIXTURES"] = "1"

        let f = try loadSmokeFixtures(env: env)

        XCTAssertEqual(f.collectionId, "coll_smoke_runs_123")
        XCTAssertEqual(f.collectionName, "smoke_runs")
        XCTAssertEqual(f.aiPromptId, "prompt_smoke_abc")
        XCTAssertEqual(f.aiPromptKey, "smoke-prompt")
        XCTAssertEqual(f.storageBucket, "smoke-bucket")
        XCTAssertTrue(f.allPresent)
    }

    func testLoadThrowsWhenRequiredFieldMissingNamingTheVar() {
        var env = allEnv()
        env["AMBA_REQUIRE_FIXTURES"] = "1"
        env.removeValue(forKey: "AMBA_SMOKE_AI_PROMPT_KEY")

        XCTAssertThrowsError(try loadSmokeFixtures(env: env)) { err in
            guard case FixturesError.missingRequired(let name) = err else {
                XCTFail("expected .missingRequired, got \(err)")
                return
            }
            XCTAssertEqual(name, "AMBA_SMOKE_AI_PROMPT_KEY")
        }
    }

    func testLoadTreatsEmptyStringEnvVarAsMissing() {
        // bootstrap.sh might export `=""` if a provisioning step
        // failed silently. The loader treats empty the same as
        // absent so the smoke can't accidentally call API endpoints
        // with empty IDs.
        var env = allEnv()
        env["AMBA_REQUIRE_FIXTURES"] = "1"
        env["AMBA_SMOKE_COLLECTION_ID"] = ""

        XCTAssertThrowsError(try loadSmokeFixtures(env: env)) { err in
            guard case FixturesError.missingRequired(let name) = err else {
                XCTFail("expected .missingRequired, got \(err)")
                return
            }
            XCTAssertEqual(name, "AMBA_SMOKE_COLLECTION_ID")
        }
    }

    func testLoadErrorMessagePointsAtBootstrapSh() {
        // Operators reading the test output need to know where
        // these fixtures come from. Hard-code the path in the
        // error so debugging is one greppable hop.
        XCTAssertThrowsError(try loadSmokeFixtures(env: ["AMBA_REQUIRE_FIXTURES": "1"])) { err in
            let msg = (err as? LocalizedError)?.errorDescription ?? "\(err)"
            XCTAssertTrue(msg.contains("e2e/lib/bootstrap.sh"),
                          "error message should mention bootstrap.sh, got: \(msg)")
        }
    }

    // ── allPresent semantics ─────────────────────────────────────

    func testAllPresentFalseWhenAnyFieldIsNil() {
        let f = SmokeFixtures(
            collectionId: "a",
            collectionName: "b",
            aiPromptId: "c",
            aiPromptKey: "d",
            storageBucket: nil
        )
        XCTAssertFalse(f.allPresent)
    }

    func testAllPresentTrueOnlyWhenEveryFieldIsNonEmpty() {
        let f = SmokeFixtures(
            collectionId: "a",
            collectionName: "b",
            aiPromptId: "c",
            aiPromptKey: "d",
            storageBucket: "e"
        )
        XCTAssertTrue(f.allPresent)
    }

    func testAllPresentFalseWhenAnyFieldIsEmptyString() {
        // Matches the loader's "empty == missing" semantic above.
        let f = SmokeFixtures(
            collectionId: "a",
            collectionName: "b",
            aiPromptId: "c",
            aiPromptKey: "d",
            storageBucket: ""
        )
        XCTAssertFalse(f.allPresent)
    }
}
