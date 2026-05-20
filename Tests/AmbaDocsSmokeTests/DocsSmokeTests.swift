//
//  DocsSmokeTests.swift
//
//  Customer-shoes exercise for apps/docs/content/docs/sdk/swift.mdx
//  (Phase B of customer-smoke-docs).
//
//  This is the Swift counterpart to e2e/docs/exercise-{web,node,react,
//  react-native,expo}.mjs. It reads PRE-MINTED credentials from env
//  (AMBA_API_KEY + AMBA_API_URL exported by sdks/e2e/lib/bootstrap.sh)
//  and runs the docs quickstart's 4-step journey end-to-end:
//
//    §2 Configure                 → Amba.configure(apiKey:baseUrl:)
//    §3 First auth                → Amba.auth.signInAnonymously()
//    §4 First event               → Amba.events.track(...)
//    §5 First collection insert   → Amba.collections.insert("posts", row: …)
//
//  The bash bootstrap already:
//    1. Signed up a fresh dev tenant + minted PAT/client_key/project_id
//    2. Polled provisioning_status=active
//    3. Provisioned the `posts` collection via docs-fixtures.sh
//    4. Installed an EXIT trap that DELETEs the tenant on every exit
//
//  This Swift test does NOT re-do signup/cleanup. It's the pure SDK
//  journey, fail-closed on any non-2xx — exit code propagates back to
//  the orchestrator which reports PASS/FAIL per language.
//
//  Skipped (XCTSkip) when AMBA_API_KEY / AMBA_API_URL aren't set, so
//  `swift test` without env still passes cleanly. CI invokes via:
//    swift test --filter AmbaDocsSmokeTests
//
//  This file deliberately mirrors the structure of
//  Tests/AmbaIntegrationTests/SmokeTests.swift but trims out the
//  signup/cleanup/comprehensive-surface bits, since this gate exists
//  to enforce that the published docs work — not to assert every SDK
//  surface still works on staging.

import XCTest
@testable import Amba

final class DocsSmokeTests: XCTestCase {
    /// One sequential customer journey. Like the broader integration
    /// smoke, splitting into many tiny tests would either share global
    /// state or burn through fresh tenants on every step — both bad.
    func testDocsCustomerJourney() async throws {
        guard let baseUrl = Self.env("AMBA_API_URL"), !baseUrl.isEmpty else {
            throw XCTSkip(
                "AMBA_API_URL not set — skipping. The orchestrator at " +
                "e2e/customer-smoke-docs.sh exports both AMBA_API_URL and " +
                "AMBA_API_KEY from the bash bootstrap before running this."
            )
        }
        guard let apiKey = Self.env("AMBA_API_KEY"), !apiKey.isEmpty else {
            throw XCTSkip(
                "AMBA_API_KEY not set — orchestrator did not export the " +
                "freshly-minted client_key. This shouldn't happen in CI; " +
                "if you see it, check sdks/e2e/lib/bootstrap.sh."
            )
        }

        let runId = Self.env("GITHUB_RUN_ID") ?? "local"
        let tag = "docs-swift-\(runId)-\(Int(Date().timeIntervalSince1970))"

        // ── §2 Configure ────────────────────────────────────────────
        try Amba.configure(apiKey: apiKey, baseUrl: baseUrl)
        let anonId = Amba.anonymousId ?? ""
        XCTAssertFalse(anonId.isEmpty, "Amba.anonymousId should be present after configure")
        XCTAssertGreaterThanOrEqual(anonId.count, 16, "anonymousId should look uuid-ish, got: \(anonId)")
        XCTAssertFalse(Amba.isAuthenticated, "isAuthenticated should be false before signIn")
        XCTAssertNil(Amba.appUserId, "appUserId should be nil before signIn")
        log("✓ configure: anonymousId=\(anonId.prefix(12))…")

        // ── §3 First auth ──────────────────────────────────────────
        let auth = try await Amba.auth.signInAnonymously()
        XCTAssertFalse(auth.sessionToken.isEmpty, "session_token should be non-empty")
        XCTAssertFalse(auth.user.id.isEmpty, "user.id should be non-empty")
        XCTAssertTrue(Amba.isAuthenticated, "isAuthenticated should flip true after signIn")
        XCTAssertEqual(Amba.appUserId, auth.user.id, "appUserId should match session user.id")
        log("✓ signInAnonymously: user=\(auth.user.id)")

        // ── §4 First event ─────────────────────────────────────────
        try await Amba.events.track("app_opened", properties: [
            "source": "swift",
            "smoke_tag": tag,
        ])
        log("✓ events.track")

        // ── §5 First collection insert (into the `posts` collection
        //     provisioned by docs-fixtures.sh) ─────────────────────
        struct Post: Decodable {
            let id: String
            let title: String
            let body: String
        }
        let inserted: Post = try await Amba.collections.insert(
            "posts",
            row: [
                "title": "Hello amba from Swift",
                "body": "My first post from a Swift app.",
            ],
            as: Post.self
        )
        XCTAssertFalse(inserted.id.isEmpty, "insert returned an empty id")
        XCTAssertEqual(inserted.title, "Hello amba from Swift", "insert.title round-trip")
        XCTAssertEqual(inserted.body, "My first post from a Swift app.", "insert.body round-trip")
        log("✓ collections.insert('posts'): id=\(inserted.id)")

        log("✅ swift docs smoke PASS")
    }

    // MARK: - Helpers

    private static func env(_ name: String) -> String? {
        let v = ProcessInfo.processInfo.environment[name]
        return (v?.isEmpty ?? true) ? nil : v
    }

    private func log(_ msg: String) {
        FileHandle.standardError.write(Data("[docs-smoke] \(msg)\n".utf8))
    }
}
