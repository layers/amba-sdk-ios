//
//  SmokeTests.swift
//
//  Customer-shoes smoke for the Swift SDK. Same agentic flow as the
//  TS smokes in `e2e/exercise/*.mjs`, written in idiomatic Swift +
//  XCTest, runs against staging in CI on macos-latest.
//
//  Flow per CLAUDE.md Rule 1 ("real customer journey from clean shell"):
//
//   1. URLSession POST /v1/auth/developer/signup with unique email
//      → capture PAT, project_id, client_key
//   2. Poll /v1/admin/projects/<id> until provisioning_status=active
//   3. Amba.configure(apiKey: client_key, baseUrl: AMBA_API_URL)
//   4. Exercise every namespace that's known-working on staging today
//      (see "deliberately omitted" list at the end of this file —
//      surfaces gated on items #15 + #16 get added when those land)
//   5. Cleanup: DELETE /v1/admin/projects/<id> via PAT
//
//  Requires env: AMBA_API_URL. Skipped (not failed) when unset so
//  local `swift test` runs without it pass cleanly.
//

import XCTest
@testable import Amba

final class SmokeTests: XCTestCase {
    private var bootstrap: Bootstrap?

    override func tearDown() async throws {
        if let b = bootstrap {
            // Best-effort cleanup — fire and don't fail the suite on
            // teardown errors. Staging has a sweeper for orphaned
            // agent_sandbox projects.
            await b.cleanup()
            bootstrap = nil
        }
        try await super.tearDown()
    }

