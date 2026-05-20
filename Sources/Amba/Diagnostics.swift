//
//  Diagnostics.swift
//  Wire-verify primitive — exposes `Amba.diagnostics.ping()` for
//  customers to confirm "this key reaches this project on this
//  environment" before running real workloads.
//
//  Surface:
//
//      let result = try await Amba.diagnostics.ping()
//      if result.ok {
//          // result.serverProjectId / .environment / .keyFingerprint
//          // confirm the configured key is loading the right project.
//      }
//
//  The actual round-trip is in the Rust core
//  (`sdks/core/src/diagnostics.rs`); UniFFI returns the server-echoed
//  envelope as a JSON string and this wrapper decodes it into the
//  typed `PingResult` below. The struct mirrors the Rust shape
//  field-for-field — keep the two in sync.
//

import Foundation

#if canImport(os)
    import os
#endif

// MARK: - Server-echoed envelope

/// Server-echoed diagnostics envelope. Every field is decided by the
/// server — none of it is trusted from the request. That's the entire
/// reason the primitive exists: comparing `serverProjectId` against
/// the project id the customer thinks they configured catches "wrong
/// key, right project id" misconfiguration on the spot.
///
/// Mirrors `sdks/core/src/diagnostics.rs::PingResult` (snake_case
/// on the wire, camelCase in Swift).
public struct PingResult: Codable, Equatable, Sendable {
    /// `true` on a successful diagnostic. `false` when the server
    /// reached the route handler but couldn't resolve the lookup —
    /// `error` carries a stable code string in that case. Network /
    /// auth failures bubble out as `throw` from `Diagnostics.ping()`
    /// and never produce a `PingResult`.
    public let ok: Bool

    /// The project id the server resolved from the API key. Compare
    /// against the project id the customer thinks they configured —
    /// they should match. `nil` only when `ok == false` and the
    /// lookup failed before the project id was resolved.
    public let serverProjectId: String?

    /// `"production"` / `"staging"` / `"sandbox"` — derived server-side
    /// from the API key's environment and the developer tier. `nil`
    /// when `ok == false` and the lookup failed.
    public let environment: String?

    /// Last 4 hex chars of the sha256 of the API key the server
    /// actually saw on this request. Pasted next to the same suffix
    /// in the developer console, the customer can confirm the
    /// environment is loading the right secret.
    public let keyFingerprint: String?

    /// Server-measured handler latency in milliseconds (does NOT
    /// include client-side network time). Useful for spotting a
    /// degraded control plane.
    public let latencyMs: Int64

    /// `nil` on success. On a server-side failure (control DB read
    /// error etc.) the route returns 200 with `ok == false` and a
    /// stable code here — typically `"DIAGNOSTICS_INTERNAL_ERROR"`.
    public let error: String?

    public init(
        ok: Bool,
        serverProjectId: String?,
        environment: String?,
        keyFingerprint: String?,
        latencyMs: Int64,
        error: String?
    ) {
        self.ok = ok
        self.serverProjectId = serverProjectId
        self.environment = environment
        self.keyFingerprint = keyFingerprint
        self.latencyMs = latencyMs
        self.error = error
    }

    private enum CodingKeys: String, CodingKey {
        case ok
        case serverProjectId = "server_project_id"
        case environment
        // Server emits `key_fingerprint` always; struct keeps it
        // optional defensively in case a future server rev returns
        // null on `ok=false`.
        case keyFingerprint = "key_fingerprint"
        case latencyMs = "latency_ms"
        case error
    }
}

// MARK: - Static facade

/// `Amba.diagnostics.ping()` entry point.
///
/// Declared as `actor` for the same reason every namespace on the
/// `Amba` enum is a thread-safe shim: callers may invoke ping from
/// any task (often the install bootstrap, which runs on the main
/// actor) and we want the call site to read as "ask the diagnostics
/// namespace to ping" without surfacing the underlying singleton
/// access. The `static func ping` does not require actor isolation —
/// `Diagnostics.self` is a type-level namespace, mirroring the
/// pattern Stripe and AWS SDK use — but the actor declaration keeps
/// the type's identity stable for any future stored state.
public actor Diagnostics {
    /// Issue a wire-verify ping against `/v1/client/diagnostics/ping`
    /// using the configured API key. Returns the server-echoed
    /// envelope; emits a structured log line via `os.Logger`.
    ///
    /// Throws:
    ///   - `AmbaSwiftError.notConfigured` if `Amba.configure(...)`
    ///     has not been called yet.
    ///   - Any `AmbaCoreError` the Rust core surfaces for transport
    ///     or auth failures (`.Amba(...)`, `.Structured(...)`).
    ///   - `AmbaSwiftError.decode(...)` if the server envelope can't
    ///     be parsed as `PingResult` (would indicate server/SDK
    ///     version drift — surface it loudly rather than silently
    ///     returning a stale-shape struct).
    public static func ping() async throws -> PingResult {
        try await Amba._internalRequireClient().diagnosticsClient.ping()
    }
}

