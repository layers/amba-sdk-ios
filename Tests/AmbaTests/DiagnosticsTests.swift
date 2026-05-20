//
//  DiagnosticsTests.swift
//
//  Coverage for `Amba.diagnostics.ping()` — added in v1.0.1.
//
//  Three round-trip cases against the wire shape the Rust core
//  surfaces (see `sdks/core/src/diagnostics.rs::PingResult`):
//
//      1. success — server returns ok:true with full envelope.
//      2. invalid key — Rust core surfaces a 401 as
//         `AmbaCoreError.Structured(status:401, code:"UNAUTHORIZED")`,
//         which the wrapper rethrows verbatim.
//      3. project not found — server returns 200 with ok:false and
//         a stable `error` code ("DIAGNOSTICS_PROJECT_NOT_FOUND").
//         The wrapper surfaces it as a structured `PingResult`,
//         NOT a throw — that path is reserved for transport/auth
//         failures (matches the Rust-side test
//         `ping_decodes_server_side_failure_envelope`).
//
//  Plus one wire-shape lock: snake_case fields on the wire decode
//  cleanly into camelCase Swift properties. Catches a future
//  serde rename on the Rust side that would silently break the
//  Swift decode path.
//

import XCTest
@testable import Amba

final class DiagnosticsTests: XCTestCase {
    var mock: MockAmbaCore!
    var client: AmbaClient!

    override func setUp() {
        super.setUp()
        mock = MockAmbaCore()
        client = AmbaClient(core: mock)
        AmbaDiagnosticsLog.lastEvent = nil
    }