    /// One big customer journey. Per Item-10a brief: single XCTest method,
    /// hard-fails on any assertion mismatch. Splitting into many tiny
    /// tests would re-bootstrap a fresh tenant on every step, which is
    /// both slow and pointless — the customer flow is inherently
    /// sequential.
    func testCustomerJourney() async throws {
        guard let baseUrl = Self.env("AMBA_API_URL"), !baseUrl.isEmpty else {
            throw XCTSkip("AMBA_API_URL not set — skipping. Run locally with: AMBA_API_URL=<staging> swift test --filter AmbaIntegrationTests")
        }

        // 1. Sign up a fresh dev tenant. Holds creds for cleanup.
        let b = try await Bootstrap.signup(baseUrl: baseUrl)
        bootstrap = b
        log("✓ signup: project=\(b.projectId) client_key=\(b.clientKey.prefix(14))…")

        // 2. Configure SDK against this tenant.
        try Amba.configure(apiKey: b.clientKey, baseUrl: baseUrl)
        // Before any auth call: anonymousId is a stable UUID-shaped
        // string seeded on first SDK use.
        let anonId = Amba.anonymousId ?? ""
        XCTAssertFalse(anonId.isEmpty, "Amba.anonymousId should be present after configure")
        XCTAssertTrue(anonId.count >= 16, "anonymousId should look uuid-ish, got: \(anonId)")
        XCTAssertFalse(Amba.isAuthenticated, "isAuthenticated should be false before signIn")
        XCTAssertNil(Amba.appUserId, "appUserId should be nil before signIn")
        log("✓ configure: anonymousId=\(anonId.prefix(12))…")

        // 3. auth.signInAnonymously — should mint a session.
        let auth = try await Amba.auth.signInAnonymously()
        XCTAssertFalse(auth.sessionToken.isEmpty, "session_token should be non-empty")
        XCTAssertFalse(auth.refreshToken.isEmpty, "refresh_token should be non-empty")
        XCTAssertFalse(auth.user.id.isEmpty, "user.id should be non-empty")
        XCTAssertTrue(Amba.isAuthenticated, "isAuthenticated should flip true after signIn")
        XCTAssertEqual(Amba.appUserId, auth.user.id, "appUserId should match session user.id")
        log("✓ signInAnonymously: user=\(auth.user.id)")

        // 4. events.track (authenticated). The server's /v1/client/events
        //    is under clientSessionAuth — without the Bearer token from
        //    signIn it 401s. We exercised signIn just now so this must
        //    succeed; the post-signOut step below also verifies the
        //    inverse.
        try await Amba.events.track("swift_smoke_started", properties: [
            "run_id": b.runId,
            "sdk": "swift",
            "tag": "\(b.runId)-\(Int(Date().timeIntervalSince1970))",
        ])
        log("✓ events.track (authenticated)")

        // 5. events.track with no properties — must also succeed.
        try await Amba.events.track("swift_smoke_no_props")
        log("✓ events.track (no properties)")

        // 6. entitlements.list — fresh tenant returns empty array but
        //    the call must succeed (route exists, auth check passes).
        let entitlements = try await Amba.entitlements.list()
        // The shape itself is enough — the type is [UserEntitlementFfi];
        // an empty list is the expected default on a brand-new project.
        log("✓ entitlements.list (count=\(entitlements.count))")

        // 7. entitlements.has (unknown) — must return false, not throw.
        let hasUnknown = await Amba.entitlements.has("__smoke_unknown__")
        XCTAssertFalse(hasUnknown, "has('__smoke_unknown__') must be false on fresh tenant")
        log("✓ entitlements.has (unknown=false)")

        // 8. config.fetch — post-#12 fix this returns a flat values map
        //    + nullable version (from the response's ETag header).
        let bundle = try await Amba.config.fetch()
        XCTAssertFalse(bundle.values.value is NSNull, "config.values must be present (non-null)")
        if let v = bundle.version {
            XCTAssertFalse(v.isEmpty, "if version is set it must be non-empty, got: \(v)")
        }
        log("✓ config.fetch (version=\(bundle.version ?? "nil"))")

        // 9. auth.signOut — clears the session.
        try await Amba.auth.signOut()
        XCTAssertFalse(Amba.isAuthenticated, "isAuthenticated should flip false after signOut")
        log("✓ signOut")

        // 10. Post-signOut: events.track MUST fail with an auth-related
        //     error. Without this we can't be sure the SDK state
        //     machine actually cleared the session — we'd just be
        //     trusting `isAuthenticated == false` to be load-bearing.
        var threwAuth = false
        var errMsg = ""
        do {
            try await Amba.events.track("swift_smoke_should_not_send")
        } catch {
            threwAuth = true
            errMsg = "\(error)".lowercased()
        }
        XCTAssertTrue(threwAuth, "events.track after signOut should throw, got success")
        let looksLikeAuthError = errMsg.contains("unauth")
            || errMsg.contains("401")
            || errMsg.contains("session")
            || errMsg.contains("missing.*authorization")
        XCTAssertTrue(looksLikeAuthError, "expected auth-related error, got: \(errMsg)")
        log("✓ events.track after signOut threw (auth-related: \(errMsg.prefix(80))…)")

        log("✅ swift smoke PASS")

        // Deliberately NOT exercised here (same omission list as
        // e2e/exercise/web.mjs — gated on items #15 + #16):
        //   - auth.me            — server route mismatch, item #15
        //   - push.register      — server route mismatch, item #15
        //   - push.subscribe     — no server route
        //   - storage.upload     — different presign protocol, item #15
        //   - collections.*      — needs fixture schema, item #16
        //   - ai.anthropic.messages.create — needs fixture prompt slug, item #16
        //   - flags.fetch        — no /v1/client/flags route
        //
        // When those land, restore the corresponding XCTAssert blocks.
    }

    // MARK: - Helpers

    private static func env(_ name: String) -> String? {
        let v = ProcessInfo.processInfo.environment[name]
        return (v?.isEmpty ?? true) ? nil : v
    }

    private func log(_ msg: String) {
        // FileHandle so output isn't swallowed by XCTest's stdout buffer.
        FileHandle.standardError.write(Data("[smoke] \(msg)\n".utf8))
    }
}

// MARK: - Bootstrap (raw URLSession; not part of public Amba SDK)

/// Holds credentials for a freshly-signed-up dev tenant. The
/// signup + provisioning-wait + cleanup live here as plain
/// URLSession calls — we deliberately don't reuse the Amba SDK
/// for the admin-plane bootstrap so an SDK bug can't mask a
/// signup-flow regression.
struct Bootstrap {
    let baseUrl: String
    let pat: String
    let projectId: String
    let clientKey: String
    let runId: String

