//
//  AmbaApiError.swift
//
//  Typed error class for the amba Swift SDK + helper that converts
//  arbitrary thrown values (UniFFI core errors, NSError, plain Error)
//  into a stable `AmbaApiError` instance.
//
//  Callers can pattern-match safely with `error as? AmbaApiError`,
//  branch on `.code`, and pull extra payload from `.details` (raw HTTP
//  body, validation field paths, etc.). The wrapper methods on
//  `AmbaClient` / `Amba` rethrow via `withAmbaError` so consumers see
//  one error shape regardless of which layer (network, FFI, validation)
//  failed.
//
//  Mirrors `AmbaApiError` in `@layers/amba-web`, `@layers/amba-react-native`,
//  and the Flutter `AmbaApiError` Dart class. The `code` field is a
//  `String` (not a Swift enum) so customers can extend with their own
//  custom codes by simply throwing `AmbaApiError(code: "MY_CODE", ...)`
//  without coordinating with this package's types.
//

import Foundation

/// Stable error codes surfaced by the SDK. Mirrors the `AmbaApiErrorCode`
/// union in the TypeScript SDKs.
///
/// Kept as a constant `enum` of `String` values rather than a true
/// closed `enum` — that way callers can pass arbitrary code strings
/// for forward-compat (e.g. a server-only code not yet in the SDK)
/// without forcing a recompile.
public enum AmbaApiErrorCode {
    public static let unauthorized = "UNAUTHORIZED"
    public static let forbidden = "FORBIDDEN"
    public static let notFound = "NOT_FOUND"
    public static let conflict = "CONFLICT"
    public static let rateLimited = "RATE_LIMITED"
    public static let validationError = "VALIDATION_ERROR"
    public static let networkError = "NETWORK_ERROR"
    public static let httpError = "HTTP_ERROR"
    public static let circuitOpen = "CIRCUIT_OPEN"
    public static let consentNotGranted = "CONSENT_NOT_GRANTED"
    public static let notInitialized = "NOT_INITIALIZED"
    public static let invalidConfig = "INVALID_CONFIG"
    public static let invalidArgument = "INVALID_ARGUMENT"
    public static let pushPermissionDenied = "PUSH_PERMISSION_DENIED"
    public static let pushRegistrationFailed = "PUSH_REGISTRATION_FAILED"
    public static let unknownError = "UNKNOWN_ERROR"
}

/// Typed error thrown by the amba SDK. `code` carries a stable string
/// identifier (see `AmbaApiErrorCode`) so customers can branch without
/// string-matching `.message`. `details` is optional structured payload
/// (HTTP body, validation field paths, etc.).
///
/// ```swift
/// do {
///     try await Amba.events.track("purchase")
/// } catch let err as AmbaApiError {
///     switch err.code {
///     case AmbaApiErrorCode.unauthorized:
///         try await Amba.auth.signInAnonymously()
///     case AmbaApiErrorCode.rateLimited:
///         await Task.sleep(nanoseconds: 1_000_000_000)
///     default:
///         throw err
///     }
/// }
/// ```
public final class AmbaApiError: Error, CustomStringConvertible, @unchecked Sendable {
    /// Stable error code. See `AmbaApiErrorCode` for known values; may
    /// also be a custom string forwarded from the server.
    public let code: String
    /// Human-readable message. Don't string-match — use `.code` instead.
    public let message: String
    /// Optional structured payload — HTTP body, validation field paths,
    /// or any extra context the wrapping layer attached.
    public let details: Any?

    public init(code: String, message: String, details: Any? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }

    public var description: String {
        "AmbaApiError(\(code)): \(message)"
    }

    public var localizedDescription: String { description }
}

/// Best-effort: pull a stable error code out of a UniFFI / Rust
/// `AmbaError` Display string. Mirrors the same heuristic the TS
/// SDKs use (`codeFromMessage`). Falls back to `UNKNOWN_ERROR` for
/// any pattern it doesn't recognize.
internal func codeFromMessage(_ message: String) -> String {
    // Cheapest checks first — most production errors are auth or HTTP.
    if message.hasPrefix("Unauthorized") { return AmbaApiErrorCode.unauthorized }
    if message.hasPrefix("Forbidden") { return AmbaApiErrorCode.forbidden }
    if message.hasPrefix("Not found") { return AmbaApiErrorCode.notFound }
    if message.hasPrefix("Conflict") { return AmbaApiErrorCode.conflict }
    if message.hasPrefix("Rate limited") { return AmbaApiErrorCode.rateLimited }
    if message.hasPrefix("Validation error") { return AmbaApiErrorCode.validationError }
    if message.hasPrefix("Network error") { return AmbaApiErrorCode.networkError }
    if message.hasPrefix("HTTP error") { return AmbaApiErrorCode.httpError }
    if message.hasPrefix("Circuit breaker") { return AmbaApiErrorCode.circuitOpen }
    if message.hasPrefix("Consent not granted") { return AmbaApiErrorCode.consentNotGranted }
    if message.contains("not initialized") { return AmbaApiErrorCode.notInitialized }
    if message.hasPrefix("Invalid configuration") { return AmbaApiErrorCode.invalidConfig }
    if message.hasPrefix("Invalid argument") { return AmbaApiErrorCode.invalidArgument }
    return AmbaApiErrorCode.unknownError
}