    // 1. Happy path — full envelope round-trips through JSON decode.
    func testDiagnosticsPingDecodesSuccessEnvelope() async throws {
        mock.nextDiagnosticsPingJson = #"""
            {"ok":true,"server_project_id":"proj_abc123","environment":"sandbox","key_fingerprint":"4f8a","latency_ms":73,"error":null}
            """#
        let result = try await client.diagnosticsClient.ping()
        XCTAssertEqual(mock.diagnosticsPingCount, 1)
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.serverProjectId, "proj_abc123")
        XCTAssertEqual(result.environment, "sandbox")
        XCTAssertEqual(result.keyFingerprint, "4f8a")
        XCTAssertEqual(result.latencyMs, 73)
        XCTAssertNil(result.error)
        // Log path lock: ok=true must take the success branch.
        XCTAssertEqual(AmbaDiagnosticsLog.lastEvent, .success)
    }

    // 2. Invalid API key — Rust core surfaces 401 as
    // AmbaCoreError.Structured(status:401, code:"UNAUTHORIZED"). The
    // Swift wrapper rethrows verbatim; PingResult must NOT be
    // constructed.
    func testDiagnosticsPingPropagatesInvalidKeyAsThrow() async {
        mock.diagnosticsPingError = AmbaCoreError.Structured(
            status: 401,
            code: "UNAUTHORIZED",
            display: "401 Unauthorized",
            detailsJson: nil
        )
        do {
            _ = try await client.diagnosticsClient.ping()
            XCTFail("expected throw on 401")
        } catch let AmbaCoreError.Structured(status, code, _, _) {
            XCTAssertEqual(status, 401)
            XCTAssertEqual(code, "UNAUTHORIZED")
        } catch {
            XCTFail("expected AmbaCoreError.Structured, got \(error)")
        }
        // Log path lock: throws take the transport-failure branch.
        XCTAssertEqual(AmbaDiagnosticsLog.lastEvent, .transportFailure)
    }

    // 3. Project not found — server returns 200 + ok:false rather than
    // 4xx, so the SDK gets a structured PingResult with the error code
    // populated. The customer sees a debuggable string rather than a
    // generic 5xx.
    //
    // Regression lock for BugBot finding on PR #221: the log path
    // MUST be `.serverFailure`, not `.success`. A 200/ok:false
    // envelope logged as success would defeat the whole purpose of
    // the wire-verify primitive — customers would scroll past a
    // healthy-looking "ping ok" line while the project lookup
    // silently failed.
    func testDiagnosticsPingDecodesProjectNotFoundEnvelope() async throws {
        mock.nextDiagnosticsPingJson = #"""
            {"ok":false,"server_project_id":null,"environment":null,"key_fingerprint":"4f8a","latency_ms":4,"error":"DIAGNOSTICS_PROJECT_NOT_FOUND"}
            """#
        let result = try await client.diagnosticsClient.ping()
        XCTAssertFalse(result.ok)
        XCTAssertNil(result.serverProjectId)
        XCTAssertNil(result.environment)
        XCTAssertEqual(result.keyFingerprint, "4f8a")
        XCTAssertEqual(result.latencyMs, 4)
        XCTAssertEqual(result.error, "DIAGNOSTICS_PROJECT_NOT_FOUND")
        XCTAssertEqual(
            AmbaDiagnosticsLog.lastEvent,
            .serverFailure(code: "DIAGNOSTICS_PROJECT_NOT_FOUND"),
            "ok=false MUST log as serverFailure, not success"
        )
    }

    // 3b. Internal-error envelope — same shape as project-not-found
    // but with a different stable code. Tested separately so a
    // future refactor that hard-codes one error code in the log
    // branch surfaces immediately.
    func testDiagnosticsPingLogsServerFailureForInternalError() async throws {
        mock.nextDiagnosticsPingJson = #"""
            {"ok":false,"server_project_id":"proj_abc","environment":null,"key_fingerprint":"4f8a","latency_ms":4,"error":"DIAGNOSTICS_INTERNAL_ERROR"}
            """#
        let result = try await client.diagnosticsClient.ping()
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "DIAGNOSTICS_INTERNAL_ERROR")
        XCTAssertEqual(
            AmbaDiagnosticsLog.lastEvent,
            .serverFailure(code: "DIAGNOSTICS_INTERNAL_ERROR")
        )
    }

    // 4. Wire-shape lock — exercise the spec's actual JSON-decoder
    // behavior end-to-end rather than just asserting the
    // CodingKeys table. Per the memory entry
    // `feedback_polyfills_need_spec_self_tests`: a renamed serde
    // field on the Rust side would not throw — it would silently
    // return a default-initialized struct. This test would catch it.
    func testPingResultCodingKeysMapSnakeCaseFromServer() throws {
        let json = Data(#"""
            {"ok":true,"server_project_id":"proj_x","environment":"production","key_fingerprint":"abcd","latency_ms":12,"error":null}
            """#.utf8)
        let decoded = try JSONDecoder().decode(PingResult.self, from: json)
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.serverProjectId, "proj_x")
        XCTAssertEqual(decoded.environment, "production")
        XCTAssertEqual(decoded.keyFingerprint, "abcd")
        XCTAssertEqual(decoded.latencyMs, 12)
        XCTAssertNil(decoded.error)

        // Round-trip — re-encode and confirm snake_case lands back
        // on the wire. A future contributor renaming a CodingKey to
        // camelCase would break the Rust-side decoder; this assert
        // gates that.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let reencoded = try encoder.encode(decoded)
        let reencodedString = String(decoding: reencoded, as: UTF8.self)
        XCTAssertTrue(
            reencodedString.contains("\"server_project_id\":\"proj_x\""),
            "expected snake_case server_project_id in: \(reencodedString)"
        )
        XCTAssertTrue(
            reencodedString.contains("\"key_fingerprint\":\"abcd\""),
            "expected snake_case key_fingerprint in: \(reencodedString)"
        )
        XCTAssertTrue(
            reencodedString.contains("\"latency_ms\":12"),
            "expected snake_case latency_ms in: \(reencodedString)"
        )
    }

    // 5. Static facade — `Amba.diagnostics.ping()` throws
    // `.notConfigured` when no client is installed. Verifies the
    // typealias-style exposure (`Diagnostics.Type`) compiles and
    // routes through `Amba._internalRequireClient()`. The configured
    // path is exercised in (1)-(3) above via the instance accessor;
    // here we just lock the not-configured guard.
    func testStaticFacadeThrowsNotConfiguredWhenSingletonEmpty() async {
        // Defensive: in case a sibling test left a client behind.
        Amba.reset()
        do {
            _ = try await Amba.diagnostics.ping()
            XCTFail("expected notConfigured")
        } catch AmbaSwiftError.notConfigured {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