    static func signup(baseUrl: String) async throws -> Bootstrap {
        let runId = ProcessInfo.processInfo.environment["GITHUB_RUN_ID"] ?? "local"
        let attempt = ProcessInfo.processInfo.environment["GITHUB_RUN_ATTEMPT"] ?? "1"
        let epoch = Int(Date().timeIntervalSince1970)
        // RANDOM-equivalent: 0...100000. Same hedging as the bash
        // bootstrap — guards against same-second re-runs colliding.
        let rand = Int.random(in: 0...100_000)
        let email = "smoke-swift-\(runId)-\(attempt)-\(epoch)-\(rand)@layers.com"
        let password = "smoke-\(UUID().uuidString)"
        let name = "swift-smoke-\(runId)"

        // POST signup
        var signupReq = URLRequest(url: URL(string: "\(baseUrl)/v1/auth/developer/signup")!)
        signupReq.httpMethod = "POST"
        signupReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        signupReq.httpBody = try JSONSerialization.data(
            withJSONObject: ["email": email, "password": password, "name": name],
            options: []
        )
        let (signupData, signupResp) = try await URLSession.shared.data(for: signupReq)
        try assert2xx(signupResp, body: signupData, context: "signup")

        guard let parsed = try JSONSerialization.jsonObject(with: signupData) as? [String: Any],
              let data = parsed["data"] as? [String: Any],
              let project = data["project"] as? [String: Any],
              let pat = data["pat"] as? String,
              let projectId = project["project_id"] as? String,
              let clientKey = project["client_key"] as? String
        else {
            let preview = String(data: signupData, encoding: .utf8) ?? "<binary>"
            throw NSError(domain: "Bootstrap", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "signup response missing pat/project_id/client_key. Body: \(preview)"
            ])
        }

        // Poll provisioning_status until active (5-min deadline).
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline {
            var statusReq = URLRequest(url: URL(string: "\(baseUrl)/v1/admin/projects/\(projectId)")!)
            statusReq.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
            let (sData, sResp) = try await URLSession.shared.data(for: statusReq)
            if let sHttp = sResp as? HTTPURLResponse, (200..<300).contains(sHttp.statusCode) {
                let sJson = try JSONSerialization.jsonObject(with: sData) as? [String: Any]
                let sData2 = sJson?["data"] as? [String: Any]
                let status = sData2?["provisioning_status"] as? String
                    ?? sData2?["status"] as? String
                    ?? "unknown"
                if status == "active" {
                    return Bootstrap(baseUrl: baseUrl, pat: pat, projectId: projectId, clientKey: clientKey, runId: runId)
                }
                if status == "failed" {
                    throw NSError(domain: "Bootstrap", code: 3, userInfo: [
                        NSLocalizedDescriptionKey: "provisioning_status=failed for project \(projectId)"
                    ])
                }
            }
            // 5s between polls (matches bash bootstrap)
            try await Task.sleep(nanoseconds: 5_000_000_000)
        }
        throw NSError(domain: "Bootstrap", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "provisioning did not reach 'active' within 5 min for project \(projectId)"
        ])
    }

    func cleanup() async {
        var req = URLRequest(url: URL(string: "\(baseUrl)/v1/admin/projects/\(projectId)")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        // Best-effort. If the delete fails the tenant lingers and the
        // staging sweeper picks it up — we don't fail the test on
        // cleanup errors because the customer journey itself already
        // either passed or failed by this point.
        _ = try? await URLSession.shared.data(for: req)
    }

    private static func assert2xx(_ response: URLResponse, body: Data, context: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Bootstrap", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "\(context): non-HTTP response"
            ])
        }
        if !(200..<300).contains(http.statusCode) {
            let preview = String(data: body, encoding: .utf8) ?? "<binary>"
            throw NSError(domain: "Bootstrap", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "\(context) failed with status \(http.statusCode). Body: \(preview)"
            ])
        }
    }
}