extension Amba {
    /// Top-level `Amba.diagnostics` namespace. Returns the
    /// `Diagnostics.Type` itself so callers write
    /// `Amba.diagnostics.ping()` instead of constructing an instance
    /// — `ping()` is a static method on the type.
    public static var diagnostics: Diagnostics.Type { Diagnostics.self }
}

// MARK: - Logging

/// Platform-idiomatic logger for `Amba.diagnostics.ping()`.
///
/// Routes through Apple's `os.Logger` on iOS 14+ / macOS 11+ /
/// tvOS 14+ / watchOS 7+ (every platform our Package.swift
/// targets), which lands in Console.app + the unified logging
/// system with the subsystem/category filters set below. On any
/// other platform (e.g. someone vendoring the package into a Linux
/// SwiftPM target) falls back to `print()` so the log line is at
/// least visible somewhere.
///
/// Why a dedicated helper and not call sites: keeps the `if
/// #available` ladder in one place + lets tests verify which path
/// the call site took via the `lastEvent` record without snooping
/// on `os.Logger` itself (Apple deliberately does not expose a
/// public way to introspect emitted log lines from inside the
/// same process).
internal enum AmbaDiagnosticsLog {
    /// Apple's recommended subsystem format is reverse-DNS of the
    /// owning org. `com.layers.amba` matches the customer-facing
    /// brand and lines up with the upcoming Kotlin SDK's
    /// `com.layers.amba` Logback tag.
    static let subsystem = "com.layers.amba"
    static let category = "sdk"

    /// Tags the path the most recent `Amba.diagnostics.ping()` call
    /// took, for test introspection. Three states:
    ///
    ///   - `.success` — server returned `ok:true` and the SDK
    ///     decoded a healthy envelope.
    ///   - `.serverFailure` — server returned `ok:false` with a
    ///     stable error code (no exception); the customer should
    ///     see a debuggable string, not a "ping ok" line.
    ///   - `.transportFailure` — the call threw (network, 401,
    ///     5xx, decode error); no `PingResult` was produced.
    ///
    /// `nil` until the first call. Tests reset to `nil` in setUp.
    enum Event: Equatable {
        case success
        case serverFailure(code: String?)
        case transportFailure
    }

    nonisolated(unsafe) static var lastEvent: Event?

    #if canImport(os)
        @available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *)
        private static let logger = Logger(subsystem: subsystem, category: category)
    #endif

    static func success(_ result: PingResult) {
        lastEvent = .success
        let projectId = result.serverProjectId ?? "<nil>"
        let env = result.environment ?? "<nil>"
        let fingerprint = result.keyFingerprint ?? "<nil>"
        let latency = result.latencyMs
        #if canImport(os)
            if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
                logger.debug(
                    "diagnostics.ping ok: \(projectId, privacy: .public) / \(env, privacy: .public) / fp=\(fingerprint, privacy: .public) / \(latency, privacy: .public)ms"
                )
                return
            }
        #endif
        print(
            "[amba/sdk] diagnostics.ping ok: \(projectId) / \(env) / fp=\(fingerprint) / \(latency)ms"
        )
    }

    /// 200 response with `ok=false`. Server reached the route but
    /// couldn't resolve the project / key — the customer needs to
    /// see this as a failure, not a "ping ok" line, otherwise the
    /// primitive defeats its own purpose (cf. PR #221 review).
    static func serverFailure(_ result: PingResult) {
        let code = result.error
        lastEvent = .serverFailure(code: code)
        let codeStr = code ?? "<nil>"
        let projectId = result.serverProjectId ?? "<nil>"
        let fingerprint = result.keyFingerprint ?? "<nil>"
        let latency = result.latencyMs
        #if canImport(os)
            if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
                logger.error(
                    "diagnostics.ping server failure: code=\(codeStr, privacy: .public) projectId=\(projectId, privacy: .public) fp=\(fingerprint, privacy: .public) latency=\(latency, privacy: .public)ms"
                )
                return
            }
        #endif
        print(
            "[amba/sdk] diagnostics.ping server failure: code=\(codeStr) projectId=\(projectId) fp=\(fingerprint) latency=\(latency)ms"
        )
    }

    static func failure(_ error: Error) {
        lastEvent = .transportFailure
        // Surface the typed description so the customer sees the
        // structured code on `AmbaCoreError.Structured(...)` rather
        // than the generic Display string.
        let description = String(reflecting: error)
        #if canImport(os)
            if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
                logger.error("diagnostics.ping failed: \(description, privacy: .public)")
                return
            }
        #endif
        print("[amba/sdk] diagnostics.ping failed: \(description)")
    }
}
