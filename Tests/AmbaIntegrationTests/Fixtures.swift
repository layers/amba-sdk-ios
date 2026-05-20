//
//  Fixtures.swift — Smoke fixture loader, Swift companion to the
//  per-run fixture provisioning that `e2e/lib/bootstrap.sh` performs
//  as task #16. Symmetric to:
//    - flutter/integration_test/lib/fixtures.dart
//    - unity/Tests/Integration/Fixtures.cs
//    - kotlin/.../SmokeFixtures.kt
//
//  bootstrap.sh provisions per-run fixtures (a collection schema and
//  an AI prompt — plus optionally a storage bucket) and exports the
//  resulting IDs/names via env vars. This file reads them on the
//  Swift side so smokes don't re-implement env parsing per language.
//
//  ── Behavior ────────────────────────────────────────────────────
//
//    AMBA_REQUIRE_FIXTURES unset or "0"
//      → returns `SmokeFixtures` with `nil` for any missing env vars.
//        Today's narrow smoke (no fixtures provisioned) uses this
//        mode.
//
//    AMBA_REQUIRE_FIXTURES=1
//      → throws `FixturesError.missingRequired(varName)`. The
//        expanded smoke (task #26, post-#16) flips this on so a
//        missing fixture is a loud failure, not a silent skip.
//
//  Env vars consumed (same set as Flutter/Unity/Kotlin):
//    - AMBA_SMOKE_COLLECTION_ID
//    - AMBA_SMOKE_COLLECTION_NAME
//    - AMBA_SMOKE_AI_PROMPT_ID
//    - AMBA_SMOKE_AI_PROMPT_KEY
//    - AMBA_SMOKE_STORAGE_BUCKET
//
//  ── Where it lives ──────────────────────────────────────────────
//
//  Under `Tests/AmbaIntegrationTests/` next to SmokeTests.swift.
//  The loader is pure env-parsing — no HTTP, no native lib, no
//  fixture data needed. The fixture LOADER unit tests in
//  `FixturesTests.swift` run as part of both `swift test` (default)
//  and `swift test --filter AmbaIntegrationTests` (CI smoke job).
//

import Foundation

/// Fixture handles provisioned by bootstrap.sh for the current
/// smoke run. Every field is optional so the loader can return a
/// partial struct when `AMBA_REQUIRE_FIXTURES` is not set (today's
/// narrow smoke). The expanded smoke checks `allPresent` before
/// reading individual fields.
public struct SmokeFixtures: Equatable {
    public let collectionId: String?
    public let collectionName: String?
    public let aiPromptId: String?
    public let aiPromptKey: String?
    public let storageBucket: String?

    public init(
        collectionId: String? = nil,
        collectionName: String? = nil,
        aiPromptId: String? = nil,
        aiPromptKey: String? = nil,
        storageBucket: String? = nil
    ) {
        self.collectionId = collectionId
        self.collectionName = collectionName
        self.aiPromptId = aiPromptId
        self.aiPromptKey = aiPromptKey
        self.storageBucket = storageBucket
    }

    /// `true` iff every fixture handle was provisioned and present
    /// in the env as a non-empty string. The expanded smoke gates
    /// its expanded surface paths on this so it can't half-run with
    /// three of five fixtures.
    ///
    /// Treats empty strings as missing (matches the loader's
    /// "empty == absent" rule) so direct struct construction
    /// stays consistent with the loader's behavior.
    public var allPresent: Bool {
        guard let cId = collectionId, !cId.isEmpty,
              let cN = collectionName, !cN.isEmpty,
              let pId = aiPromptId, !pId.isEmpty,
              let pK = aiPromptKey, !pK.isEmpty,
              let sB = storageBucket, !sB.isEmpty
        else { return false }
        return true
    }
}

/// Error raised when a fixture env var is missing while
/// `AMBA_REQUIRE_FIXTURES=1`. The `errorDescription` (and the
/// associated value) name the missing var and point at
/// bootstrap.sh so operators reading test output can grep to the
/// source in one hop.
public enum FixturesError: Error, Equatable, LocalizedError {
    case missingRequired(String)

    public var errorDescription: String? {
        switch self {
        case .missingRequired(let name):
            return "\(name) is required when AMBA_REQUIRE_FIXTURES=1 " +
                   "(provisioned by e2e/lib/bootstrap.sh after task #16 lands)"
        }
    }
}

/// Load fixture handles from the process env.
///
/// `env` is an injection seam for tests so they can pass a
/// synthetic map instead of mutating real process env (Swift's
/// `ProcessInfo.processInfo.environment` is a snapshot at process
/// start; you can't reassign it). Production callers omit `env`
/// and get the real environment.
public func loadSmokeFixtures(
    env: [String: String] = ProcessInfo.processInfo.environment
) throws -> SmokeFixtures {
    let require = env["AMBA_REQUIRE_FIXTURES"] == "1"

    func read(_ name: String) throws -> String? {
        let v = env[name]
        if let v = v, !v.isEmpty {
            return v
        }
        if require {
            // bootstrap.sh might also export `=""` if a provisioning
            // step failed silently. The loader treats empty the same
            // as absent so the smoke can't accidentally call API
            // endpoints with empty IDs.
            throw FixturesError.missingRequired(name)
        }
        return nil
    }

    return SmokeFixtures(
        collectionId: try read("AMBA_SMOKE_COLLECTION_ID"),
        collectionName: try read("AMBA_SMOKE_COLLECTION_NAME"),
        aiPromptId: try read("AMBA_SMOKE_AI_PROMPT_ID"),
        aiPromptKey: try read("AMBA_SMOKE_AI_PROMPT_KEY"),
        storageBucket: try read("AMBA_SMOKE_STORAGE_BUCKET")
    )
}