/// Coerce any thrown value into an `AmbaApiError`. Idempotent — passing
/// an existing `AmbaApiError` returns it unchanged so wrappers can stack
/// without re-wrapping.
///
/// Heuristics, in order:
/// 1. Existing `AmbaApiError` → returned as-is.
/// 2. `AmbaCoreError.Structured` (DX-17) — server returned a structured
///    `{error:{code,message,details?}}` envelope. Surface the granular
///    server code (`STREAK_NOT_DEFINED`, `USER_NOT_FOUND`, …) verbatim.
///    `detailsJson` is the canonical JSON of the server-side `details`
///    field — wrappers can `JSONDecoder().decode(...)` it; we hand back
///    the raw string so consumers can pick their own parser.
/// 3. `AmbaCoreError.Amba` (legacy / non-envelope error path) — infer
///    code from the Display string's prefix (`Unauthorized`, `Rate
///    limited`, `HTTP error`, etc.). The Display string lives on the
///    `display` associated value — not `message` — because UniFFI 0.28's
///    Kotlin bindgen needed a field rename to avoid an `Exception.message`
///    collision (so Rust uses `display` everywhere for symmetry).
/// 4. `AmbaSwiftError` → mapped to the matching code.
/// 5. `LocalizedError` / `Error` with a Display string → inferred from prefix.
/// 6. Anything else → stringified and tagged `UNKNOWN_ERROR`.
public func toAmbaApiError(_ err: Error) -> AmbaApiError {
    if let apiErr = err as? AmbaApiError { return apiErr }
    if let coreErr = err as? AmbaCoreError {
        switch coreErr {
        case .Structured(_, let code, let display, let detailsJson):
            // Granular server code straight from the envelope. Skip
            // `codeFromMessage` — that's the whole point of DX-17.
            return AmbaApiError(code: code, message: display, details: detailsJson)
        case .Amba(let display):
            return AmbaApiError(code: codeFromMessage(display), message: display)
        }
    }
    if let swiftErr = err as? AmbaSwiftError {
        switch swiftErr {
        case .notConfigured:
            return AmbaApiError(code: AmbaApiErrorCode.notInitialized, message: "SDK not configured — call Amba.configure(...) first")
        case .alreadyConfigured:
            return AmbaApiError(code: AmbaApiErrorCode.invalidConfig, message: "SDK already configured — call Amba.reset() before re-configuring")
        case .invalidConfig(let msg):
            return AmbaApiError(code: AmbaApiErrorCode.invalidConfig, message: msg)
        case .decode(let msg):
            return AmbaApiError(code: AmbaApiErrorCode.validationError, message: "Decode error: \(msg)")
        case .uploadFailed:
            return AmbaApiError(code: AmbaApiErrorCode.httpError, message: "Upload failed")
        }
    }
    let msg = (err as? LocalizedError)?.errorDescription ?? "\(err)"
    return AmbaApiError(code: codeFromMessage(msg), message: msg)
}

/// Wrap a throwing async closure so any thrown value becomes an
/// `AmbaApiError`. The wrapper methods on `Amba` can use this to
/// convert UniFFI-emitted errors uniformly at the SDK boundary.
///
/// Note: existing public methods on `AmbaClient` / `Amba` still throw
/// the raw UniFFI error today for back-compat. Callers who want the
/// typed shape should wrap the call site:
///
/// ```swift
/// do {
///     try await withAmbaError { try await Amba.events.track("x") }
/// } catch let e as AmbaApiError { /* ... */ }
/// ```
public func withAmbaError<T>(_ body: () async throws -> T) async throws -> T {
    do {
        return try await body()
    } catch {
        throw toAmbaApiError(error)
    }
}
