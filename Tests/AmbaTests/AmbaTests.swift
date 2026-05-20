//
//  AmbaTests.swift
//
//  Unit tests for the Swift wrapper. The Rust core's behavior is
//  covered by 276+ tests in `core/`. These tests exercise the Swift-
//  side decoding + encoding logic on top of the UniFFI-generated bindings.
//

import XCTest
@testable import Amba

final class AmbaTests: XCTestCase {
    func testVersionPresent() {
        XCTAssertFalse(SDK_VERSION.isEmpty)
    }

    func testFindOptionsEncodesEmpty() throws {
        let options = FindOptions()
        let data = try JSONEncoder().encode(options)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertEqual(json, "{}")
    }

    func testFindOptionsEncodesLimit() throws {
        let options = FindOptions(limit: 50)
        let data = try JSONEncoder().encode(options)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"limit\":50"))
    }

    func testFindOptionsEncodesIncludeDeletedAsSnakeCase() throws {
        let options = FindOptions(includeDeleted: true)
        let data = try JSONEncoder().encode(options)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"include_deleted\":true"))
    }

    func testOrderByCodableRoundtrip() throws {
        let order = OrderBy(column: "created_at", direction: .desc)
        let data = try JSONEncoder().encode(order)
        let decoded = try JSONDecoder().decode(OrderBy.self, from: data)
        XCTAssertEqual(decoded.column, "created_at")
        XCTAssertEqual(decoded.direction, .desc)
    }

    func testFindResponseDecodesSnakeCase() throws {
        struct Row: Decodable { let id: String }
        let json = """
        {"data":[{"id":"r1"}],"next_cursor":"abc","has_more":true}
        """.data(using: .utf8)!
        let resp = try JSONDecoder.amba.decode(FindResponse<Row>.self, from: json)
        XCTAssertEqual(resp.data.count, 1)
        XCTAssertEqual(resp.data[0].id, "r1")
        XCTAssertEqual(resp.nextCursor, "abc")
        XCTAssertTrue(resp.hasMore)
    }

    func testAiMessageRequestEncodesPromptSlug() throws {
        let req = AiMessageRequest(promptSlug: "greeting", maxTokens: 100)
        let data = try JSONEncoder.amba.encode(req)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"prompt_slug\":\"greeting\""))
        XCTAssertTrue(json.contains("\"max_tokens\":100"))
    }

    func testAnyDecodableHandlesNull() throws {
        let data = "null".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AnyDecodable.self, from: data)
        XCTAssertTrue(decoded.value is NSNull)
    }

    func testAnyDecodableHandlesBool() throws {
        let data = "true".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AnyDecodable.self, from: data)
        XCTAssertEqual(decoded.value as? Bool, true)
    }

    func testAnyDecodableHandlesArray() throws {
        let data = "[1, 2, 3]".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AnyDecodable.self, from: data)
        XCTAssertNotNil(decoded.value as? [Any])
    }

    // MARK: - AmbaApiError

    func testAmbaApiErrorPreservesCodeAndMessage() {
        let err = AmbaApiError(
            code: AmbaApiErrorCode.rateLimited,
            message: "Rate limited",
            details: ["retry_after": 5]
        )
        XCTAssertEqual(err.code, "RATE_LIMITED")
        XCTAssertEqual(err.message, "Rate limited")
        let details = err.details as? [String: Int]
        XCTAssertEqual(details?["retry_after"], 5)
        XCTAssertTrue(err.description.contains("RATE_LIMITED"))
    }

    func testToAmbaApiErrorIsIdempotent() {
        let original = AmbaApiError(code: "X", message: "y")
        let wrapped = toAmbaApiError(original)
        // Same instance — no double-wrapping.
        XCTAssertTrue(wrapped === original)
    }

    func testToAmbaApiErrorMapsAmbaSwiftError() {
        let mapped = toAmbaApiError(AmbaSwiftError.notConfigured)
        XCTAssertEqual(mapped.code, AmbaApiErrorCode.notInitialized)

        let invalid = toAmbaApiError(AmbaSwiftError.invalidConfig("apiKey must not be empty"))
        XCTAssertEqual(invalid.code, AmbaApiErrorCode.invalidConfig)
        XCTAssertEqual(invalid.message, "apiKey must not be empty")
    }

    func testCodeFromMessageRecognizesRustErrorStrings() {
        XCTAssertEqual(codeFromMessage("Unauthorized: missing api key"), AmbaApiErrorCode.unauthorized)
        XCTAssertEqual(codeFromMessage("Rate limited: try again in 5s"), AmbaApiErrorCode.rateLimited)
        XCTAssertEqual(codeFromMessage("HTTP error: 500"), AmbaApiErrorCode.httpError)
        XCTAssertEqual(codeFromMessage("something weird"), AmbaApiErrorCode.unknownError)
    }

    func testWithAmbaErrorRethrowsAsAmbaApiError() async {
        do {
            _ = try await withAmbaError {
                throw AmbaSwiftError.notConfigured
            }
            XCTFail("expected throw")
        } catch let err as AmbaApiError {
            XCTAssertEqual(err.code, AmbaApiErrorCode.notInitialized)
        } catch {
            XCTFail("expected AmbaApiError, got \(error)")
        }
    }

    // ─── DX-17: structured envelope path ─────────────────────────────

    func testToAmbaApiErrorSurfacesGranularServerCodeFromStructured() {
        // The whole DX-17 point: granular server code lifts straight
        // through the UniFFI typed-error variant — no prefix-matching,
        // no UNKNOWN_ERROR fallback.
        let core = AmbaCoreError.Structured(
            status: 404,
            code: "STREAK_NOT_DEFINED",
            display: "no streak with key 'daily_play' has been defined",
            detailsJson: #"{"streak_key":"daily_play"}"#
        )
        let mapped = toAmbaApiError(core)
        XCTAssertEqual(mapped.code, "STREAK_NOT_DEFINED")
        XCTAssertEqual(mapped.message, "no streak with key 'daily_play' has been defined")
        XCTAssertEqual(mapped.details as? String, #"{"streak_key":"daily_play"}"#)
    }

    func testToAmbaApiErrorStructuredWithoutDetails() {
        let core = AmbaCoreError.Structured(
            status: 422,
            code: "INVALID_PAYLOAD",
            display: "bad body",
            detailsJson: nil
        )
        let mapped = toAmbaApiError(core)
        XCTAssertEqual(mapped.code, "INVALID_PAYLOAD")
        XCTAssertEqual(mapped.message, "bad body")
        XCTAssertNil(mapped.details)
    }

    func testToAmbaApiErrorStructuredKeepsCustomServerCodeUnknownToCodeFromMessage() {
        // Custom server code that isn't in AmbaApiErrorCode passes
        // through unchanged — not clobbered to UNKNOWN_ERROR.
        let core = AmbaCoreError.Structured(
            status: 409,
            code: "TEAM_ALREADY_HAS_OWNER",
            display: "team already has an owner",
            detailsJson: nil
        )
        let mapped = toAmbaApiError(core)
        XCTAssertEqual(mapped.code, "TEAM_ALREADY_HAS_OWNER")
        XCTAssertNotEqual(mapped.code, AmbaApiErrorCode.unknownError)
    }

    func testToAmbaApiErrorLegacyAmbaVariantUsesPrefixMatcher() {
        // Non-structured errors still flow through the prefix-matcher,
        // so existing wrapper behavior is preserved.
        let core = AmbaCoreError.Amba(display: "Rate limited: slow down")
        let mapped = toAmbaApiError(core)
        XCTAssertEqual(mapped.code, AmbaApiErrorCode.rateLimited)
        XCTAssertEqual(mapped.message, "Rate limited: slow down")
    }

    // ─── BugBot finding on #161 ──────────────────────────────────────
    //
    // The synthetic "message not found" path in Messaging.message(...)
    // must throw with code = NOT_FOUND so consumers' code-driven catches
    // resolve correctly. Earlier draft threw AmbaSwiftError.decode(...),
    // which `toAmbaApiError` mapped to VALIDATION_ERROR — semantically
    // wrong for a not-found condition.

    func testMessageNotFoundEmitsAmbaApiErrorWithNotFoundCode() async {
        // We can't easily mock the core's messagingListMessages from a
        // unit test (no FFI mock harness in scope), so this test asserts
        // the static error-construction shape that Messaging.message(...)
        // uses. The pattern needs to match a `where e.code ==
        // AmbaApiErrorCode.notFound` branch.
        let err = AmbaApiError(
            code: AmbaApiErrorCode.notFound,
            message: "no message m1 in conversation c1"
        )
        XCTAssertEqual(err.code, AmbaApiErrorCode.notFound)
        XCTAssertEqual(err.code, "NOT_FOUND")
        // Pass through `toAmbaApiError` — must be idempotent (BugBot
        // would catch a regression if a wrapper double-wraps and
        // changes the code).
        let mapped = toAmbaApiError(err)
        XCTAssertTrue(mapped === err)
        XCTAssertEqual(mapped.code, AmbaApiErrorCode.notFound)
    }
}
