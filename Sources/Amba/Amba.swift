//
//  Amba.swift
//  amba SDK for Swift (iOS / macOS / tvOS / watchOS).
//
//  Two surfaces, same code path:
//
//   * `AmbaClient` — instance class holding the UniFFI-generated core +
//     per-namespace instance accessors. Constructor DI: production code
//     calls the public initializer (which builds a real `AmbaCoreFfi`);
//     tests use the internal initializer with a mock `AmbaCoreFfiProtocol`.
//
//   * `Amba` — static facade. Holds a singleton `AmbaClient` created by
//     `Amba.configure(...)` and routes every static method through it.
//     The exact same code runs in tests and production — tests just bypass
//     the facade by constructing `AmbaClient` directly.
//
//  Why two surfaces? Most consumers want `Amba.events.track(...)` (no
//  passing an SDK instance through every layer of the app). But tests
//  benefit from explicit injection — no global state, no setters that
//  leak into the shipping API. Same pattern as Stripe, AWS SDK, URLSession.
//

import Foundation

// MARK: - AmbaClient (the real implementation)

/// Instance class that owns the engine handle and exposes per-namespace
/// accessors. Construct one and call methods directly, or use the
/// `Amba` static facade for global SDK access.
public final class AmbaClient {
    // The core is the only thing tests need to inject. Held behind the
    // UniFFI-generated protocol so a mock conforming type works
    // identically to the real `AmbaCoreFfi`.
    private let core: AmbaCoreFfiProtocol
    private let uploadSession: URLSession

    public let events: Events
    public let auth: Auth
    public let users: Users
    public let sessions: Sessions
    public let sync: Sync
    public let collections: Collections
    public let storage: Storage
    public let push: Push
    public let entitlements: Entitlements
    public let ai: Ai
    public let config: Config
    public let flags: Flags
    // Gamification
    public let achievements: Achievements
    public let challenges: Challenges
    public let currencies: Currencies
    public let inventory: Inventory
    public let leaderboards: Leaderboards
    public let leagues: Leagues
    public let stores: Stores
    public let xp: Xp
    public let streaks: Streaks
    // Social
    public let feeds: Feeds
    public let friends: Friends
    public let groups: Groups
    public let messaging: Messaging
    public let moderation: Moderation
    public let reviews: Reviews
    public let roles: Roles
    public let referrals: Referrals
    // Lifecycle
    public let catalog: Catalog
    public let content: Content
    public let deepLinks: DeepLinks
    public let onboarding: Onboarding
    // Wire-verify primitive — added in v1.0.1. Held last in this list so
    // the diff against v1.0.0 is exactly one line plus the namespace
    // class below.
    public let diagnosticsClient: DiagnosticsClient

    /// Production initializer — builds a real `AmbaCoreFfi` from config.
    /// Throws `AmbaSwiftError.invalidConfig` if `apiKey` is empty.
    public convenience init(
        apiKey: String,
        baseUrl: String? = nil,
        consentRequired: Bool = false,
        debug: Bool = false
    ) throws {
        guard !apiKey.isEmpty else { throw AmbaSwiftError.invalidConfig("apiKey must not be empty") }
        let cfg = AmbaConfigFfi(
            apiKey: apiKey,
            baseUrl: baseUrl,
            sdkPlatform: "swift",
            sdkWrapperVersion: "amba-swift/\(SDK_VERSION)",
            consentRequired: consentRequired,
            debug: debug
        )
        let realCore = try AmbaCoreFfi(config: cfg)
        self.init(core: realCore, uploadSession: .shared)
    }

    /// Internal initializer — used by tests to inject a mock core plus
    /// (optionally) a URLSession whose configuration registers a
    /// URLProtocol stub so `storage.upload`'s PUT to R2 can be captured
    /// without real network I/O.
    internal init(core: AmbaCoreFfiProtocol, uploadSession: URLSession = .shared) {
        self.core = core
        self.uploadSession = uploadSession
        self.events = Events(core: core)
        self.auth = Auth(core: core)
        self.users = Users(core: core)
        self.sessions = Sessions(core: core)
        self.sync = Sync(core: core)
        self.collections = Collections(core: core)
        self.storage = Storage(core: core, uploadSession: uploadSession)
        self.push = Push(core: core)
        self.entitlements = Entitlements(core: core)
        self.ai = Ai(core: core)
        self.config = Config(core: core)
        self.flags = Flags(core: core)
        self.achievements = Achievements(core: core)
        self.challenges = Challenges(core: core)
        self.currencies = Currencies(core: core)
        self.inventory = Inventory(core: core)
        self.leaderboards = Leaderboards(core: core)
        self.leagues = Leagues(core: core)
        self.stores = Stores(core: core)
        self.xp = Xp(core: core)
        self.streaks = Streaks(core: core)
        self.feeds = Feeds(core: core)
        self.friends = Friends(core: core)
        self.groups = Groups(core: core)
        self.messaging = Messaging(core: core)
        self.moderation = Moderation(core: core)
        self.reviews = Reviews(core: core)
        self.roles = Roles(core: core)
        self.referrals = Referrals(core: core)
        self.catalog = Catalog(core: core)
        self.content = Content(core: core)
        self.deepLinks = DeepLinks(core: core)
        self.onboarding = Onboarding(core: core)
        self.diagnosticsClient = DiagnosticsClient(core: core)
    }

    // ── Identity / debug pass-through ─────────────────────────────────

    public var anonymousId: String? { try? core.anonymousId() }
    public var appUserId: String? { core.appUserId() }
    public var isAuthenticated: Bool { core.isAuthenticated() }
    public func setDebug(_ enabled: Bool) { core.setDebug(enabled: enabled) }

    // ── Namespace classes ─────────────────────────────────────────────

    public final class Events {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func track(
            _ event: String,
            properties: [String: Any]? = nil,
            telemetry: Bool? = nil
        ) async throws {
            let propsJson: String?
            if let p = properties {
                let data = try JSONSerialization.data(withJSONObject: p, options: [])
                propsJson = String(data: data, encoding: .utf8)
            } else {
                propsJson = nil
            }
            // Rust core's track FFI signature is
            // `track(event:propertiesJson:telemetry:)` — the `telemetry`
            // parameter was added when the Wave-2 billing bifurcation
            // shipped (PR #241). The Swift wrapper wasn't updated to
            // pass it through, so a fresh `swift build` failed with
            // `missing argument for parameter 'telemetry' in call`
            // (PR #246 docs-swift, fefdc02b). Pass through whatever
            // the caller asked for, defaulting to nil (= engagement
            // event, not telemetry).
            try await core.track(event: event, propertiesJson: propsJson, telemetry: telemetry)
        }
    }

    public final class Auth {
        private let core: AmbaCoreFfiProtocol
        // In-SDK auth-state pub/sub. `signIn*` / `signUp*` / `signOut`
        // / `refresh` call `notifySubscribers` after their underlying
        // core call resolves so subscribers always see a consistent
        // `Session?` snapshot. Subscriber callbacks run synchronously
        // inside the notification path — keep them light.
        private let subscribers = AuthSubscriberRegistry()
        init(core: AmbaCoreFfiProtocol) { self.core = core }

        public func signInAnonymously() async throws -> AuthResultFfi {
            let r = try await core.signInAnonymously()
            notifyFromAuthResult(r)
            return r
        }
        public func signInWithEmail(email: String, password: String) async throws -> AuthResultFfi {
            let r = try await core.signInWithEmail(email: email, password: password)
            notifyFromAuthResult(r)
            return r
        }
        public func signUpWithEmail(email: String, password: String) async throws -> AuthResultFfi {
            let r = try await core.signUpWithEmail(email: email, password: password)
            notifyFromAuthResult(r)
            return r
        }
        public func signInWithApple(identityToken: String) async throws -> AuthResultFfi {
            let r = try await core.signInWithSocial(provider: .apple, idToken: identityToken)
            notifyFromAuthResult(r)
            return r
        }
        public func signInWithGoogle(idToken: String) async throws -> AuthResultFfi {
            let r = try await core.signInWithSocial(provider: .google, idToken: idToken)
            notifyFromAuthResult(r)
            return r
        }
        /// Request a one-time passcode for `email`. The server emails a
        /// 6-digit code; the user types it in, then call
        /// `verifyEmailOtp(email:code:)` to exchange for a session.
        public func requestEmailOtp(email: String) async throws {
            try await core.requestEmailOtp(email: email)
        }
        /// Exchange `(email, code)` for a session. Returns the same
        /// `AuthResultFfi` shape as `signInWithEmail`.
        public func verifyEmailOtp(email: String, code: String) async throws -> AuthResultFfi {
            let r = try await core.verifyEmailOtp(email: email, code: code)
            notifyFromAuthResult(r)
            return r
        }
        /// Request a one-time passcode by SMS. `phone` must be E.164
        /// (starts with `+`, 8–15 total digits). The SDK rejects
        /// non-E.164 phones before issuing the network call.
        public func requestSmsOtp(phone: String) async throws {
            try await core.requestSmsOtp(phone: phone)
        }
        /// Exchange `(phone, code)` for a session. Returns the same
        /// `AuthResultFfi` shape as `verifyEmailOtp`.
        public func verifySmsOtp(phone: String, code: String) async throws -> AuthResultFfi {
            let r = try await core.verifySmsOtp(phone: phone, code: code)
            notifyFromAuthResult(r)
            return r
        }
        /// Request a magic-link email. The server emails a tokenized URL;
        /// open the URL on the device, extract the token from the deep link,
        /// then call `verifyMagicLink(token:)` to exchange for a session.
        /// NEW in SDK 4.0.
        public func requestMagicLink(email: String) async throws {
            try await core.requestMagicLink(email: email)
        }
        /// Exchange the token from a magic-link URL for a session.
        /// NEW in SDK 4.0.
        public func verifyMagicLink(token: String) async throws -> AuthResultFfi {
            let r = try await core.verifyMagicLink(token: token)
            notifyFromAuthResult(r)
            return r
        }
        /// Link an external credential (Apple/Google/email/etc.) to the
        /// current — possibly anonymous — session, upgrading it to an
        /// identified account. `provider` is the lowercase identifier
        /// the server recognizes (e.g. `"apple"`, `"google"`, `"email"`).
        /// `credential` is provider-specific (id token for Apple/Google,
        /// `email:password` for email). NEW in SDK 4.0.
        public func linkAccount(provider: String, credential: String) async throws -> AuthResultFfi {
            let r = try await core.linkAccount(provider: provider, credential: credential)
            notifyFromAuthResult(r)
            return r
        }
        public func signOut(rotateAnonymousId: Bool = false) async throws {
            try await core.signOut(rotateAnonymousId: rotateAnonymousId)
            subscribers.notify(nil)
        }
        public func refresh() async throws -> AuthResultFfi {
            let r = try await core.refreshSession()
            notifyFromAuthResult(r)
            return r
        }
        public func me() async throws -> UserFfi {
            try await core.me()
        }

        // ── Session-state read-back + subscribe (Phase A parity) ─────

        /// Snapshot the current session, or `nil` if no session is
        /// live. `sessionToken` / `refreshToken` / `expiresAt` come
        /// back as empty strings — they're SDK-managed and not
        /// read-back-able from the core. Use `Amba.isAuthenticated`
        /// if you only need the boolean.
        public func getSession() async throws -> Session? {
            guard core.isAuthenticated() else { return nil }
            let user = try await core.me()
            return Session(user: user)
        }

        /// Stable anonymous identifier. Async for parity with the
        /// platform-native shape (RN/Flutter) where the platform may
        /// need to await a persistence read. On Swift the value is
        /// held in-memory by the core so the await is a no-op.
        public func getAnonymousId() async -> String {
            core.anonymousId()
        }

        /// Subscribe to session changes. Fires after every
        /// `signIn*` / `signUp*` / `refresh` / `signOut` call.
        /// Returns an unsubscribe closure — call it to remove the
        /// listener.
        ///
        /// Does NOT fire an initial snapshot on subscribe; call
        /// `getSession()` once after subscribing if you need the
        /// current state up front.
        @discardableResult
        public func onAuthStateChange(_ callback: @escaping (Session?) -> Void) -> () -> Void {
            subscribers.add(callback)
        }

        /// Internal — `AmbaClient` test scaffolding can drive the
        /// pub/sub directly for unit coverage without going through
        /// the FFI.
        internal func notifyFromAuthResult(_ result: AuthResultFfi) {
            subscribers.notify(Session(user: result.user))
        }
    }

    /// In-SDK auth-state pub/sub registry. Holds weak-of-id callbacks
    /// keyed by a UUID token returned at `add` time so subscribe-
    /// then-unsubscribe-while-iterating is safe. `NSLock`-guarded for
    /// concurrent add/remove/notify from background tasks.
    fileprivate final class AuthSubscriberRegistry: @unchecked Sendable {
        private let lock = NSLock()
        private var listeners: [UUID: (Session?) -> Void] = [:]

        func add(_ cb: @escaping (Session?) -> Void) -> () -> Void {
            let id = UUID()
            lock.lock()
            listeners[id] = cb
            lock.unlock()
            return { [weak self] in
                guard let self = self else { return }
                self.lock.lock()
                self.listeners.removeValue(forKey: id)
                self.lock.unlock()
            }
        }

        func notify(_ session: Session?) {
            // Snapshot under the lock so concurrent unsubscribe during
            // notify can't crash on a mutating dictionary. Subscriber
            // errors are isolated — one bad callback doesn't block the
            // rest (matches the TS SDK behavior).
            lock.lock()
            let snapshot = Array(listeners.values)
            lock.unlock()
            for cb in snapshot {
                cb(session)
            }
        }
    }

    /// SDK 4.0 — profile read/update. Distinct from `auth`, which owns
    /// credentials and session lifecycle. `users` is the read/write
    /// surface for the authenticated user's profile row.
    public final class Users {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        /// Fetch a user profile. `userId == nil` resolves to the current
        /// authenticated user (`/v1/client/users/me`). A non-nil `userId`
        /// is reserved for a future server route and surfaces as a
        /// validation error from the core today.
        public func get(userId: String? = nil) async throws -> UserFfi {
            try await core.usersGet(userId: userId)
        }
        /// Patch the user profile. `patch` is a JSON-serializable
        /// dictionary of fields to update (e.g. `["displayName": "Alice"]`).
        /// `userId == nil` patches the current user.
        public func update(userId: String? = nil, patch: [String: Any]) async throws -> UserFfi {
            let data = try JSONSerialization.data(withJSONObject: patch, options: [])
            let patchJson = String(data: data, encoding: .utf8) ?? "{}"
            return try await core.usersUpdate(userId: userId, patchJson: patchJson)
        }
    }

    /// SDK 4.0 — active app-session listing + revocation. Distinct from
    /// the in-SDK `auth.getSession()` snapshot (which returns the current
    /// auth-session token state); these are server-tracked app sessions
    /// surfaced for "sign out other devices" flows.
    public final class Sessions {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func list() async throws -> [AppSession] {
            let json = try await core.sessionsList()
            return try Amba.decodeJSON([AppSession].self, from: json)
        }
        public func revoke(sessionId: String) async throws {
            try await core.sessionsRevoke(sessionId: sessionId)
        }
    }

    /// SDK 4.0 — offline change replay. `pushChanges` replays a batch of
    /// buffered mutations against the server; conflicts are server-wins
    /// and surfaced in the response. `pullChanges` fetches remote-origin
    /// changes since the supplied cursor so the local cache converges.
    public final class Sync {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func pushChanges(_ changes: [SyncChange]) async throws -> PushChangesResult {
            let data = try JSONEncoder.amba.encode(changes)
            let changesJson = String(data: data, encoding: .utf8) ?? "[]"
            let json = try await core.syncPushChanges(changesJson: changesJson)
            return try Amba.decodeJSON(PushChangesResult.self, from: json)
        }
        public func pullChanges(since: PullSince) async throws -> PullChangesResult {
            let data = try JSONEncoder.amba.encode(since)
            let sinceJson = String(data: data, encoding: .utf8) ?? "{}"
            let json = try await core.syncPullChanges(sinceJson: sinceJson)
            return try Amba.decodeJSON(PullChangesResult.self, from: json)
        }
    }

    public final class Collections {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func find<T: Decodable>(_ name: String, options: FindOptions = FindOptions(), as type: T.Type = T.self) async throws -> FindResponse<T> {
            let optionsData = try JSONEncoder().encode(options)
            let optionsJson = String(data: optionsData, encoding: .utf8) ?? "{}"
            let respJson = try await core.collectionsFind(collection: name, optionsJson: optionsJson)
            guard let data = respJson.data(using: .utf8) else { throw AmbaSwiftError.decode("not utf8") }
            return try JSONDecoder.amba.decode(FindResponse<T>.self, from: data)
        }
        public func findOne<T: Decodable>(_ name: String, id: String, as type: T.Type = T.self) async throws -> T {
            let respJson = try await core.collectionsFindOne(collection: name, id: id)
            guard let data = respJson.data(using: .utf8) else { throw AmbaSwiftError.decode("not utf8") }
            return try JSONDecoder.amba.decode(T.self, from: data)
        }
        public func insert<T: Decodable>(_ name: String, row: [String: Any], as type: T.Type = T.self) async throws -> T {
            let rowData = try JSONSerialization.data(withJSONObject: row, options: [])
            let rowJson = String(data: rowData, encoding: .utf8) ?? "{}"
            let respJson = try await core.collectionsInsert(collection: name, rowJson: rowJson)
            guard let data = respJson.data(using: .utf8) else { throw AmbaSwiftError.decode("not utf8") }
            return try JSONDecoder.amba.decode(T.self, from: data)
        }
        public func update<T: Decodable>(_ name: String, id: String, set: [String: Any], as type: T.Type = T.self) async throws -> T {
            let setData = try JSONSerialization.data(withJSONObject: set, options: [])
            let setJson = String(data: setData, encoding: .utf8) ?? "{}"
            let respJson = try await core.collectionsUpdate(collection: name, id: id, setJson: setJson)
            guard let data = respJson.data(using: .utf8) else { throw AmbaSwiftError.decode("not utf8") }
            return try JSONDecoder.amba.decode(T.self, from: data)
        }
        public func delete(_ name: String, id: String) async throws {
            _ = try await core.collectionsDelete(collection: name, id: id)
        }
        /// NEW in 4.0. Vector similarity search. `vectorField` is the
        /// column holding the embedding, `queryVector` the probe vector,
        /// `k` the desired number of neighbors. Optional `filter` further
        /// narrows the candidate set before ranking.
        public func findNearest<T: Decodable>(
            _ name: String,
            vectorField: String,
            queryVector: [Float],
            k: UInt32,
            filter: AnyEncodable? = nil,
            as type: T.Type = T.self
        ) async throws -> [T] {
            let opts = NearestOptions(vectorField: vectorField, queryVector: queryVector, k: k, filter: filter)
            let data = try JSONEncoder.amba.encode(opts)
            let optionsJson = String(data: data, encoding: .utf8) ?? "{}"
            let respJson = try await core.collectionsFindNearest(collection: name, optionsJson: optionsJson)
            return try Amba.decodeJSON(NearestResponse<T>.self, from: respJson).data
        }
        /// NEW in 4.0. Row count, optionally constrained by a `filter`.
        public func count(_ name: String, filter: AnyEncodable? = nil) async throws -> UInt64 {
            let filterJson: String?
            if let f = filter {
                let data = try JSONEncoder.amba.encode(f)
                filterJson = String(data: data, encoding: .utf8)
            } else {
                filterJson = nil
            }
            let respJson = try await core.collectionsCount(collection: name, filterJson: filterJson)
            return try Amba.decodeJSON(CountResponse.self, from: respJson).data.count
        }
    }

    public final class Storage {
        private let core: AmbaCoreFfiProtocol
        private let uploadSession: URLSession
        init(core: AmbaCoreFfiProtocol, uploadSession: URLSession) {
            self.core = core
            self.uploadSession = uploadSession
        }
        public func presign(bucket: String, filename: String, mimeType: String, sizeBytes: UInt64, retentionDays: UInt32? = nil) async throws -> PresignDataFfi {
            try await core.storagePresign(bucket: bucket, filename: filename, mimeType: mimeType, sizeBytes: sizeBytes, retentionDays: retentionDays)
        }
        public func commit(uploadId: String, assetId: String) async throws -> MediaAssetFfi {
            try await core.storageCommit(uploadId: uploadId, assetId: assetId)
        }
        /// Complete-flow upload: presign → PUT to R2 → commit.
        public func upload(bucket: String, data: Data, filename: String, mimeType: String, retentionDays: UInt32? = nil) async throws -> MediaAssetFfi {
            let pre = try await presign(bucket: bucket, filename: filename, mimeType: mimeType, sizeBytes: UInt64(data.count), retentionDays: retentionDays)
            guard let uploadUrl = URL(string: pre.uploadUrl) else { throw AmbaSwiftError.decode("invalid upload URL") }
            var req = URLRequest(url: uploadUrl)
            req.httpMethod = "PUT"
            for h in pre.uploadHeaders {
                req.setValue(h.value, forHTTPHeaderField: h.name)
            }
            req.httpBody = data
            let (_, response) = try await uploadSession.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw AmbaSwiftError.uploadFailed
            }
            return try await commit(uploadId: pre.uploadId, assetId: pre.assetId)
        }
        /// NEW in 4.0. List media assets, optionally narrowed by a key
        /// `prefix` (server-side filter — forward-compatible; the server
        /// currently ignores `prefix` and returns all assets).
        public func list(prefix: String? = nil) async throws -> [MediaAssetSummary] {
            let json = try await core.storageList(prefix: prefix)
            return try Amba.decodeJSON(StorageListResponse.self, from: json).data
        }
        /// NEW in 4.0. Delete an asset by id (the canonical media id —
        /// `MediaAssetFfi.id`, NOT the storage key). The Rust core stages
        /// this as `assetId` to match the server route shape.
        public func delete(assetId: String) async throws {
            try await core.storageDelete(assetId: assetId)
        }
        /// NEW in 4.0. Download the asset bytes. Returns `Data` (UniFFI
        /// maps the Rust `Vec<u8>` → Swift `Data` natively, no extra
        /// copy). For very large assets prefer streaming via the asset's
        /// signed `url` instead — `download` materializes the whole body
        /// into memory.
        public func download(assetId: String) async throws -> Data {
            try await core.storageDownload(assetId: assetId)
        }
    }

    public final class Push {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func register(token: String, platform: PushPlatformFfi, bundleId: String? = nil) async throws -> PushTokenFfi {
            try await core.pushRegister(token: token, platform: platform, bundleId: bundleId)
        }
        public func subscribe(topic: String) async throws {
            try await core.pushSubscribe(topic: topic)
        }
        public func unregister(token: String) async throws {
            try await core.pushUnregister(token: token)
        }
        public func unsubscribe(topic: String) async throws {
            try await core.pushUnsubscribe(topic: topic)
        }
        public func getTokens() async throws -> [PushToken] {
            let json = try await core.pushGetTokens()
            return try Amba.decodeJSON([PushToken].self, from: json)
        }
    }

    public final class Entitlements {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func list() async throws -> [UserEntitlementFfi] {
            try await core.entitlementsList()
        }
        public func has(_ name: String) async -> Bool {
            await core.entitlementsHas(name: name)
        }
    }

    public final class Ai {
        public let anthropic: Anthropic
        init(core: AmbaCoreFfiProtocol) {
            self.anthropic = Anthropic(core: core)
        }
        public final class Anthropic {
            public let messages: Messages
            init(core: AmbaCoreFfiProtocol) {
                self.messages = Messages(core: core)
            }
            public final class Messages {
                private let core: AmbaCoreFfiProtocol
                init(core: AmbaCoreFfiProtocol) { self.core = core }
                public func create(request: AiMessageRequest) async throws -> AiMessageResponse {
                    let requestData = try JSONEncoder.amba.encode(request)
                    let requestJson = String(data: requestData, encoding: .utf8) ?? "{}"
                    let respJson = try await core.aiAnthropicMessages(requestJson: requestJson)
                    guard let data = respJson.data(using: .utf8) else { throw AmbaSwiftError.decode("not utf8") }
                    return try JSONDecoder.amba.decode(AiMessageResponse.self, from: data)
                }
            }
        }
    }

    public final class Config {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func fetch() async throws -> ConfigBundle {
            let respJson = try await core.configFetch()
            guard let data = respJson.data(using: .utf8) else { throw AmbaSwiftError.decode("not utf8") }
            return try JSONDecoder.amba.decode(ConfigBundle.self, from: data)
        }
    }

    public final class Flags {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func fetch() async throws -> [FlagAssignmentFfi] {
            try await core.flagsFetch()
        }
        /// Single-flag lookup (SDK 4.0). Wraps
        /// `GET /v1/client/flags/{key}`. Returns `nil` for unknown
        /// or disabled keys; rethrows other failures.
        public func get(key: String) async throws -> FlagAssignmentFfi? {
            try await core.flagsGet(key: key)
        }
    }

    /// Instance counterpart to the `Amba.diagnostics.ping()` static
    /// facade. Holds the UniFFI core reference and decodes the JSON
    /// envelope `diagnostics_ping` returns from the Rust side into a
    /// typed `PingResult`. The static facade (`public actor Diagnostics`
    /// below) forwards to this same code path through the singleton
    /// `AmbaClient`.
    public final class DiagnosticsClient {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }

        /// Issue a wire-verify ping. Returns the server-echoed envelope
        /// so the caller can compare `serverProjectId` / `keyFingerprint`
        /// against what they configured. Logs success/failure via
        /// `os.Logger` (subsystem `"com.layers.amba"`, category `"sdk"`)
        /// on platforms that support it; falls back to `print()` on
        /// older OSes / Linux.
        ///
        /// The log path branches on `PingResult.ok`: a 200 envelope
        /// with `ok=false` (e.g. `DIAGNOSTICS_PROJECT_NOT_FOUND`) is
        /// the customer-debuggable failure mode the primitive was
        /// designed around — logging it as `success` would defeat
        /// the entire point of having a wire-verify primitive.
        public func ping() async throws -> PingResult {
            do {
                let json = try await core.diagnosticsPing()
                let result = try Amba.decodeJSON(PingResult.self, from: json)
                if result.ok {
                    AmbaDiagnosticsLog.success(result)
                } else {
                    AmbaDiagnosticsLog.serverFailure(result)
                }
                return result
            } catch {
                AmbaDiagnosticsLog.failure(error)
                throw error
            }
        }
    }

    // MARK: - Gamification namespaces

    public final class Achievements {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func all() async throws -> [Achievement] {
            let json = try await core.achievementsGetAll()
            return try Amba.decodeJSON([Achievement].self, from: json)
        }
        public func progress() async throws -> [AchievementProgress] {
            let json = try await core.achievementsGetProgress()
            return try Amba.decodeJSON([AchievementProgress].self, from: json)
        }
    }

    public final class Challenges {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func active() async throws -> [Challenge] {
            let json = try await core.challengesGetActive()
            return try Amba.decodeJSON([Challenge].self, from: json)
        }
        public func get(id: String) async throws -> Challenge {
            let json = try await core.challengesGet(id: id)
            return try Amba.decodeJSON(Challenge.self, from: json)
        }
        public func progress(id: String) async throws -> ChallengeProgress {
            let json = try await core.challengesGetProgress(id: id)
            return try Amba.decodeJSON(ChallengeProgress.self, from: json)
        }
        public func claim(id: String) async throws -> ChallengeProgress {
            let json = try await core.challengesClaim(id: id)
            return try Amba.decodeJSON(ChallengeProgress.self, from: json)
        }
    }

    public final class Currencies {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func balance() async throws -> [CurrencyBalance] {
            let json = try await core.currenciesGetBalance()
            return try Amba.decodeJSON([CurrencyBalance].self, from: json)
        }
        public func transactions(currencyKey: String) async throws -> [CurrencyTransaction] {
            let json = try await core.currenciesGetTransactions(currencyKey: currencyKey)
            return try Amba.decodeJSON([CurrencyTransaction].self, from: json)
        }
    }

    public final class Inventory {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func items() async throws -> [InventoryItem] {
            let json = try await core.inventoryGetItems()
            return try Amba.decodeJSON([InventoryItem].self, from: json)
        }
        public func item(id: String) async throws -> InventoryItem {
            let json = try await core.inventoryGetItem(id: id)
            return try Amba.decodeJSON(InventoryItem.self, from: json)
        }
        public func purchase(_ request: PurchaseRequest) async throws -> InventoryItem {
            let data = try JSONEncoder.amba.encode(request)
            let requestJson = String(data: data, encoding: .utf8) ?? "{}"
            let json = try await core.inventoryPurchase(requestJson: requestJson)
            return try Amba.decodeJSON(InventoryItem.self, from: json)
        }
        public func consume(_ request: ConsumeRequest) async throws -> InventoryItem {
            let data = try JSONEncoder.amba.encode(request)
            let requestJson = String(data: data, encoding: .utf8) ?? "{}"
            let json = try await core.inventoryConsume(requestJson: requestJson)
            return try Amba.decodeJSON(InventoryItem.self, from: json)
        }
    }

    public final class Leaderboards {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func get(key: String) async throws -> Leaderboard {
            let json = try await core.leaderboardsGet(key: key)
            return try Amba.decodeJSON(Leaderboard.self, from: json)
        }
        public func entries(key: String, limit: UInt32? = nil) async throws -> [LeaderboardEntry] {
            let json = try await core.leaderboardsGetEntries(key: key, limit: limit)
            return try Amba.decodeJSON([LeaderboardEntry].self, from: json)
        }
        public func myRank(key: String) async throws -> LeaderboardEntry {
            let json = try await core.leaderboardsGetMyRank(key: key)
            return try Amba.decodeJSON(LeaderboardEntry.self, from: json)
        }
    }

    public final class Stores {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func list() async throws -> [Store] {
            let json = try await core.storesList()
            return try Amba.decodeJSON([Store].self, from: json)
        }
        public func purchaseOptions(storeKey: String) async throws -> [PurchaseOption] {
            let json = try await core.storesGetPurchaseOptions(storeKey: storeKey)
            return try Amba.decodeJSON([PurchaseOption].self, from: json)
        }
        public func purchase(storeKey: String, purchaseOptionId: String, receipt: [String: Any]) async throws -> PurchaseResult {
            let receiptData = try JSONSerialization.data(withJSONObject: receipt, options: [])
            let receiptJson = String(data: receiptData, encoding: .utf8) ?? "{}"
            let json = try await core.storesPurchase(storeKey: storeKey, purchaseOptionId: purchaseOptionId, receiptJson: receiptJson)
            return try Amba.decodeJSON(PurchaseResult.self, from: json)
        }
    }

    public final class Xp {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func balance() async throws -> XpBalance {
            let json = try await core.xpGetBalance()
            return try Amba.decodeJSON(XpBalance.self, from: json)
        }
        public func history(limit: UInt32? = nil) async throws -> [XpTransaction] {
            let json = try await core.xpGetHistory(limit: limit)
            return try Amba.decodeJSON([XpTransaction].self, from: json)
        }
        public func claim(grantKey: String) async throws -> XpTransaction {
            let json = try await core.xpClaim(grantKey: grantKey)
            return try Amba.decodeJSON(XpTransaction.self, from: json)
        }
    }

    public final class Streaks {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func all() async throws -> [Streak] {
            let json = try await core.streaksGetAll()
            return try Amba.decodeJSON([Streak].self, from: json)
        }
        public func qualify(streakKey: String) async throws -> Streak {
            let json = try await core.streaksQualify(streakKey: streakKey)
            return try Amba.decodeJSON(Streak.self, from: json)
        }
    }

    /// SDK 4.0 — weekly tiered leaderboard cohorts. The server rolls every
    /// active user into a ~30-member cohort each Monday; players race for
    /// tier-up / tier-down on a 7-day clock.
    public final class Leagues {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        /// Current user's cohort standing — rank, score, cohort metadata.
        /// `cohort` / `league` / `rank` are nil before the user's first
        /// Monday rollover.
        public func me() async throws -> LeagueMembership {
            let json = try await core.leaguesMe()
            return try Amba.decodeJSON(LeagueMembership.self, from: json)
        }
        /// Full cohort roster (anonymised: `displayName` + `score` + `rank`,
        /// NOT user ids).
        public func cohort() async throws -> LeagueCohortResponse {
            let json = try await core.leaguesCohort()
            return try Amba.decodeJSON(LeagueCohortResponse.self, from: json)
        }
    }

    // MARK: - Social namespaces

    public final class Feeds {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func activity(feed: String? = nil, cursor: String? = nil) async throws -> FeedResponse {
            let json = try await core.feedsGetActivity(feed: feed, cursor: cursor)
            return try Amba.decodeJSON(FeedResponse.self, from: json)
        }
    }

    public final class Friends {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func list() async throws -> [Friendship] {
            let json = try await core.friendsGetList()
            return try Amba.decodeJSON([Friendship].self, from: json)
        }
        public func friends() async throws -> [Friendship] {
            let json = try await core.friendsGetFriends()
            return try Amba.decodeJSON([Friendship].self, from: json)
        }
        /// NEW in 4.0. Send a friend request to `userId`. Returns the
        /// newly-created `Friendship` row in `pending` state.
        public func sendRequest(userId: String) async throws -> Friendship {
            let json = try await core.friendsSendRequest(userId: userId)
            return try Amba.decodeJSON(Friendship.self, from: json)
        }
        /// NEW in 4.0. Accept a pending friend request, returning the
        /// updated `Friendship` row in `accepted` state.
        public func acceptRequest(friendshipId: String) async throws -> Friendship {
            let json = try await core.friendsAcceptRequest(friendshipId: friendshipId)
            return try Amba.decodeJSON(Friendship.self, from: json)
        }
        /// NEW in 4.0. Decline a pending friend request. Server discards
        /// the row, so this returns Void.
        public func declineRequest(friendshipId: String) async throws {
            try await core.friendsDeclineRequest(friendshipId: friendshipId)
        }
        public func blockUser(userId: String) async throws -> Friendship {
            let json = try await core.friendsBlockUser(userId: userId)
            return try Amba.decodeJSON(Friendship.self, from: json)
        }
        public func unblockUser(userId: String) async throws {
            try await core.friendsUnblockUser(userId: userId)
        }
        public func removeBlock(friendshipId: String) async throws {
            try await core.friendsRemoveBlock(friendshipId: friendshipId)
        }
        /// Unfriend by the other user's id (SDK 4.0). Wraps
        /// `DELETE /v1/client/friends/by-user/{userId}`. Server
        /// preserves blocked rows; use `unblockUser(_:)` to clear
        /// those instead.
        public func removeFriend(userId: String) async throws {
            try await core.friendsRemoveFriend(userId: userId)
        }
    }

    public final class Groups {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func create(_ params: GroupCreate) async throws -> Group {
            let data = try JSONEncoder.amba.encode(params)
            let paramsJson = String(data: data, encoding: .utf8) ?? "{}"
            let json = try await core.groupsCreate(paramsJson: paramsJson)
            return try Amba.decodeJSON(Group.self, from: json)
        }
        public func get(id: String) async throws -> Group {
            let json = try await core.groupsGet(id: id)
            return try Amba.decodeJSON(Group.self, from: json)
        }
        public func update(id: String, patch: GroupUpdate) async throws -> Group {
            let data = try JSONEncoder.amba.encode(patch)
            let patchJson = String(data: data, encoding: .utf8) ?? "{}"
            let json = try await core.groupsUpdate(id: id, patchJson: patchJson)
            return try Amba.decodeJSON(Group.self, from: json)
        }
        public func delete(id: String) async throws {
            try await core.groupsDelete(id: id)
        }
        public func members(id: String) async throws -> [GroupMember] {
            let json = try await core.groupsGetMembers(id: id)
            return try Amba.decodeJSON([GroupMember].self, from: json)
        }
        public func join(id: String) async throws -> GroupMember {
            let json = try await core.groupsJoin(id: id)
            return try Amba.decodeJSON(GroupMember.self, from: json)
        }
        public func leave(id: String) async throws {
            try await core.groupsLeave(id: id)
        }
        public func invite(id: String, userId: String) async throws -> GroupMember {
            let json = try await core.groupsInvite(id: id, userId: userId)
            return try Amba.decodeJSON(GroupMember.self, from: json)
        }
    }

    public final class Messaging {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func conversations() async throws -> [Conversation] {
            let json = try await core.messagingGetConversations()
            return try Amba.decodeJSON([Conversation].self, from: json)
        }
        /// NEW in 4.0. Create a conversation with the supplied
        /// `participants` (user ids). Optional `metadata` is a free-form
        /// JSON-serializable blob the server stores on the conversation
        /// row. Replaces the previous workaround of starting a thread by
        /// sending an initial message with `toUserId`.
        public func createConversation(
            participants: [String],
            metadata: [String: Any]? = nil
        ) async throws -> Conversation {
            var body: [String: Any] = ["participants": participants]
            if let metadata = metadata {
                body["metadata"] = metadata
            }
            let data = try JSONSerialization.data(withJSONObject: body, options: [])
            let requestJson = String(data: data, encoding: .utf8) ?? "{}"
            let json = try await core.messagingCreateConversation(requestJson: requestJson)
            return try Amba.decodeJSON(Conversation.self, from: json)
        }
        /// NEW in 4.0. List messages in a conversation, paginated. `limit`
        /// caps the page size (server-defined default when nil); `offset`
        /// skips the leading N messages for cursor-style paging.
        public func listMessages(
            conversationId: String,
            limit: UInt32? = nil,
            offset: UInt32? = nil
        ) async throws -> [Message] {
            let json = try await core.messagingListMessages(
                conversationId: conversationId,
                limit: limit,
                offset: offset
            )
            return try Amba.decodeJSON([Message].self, from: json)
        }
        /// NEW in 4.0. Mark every unread message in `conversationId` as
        /// read for the current user.
        public func markRead(conversationId: String) async throws {
            _ = try await core.messagingMarkRead(conversationId: conversationId)
        }
        /// Fetch a single message by id. Phase A 4.0 wired a dedicated
        /// `messagingGetMessage` symbol in the Rust core (implemented via
        /// paginated `list_messages` server-side; the server itself
        /// doesn't ship a GET-one route yet but the core hides that).
        /// Returns `nil` when the id isn't present in the conversation —
        /// matches the optional-result shape the spec calls for.
        public func getMessage(conversationId: String, messageId: String) async throws -> Message? {
            let json = try await core.messagingGetMessage(
                conversationId: conversationId,
                messageId: messageId
            )
            return try Amba.decodeJSON(Message?.self, from: json)
        }
        public func sendMessage(_ request: SendMessageRequest) async throws -> Message {
            let data = try JSONEncoder.amba.encode(request)
            let requestJson = String(data: data, encoding: .utf8) ?? "{}"
            let json = try await core.messagingSendMessage(requestJson: requestJson)
            return try Amba.decodeJSON(Message.self, from: json)
        }
    }

    public final class Moderation {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func reportUser(_ request: ReportRequest) async throws -> Report {
            let data = try JSONEncoder.amba.encode(request)
            let requestJson = String(data: data, encoding: .utf8) ?? "{}"
            let json = try await core.moderationReportUser(requestJson: requestJson)
            return try Amba.decodeJSON(Report.self, from: json)
        }
        public func reportContent(_ request: ReportRequest) async throws -> Report {
            let data = try JSONEncoder.amba.encode(request)
            let requestJson = String(data: data, encoding: .utf8) ?? "{}"
            let json = try await core.moderationReportContent(requestJson: requestJson)
            return try Amba.decodeJSON(Report.self, from: json)
        }
        public func reportStatus(id: String) async throws -> Report {
            let json = try await core.moderationGetReportStatus(id: id)
            return try Amba.decodeJSON(Report.self, from: json)
        }
    }

    public final class Reviews {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func list(targetType: String, targetId: String) async throws -> [Review] {
            let json = try await core.reviewsList(targetType: targetType, targetId: targetId)
            return try Amba.decodeJSON([Review].self, from: json)
        }
        public func create(_ params: ReviewCreate) async throws -> Review {
            let data = try JSONEncoder.amba.encode(params)
            let paramsJson = String(data: data, encoding: .utf8) ?? "{}"
            let json = try await core.reviewsCreate(paramsJson: paramsJson)
            return try Amba.decodeJSON(Review.self, from: json)
        }
        public func update(id: String, patch: ReviewUpdate) async throws -> Review {
            let data = try JSONEncoder.amba.encode(patch)
            let patchJson = String(data: data, encoding: .utf8) ?? "{}"
            let json = try await core.reviewsUpdate(id: id, patchJson: patchJson)
            return try Amba.decodeJSON(Review.self, from: json)
        }
        public func delete(id: String) async throws {
            try await core.reviewsDelete(id: id)
        }
    }

    public final class Roles {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func myRoles() async throws -> [Role] {
            let json = try await core.rolesGetMyRoles()
            return try Amba.decodeJSON([Role].self, from: json)
        }
        public func hasPermission(_ permission: String) async throws -> Bool {
            try await core.rolesHasPermission(permission: permission)
        }
    }

    public final class Referrals {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func referralCode() async throws -> ReferralCode {
            let json = try await core.referralsGetReferralCode()
            return try Amba.decodeJSON(ReferralCode.self, from: json)
        }
        public func claimReferral(code: String) async throws -> ReferralClaim {
            let json = try await core.referralsClaimReferral(code: code)
            return try Amba.decodeJSON(ReferralClaim.self, from: json)
        }
        public func create(code: String? = nil, maxUses: UInt32? = nil) async throws -> ReferralCode {
            let json = try await core.referralsCreate(code: code, maxUses: maxUses)
            return try Amba.decodeJSON(ReferralCode.self, from: json)
        }
    }

    // MARK: - Lifecycle namespaces

    public final class Catalog {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func list() async throws -> [CatalogItem] {
            let json = try await core.catalogList()
            return try Amba.decodeJSON([CatalogItem].self, from: json)
        }
        /// NEW in 4.0. Fetch a single catalog item by id.
        public func get(id: String) async throws -> CatalogItem {
            let json = try await core.catalogGet(itemId: id)
            return try Amba.decodeJSON(CatalogItem.self, from: json)
        }
    }

    public final class Content {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        /// `channel` is optional; when omitted, the server defaults to `"default"`.
        public func today(channel: String? = nil) async throws -> ContentItem? {
            let json = try await core.contentGetToday(channel: channel)
            return try Amba.decodeJSON(ContentItem?.self, from: json)
        }
        /// `channel` is optional (server defaults to `"default"`).
        /// `limit` caps the page size; `cursor` is the server-issued opaque
        /// pagination token returned by a previous call.
        public func library(
            channel: String? = nil,
            limit: UInt32? = nil,
            cursor: String? = nil
        ) async throws -> [ContentItem] {
            let json = try await core.contentGetLibrary(
                channel: channel,
                limit: limit,
                cursor: cursor
            )
            return try Amba.decodeJSON([ContentItem].self, from: json)
        }
        public func item(id: String) async throws -> ContentItem {
            let json = try await core.contentGetItem(id: id)
            return try Amba.decodeJSON(ContentItem.self, from: json)
        }
        public func updateItem(id: String, state: [String: Any]) async throws -> ContentItem {
            let stateData = try JSONSerialization.data(withJSONObject: state, options: [])
            let stateJson = String(data: stateData, encoding: .utf8) ?? "{}"
            let json = try await core.contentUpdateItem(id: id, stateJson: stateJson)
            return try Amba.decodeJSON(ContentItem.self, from: json)
        }
        public func createItem(channel: String, item: [String: Any]) async throws -> ContentItem {
            let itemData = try JSONSerialization.data(withJSONObject: item, options: [])
            let itemJson = String(data: itemData, encoding: .utf8) ?? "{}"
            let json = try await core.contentCreateItem(channel: channel, itemJson: itemJson)
            return try Amba.decodeJSON(ContentItem.self, from: json)
        }
    }

    public final class DeepLinks {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func get(shortCode: String) async throws -> DeepLink {
            let json = try await core.deepLinksGet(shortCode: shortCode)
            return try Amba.decodeJSON(DeepLink.self, from: json)
        }
        public func create(_ params: DeepLinkCreate) async throws -> DeepLink {
            let data = try JSONEncoder.amba.encode(params)
            let paramsJson = String(data: data, encoding: .utf8) ?? "{}"
            let json = try await core.deepLinksCreate(paramsJson: paramsJson)
            return try Amba.decodeJSON(DeepLink.self, from: json)
        }
    }

    public final class Onboarding {
        private let core: AmbaCoreFfiProtocol
        init(core: AmbaCoreFfiProtocol) { self.core = core }
        public func status() async throws -> OnboardingStatus {
            let json = try await core.onboardingGetStatus()
            return try Amba.decodeJSON(OnboardingStatus.self, from: json)
        }
        public func nextStep(payload: [String: Any]) async throws -> OnboardingStatus {
            let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])
            let payloadJson = String(data: payloadData, encoding: .utf8) ?? "{}"
            let json = try await core.onboardingNextStep(payloadJson: payloadJson)
            return try Amba.decodeJSON(OnboardingStatus.self, from: json)
        }
        public func skipStep() async throws -> OnboardingStatus {
            let json = try await core.onboardingSkipStep()
            return try Amba.decodeJSON(OnboardingStatus.self, from: json)
        }
        public func complete() async throws -> OnboardingStatus {
            let json = try await core.onboardingComplete()
            return try Amba.decodeJSON(OnboardingStatus.self, from: json)
        }
    }
}

// MARK: - Amba static facade (singleton-backed; same code path as AmbaClient)

/// Top-level amba SDK namespace. Hosts the singleton `AmbaClient`
/// installed by `Amba.configure(...)` and forwards every static API
/// through it.
///
/// Thread safety (item #13 / C-4 fix):
///
///   The singleton slot is guarded by `NSLock`. Pre-#13 the slot was
///   `nonisolated(unsafe) static var` — Swift's strict concurrency
///   checker tolerated it but concurrent read/write was still
///   undefined behavior in practice. The customer scenario was a
///   main-actor `configure(...)` racing with a background-task
///   `Amba.events.track(...)`: torn read of the class reference
///   crashed under load.
///
///   `configure(...)` is now **single-write** — calling it twice
///   without an intervening `reset()` throws `.alreadyConfigured`.
///   This mirrors the engine-side single-init guard (`amba_init`
///   returns `AlreadyInitialized` on second call — fix #9). The
///   customer migration is: explicit `Amba.reset()` first if
///   re-init is intentional.
///
///   Reads (the per-namespace facades) take the lock just long
///   enough to read the class reference, then release. The lock
///   does not span async work — namespace methods are themselves
///   async, but the lock is released before the await.
///
/// NSLock vs `OSAllocatedUnfairLock`: the modern unfair-lock
/// wrapper requires macOS 13+/iOS 16+, but `Package.swift` targets
/// macOS 12 / iOS 14. `NSLock` is correct on all our platforms and
/// fast enough that the difference doesn't show up under load.
public enum Amba {
    // Single backing storage + serialization primitive.
    nonisolated(unsafe) private static var sharedClient: AmbaClient?
    private static let lock = NSLock()

    /// Initialize the singleton. Must be called once before any other
    /// static API.
    ///
    /// Throws `AmbaSwiftError.alreadyConfigured` if a client is
    /// already installed. Call `Amba.reset()` first if re-init is
    /// intentional (e.g. tearing down a test fixture, or rotating
    /// credentials at runtime).
    public static func configure(
        apiKey: String,
        baseUrl: String? = nil,
        consentRequired: Bool = false,
        debug: Bool = false
    ) throws {
        // Fast pre-check: if we know we're already configured, fail
        // immediately rather than constructing a real `AmbaCoreFfi`
        // (which loads the native lib + initializes the Rust SDK —
        // expensive, and would also throw at the Rust layer).
        lock.lock()
        let alreadySet = sharedClient != nil
        lock.unlock()
        if alreadySet {
            throw AmbaSwiftError.alreadyConfigured
        }

        // Expensive construction outside the lock so concurrent reads
        // aren't blocked for the duration of UniFFI initialization.
        let newClient = try AmbaClient(
            apiKey: apiKey,
            baseUrl: baseUrl,
            consentRequired: consentRequired,
            debug: debug
        )

        // Commit. Re-check inside the lock because another thread may
        // have raced ahead between our pre-check and `AmbaClient(...)`
        // construction. Classic double-checked locking — safe because
        // both the check and the write happen under the lock.
        lock.lock()
        defer { lock.unlock() }
        if sharedClient != nil {
            throw AmbaSwiftError.alreadyConfigured
        }
        sharedClient = newClient
    }

    /// Clear the singleton so a fresh `configure(...)` can install a
    /// new client. Use for tests, credential rotation, or logout flows
    /// that intentionally want a clean slate.
    ///
    /// Reset wiring: dropping `sharedClient` releases the only Swift-side
    /// strong reference to `AmbaCoreFfi`. UniFFI's generated wrapper runs
    /// the Rust `Drop` impl on deallocation, which releases the
    /// `Arc<AmbaCore>` plus its persistence handles, HTTP pool, and
    /// identity slot. The UniFFI constructor (`AmbaCoreFfi(config:)`) is
    /// instance-scoped — it does NOT consult the C-FFI `amba_init`
    /// singleton slot — so a subsequent `configure(...)` constructs a
    /// fully independent core. Reset thus stops new calls from observing
    /// the old core; in-flight calls complete against the pre-reset state
    /// (same contract as the C FFI's `amba_reset` documented in
    /// `sdks/core/src/ffi.rs`).
    public static func reset() {
        lock.lock()
        defer { lock.unlock() }
        sharedClient = nil
    }

    /// Returns true if `configure(...)` has succeeded and no
    /// intervening `reset()` has cleared the slot.
    public static var isConfigured: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sharedClient != nil
    }

    /// Internal test seam — installs a pre-built client if the slot is
    /// empty, throwing `.alreadyConfigured` otherwise. Used by the
    /// concurrent-race tests to exercise the lock semantics without
    /// going through the real-Rust `AmbaCoreFfi(...)` constructor
    /// (which has its own single-init guard at the Rust layer + would
    /// dominate the test as a confounding variable).
    ///
    /// Only the install-when-empty op is exposed — there's no
    /// counterpart that overwrites. That's deliberate: the unsafe
    /// operation the original `Amba.core = newCore` seam allowed
    /// (silent overwrite) is the one we removed in #10 and don't
    /// reintroduce here.
    @discardableResult
    internal static func _installForTesting(_ client: AmbaClient) throws -> AmbaClient {
        lock.lock()
        defer { lock.unlock() }
        if sharedClient != nil {
            throw AmbaSwiftError.alreadyConfigured
        }
        sharedClient = client
        return client
    }

    private static func requireClient() throws -> AmbaClient {
        // Hold the lock just long enough to read the class reference.
        // The reference itself is ARC-retained on read, so the caller
        // sees a stable AmbaClient even after the lock releases.
        lock.lock()
        let client = sharedClient
        lock.unlock()
        guard let c = client else { throw AmbaSwiftError.notConfigured }
        return c
    }

    /// Module-internal accessor exposed for sibling namespace files
    /// (e.g. `Diagnostics.swift`) that need to route through the
    /// singleton without making `requireClient` part of the public
    /// surface. Same semantics as the private accessor above.
    internal static func _internalRequireClient() throws -> AmbaClient {
        try requireClient()
    }

    public static var anonymousId: String? { (try? requireClient())?.anonymousId }
    public static var appUserId: String? { (try? requireClient())?.appUserId }
    public static var isAuthenticated: Bool { (try? requireClient())?.isAuthenticated ?? false }
    public static func setDebug(_ enabled: Bool) { (try? requireClient())?.setDebug(enabled) }

    public enum events {
        public static func track(
            _ event: String,
            properties: [String: Any]? = nil,
            telemetry: Bool? = nil
        ) async throws {
            try await Amba.requireClient().events.track(
                event,
                properties: properties,
                telemetry: telemetry
            )
        }
    }

    public enum auth {
        public static func signInAnonymously() async throws -> AuthResultFfi {
            try await Amba.requireClient().auth.signInAnonymously()
        }
        public static func signInWithEmail(email: String, password: String) async throws -> AuthResultFfi {
            try await Amba.requireClient().auth.signInWithEmail(email: email, password: password)
        }
        public static func signUpWithEmail(email: String, password: String) async throws -> AuthResultFfi {
            try await Amba.requireClient().auth.signUpWithEmail(email: email, password: password)
        }
        public static func signInWithApple(identityToken: String) async throws -> AuthResultFfi {
            try await Amba.requireClient().auth.signInWithApple(identityToken: identityToken)
        }
        public static func signInWithGoogle(idToken: String) async throws -> AuthResultFfi {
            try await Amba.requireClient().auth.signInWithGoogle(idToken: idToken)
        }
        public static func requestEmailOtp(email: String) async throws {
            try await Amba.requireClient().auth.requestEmailOtp(email: email)
        }
        public static func verifyEmailOtp(email: String, code: String) async throws -> AuthResultFfi {
            try await Amba.requireClient().auth.verifyEmailOtp(email: email, code: code)
        }
        public static func requestSmsOtp(phone: String) async throws {
            try await Amba.requireClient().auth.requestSmsOtp(phone: phone)
        }
        public static func verifySmsOtp(phone: String, code: String) async throws -> AuthResultFfi {
            try await Amba.requireClient().auth.verifySmsOtp(phone: phone, code: code)
        }
        public static func requestMagicLink(email: String) async throws {
            try await Amba.requireClient().auth.requestMagicLink(email: email)
        }
        public static func verifyMagicLink(token: String) async throws -> AuthResultFfi {
            try await Amba.requireClient().auth.verifyMagicLink(token: token)
        }
        public static func linkAccount(provider: String, credential: String) async throws -> AuthResultFfi {
            try await Amba.requireClient().auth.linkAccount(provider: provider, credential: credential)
        }
        public static func signOut(rotateAnonymousId: Bool = false) async throws {
            try await Amba.requireClient().auth.signOut(rotateAnonymousId: rotateAnonymousId)
        }
        public static func refresh() async throws -> AuthResultFfi {
            try await Amba.requireClient().auth.refresh()
        }
        public static func me() async throws -> UserFfi {
            try await Amba.requireClient().auth.me()
        }
        // ── Phase A parity ─────────────────────────────────────────
        public static func getSession() async throws -> Session? {
            try await Amba.requireClient().auth.getSession()
        }
        public static func getAnonymousId() async throws -> String {
            let client = try Amba.requireClient()
            return await client.auth.getAnonymousId()
        }
        @discardableResult
        public static func onAuthStateChange(_ callback: @escaping (Session?) -> Void) throws -> () -> Void {
            try Amba.requireClient().auth.onAuthStateChange(callback)
        }
    }

    public enum users {
        public static func get(userId: String? = nil) async throws -> UserFfi {
            try await Amba.requireClient().users.get(userId: userId)
        }
        public static func update(userId: String? = nil, patch: [String: Any]) async throws -> UserFfi {
            try await Amba.requireClient().users.update(userId: userId, patch: patch)
        }
    }

    public enum sessions {
        public static func list() async throws -> [AppSession] {
            try await Amba.requireClient().sessions.list()
        }
        public static func revoke(sessionId: String) async throws {
            try await Amba.requireClient().sessions.revoke(sessionId: sessionId)
        }
    }

    public enum sync {
        public static func pushChanges(_ changes: [SyncChange]) async throws -> PushChangesResult {
            try await Amba.requireClient().sync.pushChanges(changes)
        }
        public static func pullChanges(since: PullSince) async throws -> PullChangesResult {
            try await Amba.requireClient().sync.pullChanges(since: since)
        }
    }

    public enum collections {
        public static func find<T: Decodable>(_ name: String, options: FindOptions = FindOptions(), as type: T.Type = T.self) async throws -> FindResponse<T> {
            try await Amba.requireClient().collections.find(name, options: options, as: T.self)
        }
        public static func findOne<T: Decodable>(_ name: String, id: String, as type: T.Type = T.self) async throws -> T {
            try await Amba.requireClient().collections.findOne(name, id: id, as: T.self)
        }
        public static func insert<T: Decodable>(_ name: String, row: [String: Any], as type: T.Type = T.self) async throws -> T {
            try await Amba.requireClient().collections.insert(name, row: row, as: T.self)
        }
        public static func update<T: Decodable>(_ name: String, id: String, set: [String: Any], as type: T.Type = T.self) async throws -> T {
            try await Amba.requireClient().collections.update(name, id: id, set: set, as: T.self)
        }
        public static func delete(_ name: String, id: String) async throws {
            try await Amba.requireClient().collections.delete(name, id: id)
        }
        public static func findNearest<T: Decodable>(
            _ name: String,
            vectorField: String,
            queryVector: [Float],
            k: UInt32,
            filter: AnyEncodable? = nil,
            as type: T.Type = T.self
        ) async throws -> [T] {
            try await Amba.requireClient().collections.findNearest(name, vectorField: vectorField, queryVector: queryVector, k: k, filter: filter, as: T.self)
        }
        public static func count(_ name: String, filter: AnyEncodable? = nil) async throws -> UInt64 {
            try await Amba.requireClient().collections.count(name, filter: filter)
        }
    }

    public enum storage {
        public static func presign(bucket: String, filename: String, mimeType: String, sizeBytes: UInt64, retentionDays: UInt32? = nil) async throws -> PresignDataFfi {
            try await Amba.requireClient().storage.presign(bucket: bucket, filename: filename, mimeType: mimeType, sizeBytes: sizeBytes, retentionDays: retentionDays)
        }
        public static func commit(uploadId: String, assetId: String) async throws -> MediaAssetFfi {
            try await Amba.requireClient().storage.commit(uploadId: uploadId, assetId: assetId)
        }
        public static func upload(bucket: String, data: Data, filename: String, mimeType: String, retentionDays: UInt32? = nil) async throws -> MediaAssetFfi {
            try await Amba.requireClient().storage.upload(bucket: bucket, data: data, filename: filename, mimeType: mimeType, retentionDays: retentionDays)
        }
        public static func list(prefix: String? = nil) async throws -> [MediaAssetSummary] {
            try await Amba.requireClient().storage.list(prefix: prefix)
        }
        public static func delete(assetId: String) async throws {
            try await Amba.requireClient().storage.delete(assetId: assetId)
        }
        public static func download(assetId: String) async throws -> Data {
            try await Amba.requireClient().storage.download(assetId: assetId)
        }
    }

    public enum push {
        public static func register(token: String, platform: PushPlatformFfi, bundleId: String? = nil) async throws -> PushTokenFfi {
            try await Amba.requireClient().push.register(token: token, platform: platform, bundleId: bundleId)
        }
        public static func subscribe(topic: String) async throws {
            try await Amba.requireClient().push.subscribe(topic: topic)
        }
        public static func unregister(token: String) async throws {
            try await Amba.requireClient().push.unregister(token: token)
        }
        public static func unsubscribe(topic: String) async throws {
            try await Amba.requireClient().push.unsubscribe(topic: topic)
        }
        public static func getTokens() async throws -> [PushToken] {
            try await Amba.requireClient().push.getTokens()
        }
    }

    public enum entitlements {
        public static func list() async throws -> [UserEntitlementFfi] {
            try await Amba.requireClient().entitlements.list()
        }
        public static func has(_ name: String) async -> Bool {
            guard let c = try? requireClient() else { return false }
            return await c.entitlements.has(name)
        }
    }

    public enum ai {
        public enum anthropic {
            public enum messages {
                public static func create(request: AiMessageRequest) async throws -> AiMessageResponse {
                    try await Amba.requireClient().ai.anthropic.messages.create(request: request)
                }
            }
        }
    }

    public enum config {
        public static func fetch() async throws -> ConfigBundle {
            try await Amba.requireClient().config.fetch()
        }
    }

    public enum flags {
        public static func fetch() async throws -> [FlagAssignmentFfi] {
            try await Amba.requireClient().flags.fetch()
        }
        /// Single-flag lookup (SDK 4.0). Returns `nil` for unknown
        /// or disabled keys.
        public static func get(key: String) async throws -> FlagAssignmentFfi? {
            try await Amba.requireClient().flags.get(key: key)
        }
    }

    // MARK: - Gamification static facade

    public enum achievements {
        public static func all() async throws -> [Achievement] {
            try await Amba.requireClient().achievements.all()
        }
        public static func progress() async throws -> [AchievementProgress] {
            try await Amba.requireClient().achievements.progress()
        }
    }

    public enum challenges {
        public static func active() async throws -> [Challenge] {
            try await Amba.requireClient().challenges.active()
        }
        public static func get(id: String) async throws -> Challenge {
            try await Amba.requireClient().challenges.get(id: id)
        }
        public static func progress(id: String) async throws -> ChallengeProgress {
            try await Amba.requireClient().challenges.progress(id: id)
        }
        public static func claim(id: String) async throws -> ChallengeProgress {
            try await Amba.requireClient().challenges.claim(id: id)
        }
    }

    public enum currencies {
        public static func balance() async throws -> [CurrencyBalance] {
            try await Amba.requireClient().currencies.balance()
        }
        public static func transactions(currencyKey: String) async throws -> [CurrencyTransaction] {
            try await Amba.requireClient().currencies.transactions(currencyKey: currencyKey)
        }
    }

    public enum inventory {
        public static func items() async throws -> [InventoryItem] {
            try await Amba.requireClient().inventory.items()
        }
        public static func item(id: String) async throws -> InventoryItem {
            try await Amba.requireClient().inventory.item(id: id)
        }
        public static func purchase(_ request: PurchaseRequest) async throws -> InventoryItem {
            try await Amba.requireClient().inventory.purchase(request)
        }
        public static func consume(_ request: ConsumeRequest) async throws -> InventoryItem {
            try await Amba.requireClient().inventory.consume(request)
        }
    }

    public enum leaderboards {
        public static func get(key: String) async throws -> Leaderboard {
            try await Amba.requireClient().leaderboards.get(key: key)
        }
        public static func entries(key: String, limit: UInt32? = nil) async throws -> [LeaderboardEntry] {
            try await Amba.requireClient().leaderboards.entries(key: key, limit: limit)
        }
        public static func myRank(key: String) async throws -> LeaderboardEntry {
            try await Amba.requireClient().leaderboards.myRank(key: key)
        }
    }

    public enum stores {
        public static func list() async throws -> [Store] {
            try await Amba.requireClient().stores.list()
        }
        public static func purchaseOptions(storeKey: String) async throws -> [PurchaseOption] {
            try await Amba.requireClient().stores.purchaseOptions(storeKey: storeKey)
        }
        public static func purchase(storeKey: String, purchaseOptionId: String, receipt: [String: Any]) async throws -> PurchaseResult {
            try await Amba.requireClient().stores.purchase(storeKey: storeKey, purchaseOptionId: purchaseOptionId, receipt: receipt)
        }
    }

    public enum xp {
        public static func balance() async throws -> XpBalance {
            try await Amba.requireClient().xp.balance()
        }
        public static func history(limit: UInt32? = nil) async throws -> [XpTransaction] {
            try await Amba.requireClient().xp.history(limit: limit)
        }
        public static func claim(grantKey: String) async throws -> XpTransaction {
            try await Amba.requireClient().xp.claim(grantKey: grantKey)
        }
    }

    public enum streaks {
        public static func all() async throws -> [Streak] {
            try await Amba.requireClient().streaks.all()
        }
        public static func qualify(streakKey: String) async throws -> Streak {
            try await Amba.requireClient().streaks.qualify(streakKey: streakKey)
        }
    }

    public enum leagues {
        public static func me() async throws -> LeagueMembership {
            try await Amba.requireClient().leagues.me()
        }
        public static func cohort() async throws -> LeagueCohortResponse {
            try await Amba.requireClient().leagues.cohort()
        }
    }

    // MARK: - Social static facade

    public enum feeds {
        public static func activity(feed: String? = nil, cursor: String? = nil) async throws -> FeedResponse {
            try await Amba.requireClient().feeds.activity(feed: feed, cursor: cursor)
        }
    }

    public enum friends {
        public static func list() async throws -> [Friendship] {
            try await Amba.requireClient().friends.list()
        }
        public static func friends() async throws -> [Friendship] {
            try await Amba.requireClient().friends.friends()
        }
        public static func sendRequest(userId: String) async throws -> Friendship {
            try await Amba.requireClient().friends.sendRequest(userId: userId)
        }
        public static func acceptRequest(friendshipId: String) async throws -> Friendship {
            try await Amba.requireClient().friends.acceptRequest(friendshipId: friendshipId)
        }
        public static func declineRequest(friendshipId: String) async throws {
            try await Amba.requireClient().friends.declineRequest(friendshipId: friendshipId)
        }
        public static func blockUser(userId: String) async throws -> Friendship {
            try await Amba.requireClient().friends.blockUser(userId: userId)
        }
        public static func unblockUser(userId: String) async throws {
            try await Amba.requireClient().friends.unblockUser(userId: userId)
        }
        public static func removeBlock(friendshipId: String) async throws {
            try await Amba.requireClient().friends.removeBlock(friendshipId: friendshipId)
        }
        /// Unfriend by the other user's id (SDK 4.0).
        public static func removeFriend(userId: String) async throws {
            try await Amba.requireClient().friends.removeFriend(userId: userId)
        }
    }

    public enum groups {
        public static func create(_ params: GroupCreate) async throws -> Group {
            try await Amba.requireClient().groups.create(params)
        }
        public static func get(id: String) async throws -> Group {
            try await Amba.requireClient().groups.get(id: id)
        }
        public static func update(id: String, patch: GroupUpdate) async throws -> Group {
            try await Amba.requireClient().groups.update(id: id, patch: patch)
        }
        public static func delete(id: String) async throws {
            try await Amba.requireClient().groups.delete(id: id)
        }
        public static func members(id: String) async throws -> [GroupMember] {
            try await Amba.requireClient().groups.members(id: id)
        }
        public static func join(id: String) async throws -> GroupMember {
            try await Amba.requireClient().groups.join(id: id)
        }
        public static func leave(id: String) async throws {
            try await Amba.requireClient().groups.leave(id: id)
        }
        public static func invite(id: String, userId: String) async throws -> GroupMember {
            try await Amba.requireClient().groups.invite(id: id, userId: userId)
        }
    }

    public enum messaging {
        public static func conversations() async throws -> [Conversation] {
            try await Amba.requireClient().messaging.conversations()
        }
        public static func createConversation(
            participants: [String],
            metadata: [String: Any]? = nil
        ) async throws -> Conversation {
            try await Amba.requireClient().messaging.createConversation(participants: participants, metadata: metadata)
        }
        public static func listMessages(
            conversationId: String,
            limit: UInt32? = nil,
            offset: UInt32? = nil
        ) async throws -> [Message] {
            try await Amba.requireClient().messaging.listMessages(
                conversationId: conversationId,
                limit: limit,
                offset: offset
            )
        }
        public static func markRead(conversationId: String) async throws {
            try await Amba.requireClient().messaging.markRead(conversationId: conversationId)
        }
        public static func getMessage(conversationId: String, messageId: String) async throws -> Message? {
            try await Amba.requireClient().messaging.getMessage(conversationId: conversationId, messageId: messageId)
        }
        public static func sendMessage(_ request: SendMessageRequest) async throws -> Message {
            try await Amba.requireClient().messaging.sendMessage(request)
        }
    }

    public enum moderation {
        public static func reportUser(_ request: ReportRequest) async throws -> Report {
            try await Amba.requireClient().moderation.reportUser(request)
        }
        public static func reportContent(_ request: ReportRequest) async throws -> Report {
            try await Amba.requireClient().moderation.reportContent(request)
        }
        public static func reportStatus(id: String) async throws -> Report {
            try await Amba.requireClient().moderation.reportStatus(id: id)
        }
    }

    public enum reviews {
        public static func list(targetType: String, targetId: String) async throws -> [Review] {
            try await Amba.requireClient().reviews.list(targetType: targetType, targetId: targetId)
        }
        public static func create(_ params: ReviewCreate) async throws -> Review {
            try await Amba.requireClient().reviews.create(params)
        }
        public static func update(id: String, patch: ReviewUpdate) async throws -> Review {
            try await Amba.requireClient().reviews.update(id: id, patch: patch)
        }
        public static func delete(id: String) async throws {
            try await Amba.requireClient().reviews.delete(id: id)
        }
    }

    public enum roles {
        public static func myRoles() async throws -> [Role] {
            try await Amba.requireClient().roles.myRoles()
        }
        public static func hasPermission(_ permission: String) async throws -> Bool {
            try await Amba.requireClient().roles.hasPermission(permission)
        }
    }

    public enum referrals {
        public static func referralCode() async throws -> ReferralCode {
            try await Amba.requireClient().referrals.referralCode()
        }
        public static func claimReferral(code: String) async throws -> ReferralClaim {
            try await Amba.requireClient().referrals.claimReferral(code: code)
        }
        public static func create(code: String? = nil, maxUses: UInt32? = nil) async throws -> ReferralCode {
            try await Amba.requireClient().referrals.create(code: code, maxUses: maxUses)
        }
    }

    // MARK: - Lifecycle static facade

    public enum catalog {
        public static func list() async throws -> [CatalogItem] {
            try await Amba.requireClient().catalog.list()
        }
        public static func get(id: String) async throws -> CatalogItem {
            try await Amba.requireClient().catalog.get(id: id)
        }
    }

    public enum content {
        public static func today(channel: String? = nil) async throws -> ContentItem? {
            try await Amba.requireClient().content.today(channel: channel)
        }
        public static func library(
            channel: String? = nil,
            limit: UInt32? = nil,
            cursor: String? = nil
        ) async throws -> [ContentItem] {
            try await Amba.requireClient().content.library(
                channel: channel,
                limit: limit,
                cursor: cursor
            )
        }
        public static func item(id: String) async throws -> ContentItem {
            try await Amba.requireClient().content.item(id: id)
        }
        public static func updateItem(id: String, state: [String: Any]) async throws -> ContentItem {
            try await Amba.requireClient().content.updateItem(id: id, state: state)
        }
        public static func createItem(channel: String, item: [String: Any]) async throws -> ContentItem {
            try await Amba.requireClient().content.createItem(channel: channel, item: item)
        }
    }

    public enum deepLinks {
        public static func get(shortCode: String) async throws -> DeepLink {
            try await Amba.requireClient().deepLinks.get(shortCode: shortCode)
        }
        public static func create(_ params: DeepLinkCreate) async throws -> DeepLink {
            try await Amba.requireClient().deepLinks.create(params)
        }
    }

    public enum onboarding {
        public static func status() async throws -> OnboardingStatus {
            try await Amba.requireClient().onboarding.status()
        }
        public static func nextStep(payload: [String: Any]) async throws -> OnboardingStatus {
            try await Amba.requireClient().onboarding.nextStep(payload: payload)
        }
        public static func skipStep() async throws -> OnboardingStatus {
            try await Amba.requireClient().onboarding.skipStep()
        }
        public static func complete() async throws -> OnboardingStatus {
            try await Amba.requireClient().onboarding.complete()
        }
    }

    // MARK: - Internal helpers

    /// Decode a Rust-side JSON-string payload into a typed Swift value.
    /// Internal — the namespace wrappers above are the public surface.
    internal static func decodeJSON<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw AmbaSwiftError.decode("not utf8")
        }
        return try JSONDecoder.amba.decode(T.self, from: data)
    }
}

// MARK: - Public types

/// Snapshot of the current auth session as visible to the SDK consumer.
///
/// `sessionToken` / `refreshToken` / `expiresAt` are SDK-managed and
/// held internally for the auto-refresh dance — they're empty strings
/// on the consumer side, present for shape-compatibility across the
/// amba SDK family. Callers who need to introspect should branch on
/// `user` / `Amba.isAuthenticated`.
public struct Session: Equatable, @unchecked Sendable {
    public let sessionToken: String
    public let refreshToken: String
    public let user: UserFfi
    public let expiresAt: String

    public init(sessionToken: String = "", refreshToken: String = "", user: UserFfi, expiresAt: String = "") {
        self.sessionToken = sessionToken
        self.refreshToken = refreshToken
        self.user = user
        self.expiresAt = expiresAt
    }

    public static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.sessionToken == rhs.sessionToken
            && lhs.refreshToken == rhs.refreshToken
            && lhs.expiresAt == rhs.expiresAt
            && lhs.user.id == rhs.user.id
            && lhs.user.anonymousId == rhs.user.anonymousId
    }
}

public struct FindOptions: Encodable {
    public var filter: AnyEncodable?
    public var order: [OrderBy]?
    public var limit: UInt32?
    public var cursor: String?
    public var select: [String]?
    public var includeDeleted: Bool?

    public init(filter: AnyEncodable? = nil, order: [OrderBy]? = nil, limit: UInt32? = nil, cursor: String? = nil, select: [String]? = nil, includeDeleted: Bool? = nil) {
        self.filter = filter
        self.order = order
        self.limit = limit
        self.cursor = cursor
        self.select = select
        self.includeDeleted = includeDeleted
    }
    enum CodingKeys: String, CodingKey {
        case filter, order, limit, cursor, select
        case includeDeleted = "include_deleted"
    }
}

public struct OrderBy: Codable {
    public let column: String
    public let direction: Direction
    public enum Direction: String, Codable { case asc, desc }
    public init(column: String, direction: Direction) {
        self.column = column
        self.direction = direction
    }
}

public struct FindResponse<T: Decodable>: Decodable {
    public let data: [T]
    public let nextCursor: String?
    public let hasMore: Bool
    enum CodingKeys: String, CodingKey {
        case data
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

public struct AiMessageRequest: Encodable {
    public let promptSlug: String
    public let variables: AnyEncodable?
    public let maxTokens: UInt32?
    public let temperature: Float?
    public let enablePromptCache: Bool?

    public init(promptSlug: String, variables: AnyEncodable? = nil, maxTokens: UInt32? = nil, temperature: Float? = nil, enablePromptCache: Bool? = nil) {
        self.promptSlug = promptSlug
        self.variables = variables
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.enablePromptCache = enablePromptCache
    }
    enum CodingKeys: String, CodingKey {
        case promptSlug = "prompt_slug"
        case variables
        case maxTokens = "max_tokens"
        case temperature
        case enablePromptCache = "enable_prompt_cache"
    }
}

public struct AiUsage: Codable {
    public let inputTokens: UInt32
    public let outputTokens: UInt32
    public let cacheCreationInputTokens: UInt32?
    public let cacheReadInputTokens: UInt32?
    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}

public struct AiMessageResponse: Decodable {
    public let content: [AnyDecodable]
    public let usage: AiUsage
    public let stopReason: String?
    public let model: String
    enum CodingKeys: String, CodingKey {
        case content, usage, model
        case stopReason = "stop_reason"
    }
}

/// Resolved remote config returned by `Amba.config.fetch()`.
///
/// Server: `GET /v1/client/config` returns body `{ "data": { key → value } }`
/// plus an `ETag` response header carrying the version stamp. The engine
/// core lifts the `data` map into `values` and parses the ETag prefix
/// into `version`. `version` is `nil` when the server didn't send an
/// ETag (e.g. an empty `config_versions` row on a brand-new project).
///
/// Earlier SDK versions decoded a `generated_at` field that didn't exist
/// on the wire — that drift broke `config.fetch()` end-to-end and is
/// fixed in this commit (Item 5 / task #12).
public struct ConfigBundle: Decodable {
    public let version: String?
    public let values: AnyDecodable
}

public struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    public init<T: Encodable>(_ value: T) {
        _encode = { encoder in try value.encode(to: encoder) }
    }
    public func encode(to encoder: Encoder) throws { try _encode(encoder) }
}

public struct AnyDecodable: Codable {
    public let value: Any
    public init(_ value: Any) {
        self.value = value
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let b = try? container.decode(Bool.self) {
            value = b
        } else if let n = try? container.decode(Int64.self) {
            value = n
        } else if let n = try? container.decode(Double.self) {
            value = n
        } else if let s = try? container.decode(String.self) {
            value = s
        } else if let arr = try? container.decode([AnyDecodable].self) {
            value = arr.map { $0.value }
        } else if let obj = try? container.decode([String: AnyDecodable].self) {
            value = obj.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    /// `Encodable` conformance round-trips the decoded JSON value. Used
    /// when a struct holding an `AnyDecodable?` is itself re-encoded
    /// (rare on customer code paths but required for Swift to synthesize
    /// `Codable` on those parent structs).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let b as Bool:
            try container.encode(b)
        case let i as Int:
            try container.encode(i)
        case let i as Int64:
            try container.encode(i)
        case let d as Double:
            try container.encode(d)
        case let f as Float:
            try container.encode(f)
        case let s as String:
            try container.encode(s)
        case let arr as [Any]:
            try container.encode(arr.map { AnyDecodable($0) })
        case let obj as [String: Any]:
            try container.encode(obj.mapValues { AnyDecodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

public enum AmbaSwiftError: Error, Equatable {
    case notConfigured
    case decode(String)
    case uploadFailed
    case invalidConfig(String)
    /// `Amba.configure(...)` was called while a client was already
    /// installed. Call `Amba.reset()` first if re-init is intentional.
    case alreadyConfigured
}

extension JSONDecoder {
    static let amba: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()
}

extension JSONEncoder {
    static let amba: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()
}

public let SDK_VERSION = "4.0.1"

// MARK: - SDK 4.0 NEW types (sessions / sync / leagues / storage / collections)

/// Server-tracked app session row surfaced by `sessions.list()`. Mirrors
/// `sdks/core/src/sessions.rs::AppSession`.
public struct AppSession: Codable, Equatable {
    public let id: String
    public let userId: String
    public let startedAt: Date
    public let endedAt: Date?
    public let durationSecs: UInt32?
    public let metadata: AnyDecodable?

    enum CodingKeys: String, CodingKey {
        case id, metadata
        case userId = "user_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSecs = "duration_secs"
    }

    public static func == (lhs: AppSession, rhs: AppSession) -> Bool {
        lhs.id == rhs.id && lhs.userId == rhs.userId &&
            lhs.startedAt == rhs.startedAt && lhs.endedAt == rhs.endedAt &&
            lhs.durationSecs == rhs.durationSecs
    }
}

/// A single buffered mutation the client is replaying. Mirrors
/// `sdks/core/src/sync.rs::SyncChange` field-for-field.
public struct SyncChange: Codable, Equatable {
    public let entityType: String
    public let entityId: String
    /// One of `"insert"`, `"update"`, `"delete"`.
    public let action: String
    public let data: AnyEncodableDecodable?
    /// Client-side ISO-8601 timestamp captured when the mutation occurred.
    public let clientTimestamp: String

    public init(
        entityType: String,
        entityId: String,
        action: String,
        data: AnyEncodableDecodable? = nil,
        clientTimestamp: String
    ) {
        self.entityType = entityType
        self.entityId = entityId
        self.action = action
        self.data = data
        self.clientTimestamp = clientTimestamp
    }

    enum CodingKeys: String, CodingKey {
        case action, data
        case entityType = "entity_type"
        case entityId = "entity_id"
        case clientTimestamp = "client_timestamp"
    }

    public static func == (lhs: SyncChange, rhs: SyncChange) -> Bool {
        lhs.entityType == rhs.entityType && lhs.entityId == rhs.entityId &&
            lhs.action == rhs.action && lhs.clientTimestamp == rhs.clientTimestamp
    }
}

/// Per-row conflict surfaced by `sync.pushChanges`. `resolution` is
/// always `"server_wins"` today.
public struct SyncConflict: Codable, Equatable {
    public let entityType: String
    public let entityId: String
    public let resolution: String
    public let serverData: AnyDecodable?

    enum CodingKeys: String, CodingKey {
        case resolution
        case entityType = "entity_type"
        case entityId = "entity_id"
        case serverData = "server_data"
    }

    public static func == (lhs: SyncConflict, rhs: SyncConflict) -> Bool {
        lhs.entityType == rhs.entityType && lhs.entityId == rhs.entityId &&
            lhs.resolution == rhs.resolution
    }
}

/// Reply from `sync.pushChanges`. `applied` is the count the server
/// accepted; `conflicts` carries any server-wins resolutions; the
/// `checkpointToken` is the opaque cursor to pass to the next
/// `pullChanges` call.
public struct PushChangesResult: Codable, Equatable {
    public let applied: UInt32
    public let conflicts: [SyncConflict]
    public let checkpointToken: String

    enum CodingKeys: String, CodingKey {
        case applied, conflicts
        case checkpointToken = "checkpoint_token"
    }
}

/// Reply from `sync.pullChanges`. `changes` is the batch of remote-origin
/// mutations the caller should apply to their local cache.
public struct PullChangesResult: Codable, Equatable {
    public let changes: [SyncChange]
    public let checkpointToken: String
    public let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case changes
        case checkpointToken = "checkpoint_token"
        case hasMore = "has_more"
    }
}

/// Cursor input to `sync.pullChanges`. `entityType` is required; the
/// optional `checkpointToken` is omitted on the first pull.
public struct PullSince: Codable, Equatable {
    public let entityType: String
    public let checkpointToken: String?

    public init(entityType: String, checkpointToken: String? = nil) {
        self.entityType = entityType
        self.checkpointToken = checkpointToken
    }

    enum CodingKeys: String, CodingKey {
        case entityType = "entity_type"
        case checkpointToken = "checkpoint_token"
    }
}

/// Current user's weekly league standing. `cohort` / `league` / `rank`
/// are `nil` until the user's first Monday cohort assignment runs.
public struct LeagueMembership: Codable, Equatable {
    public let cohort: LeagueCohort?
    public let league: LeagueTier?
    public let rank: UInt32?
    public let score: Int64
    public let memberCount: UInt32

    enum CodingKeys: String, CodingKey {
        case cohort, league, rank, score
        case memberCount = "member_count"
    }
}

/// Cohort metadata the user currently belongs to.
public struct LeagueCohort: Codable, Equatable {
    public let id: String
    public let leagueId: String
    /// ISO-8601 date (`YYYY-MM-DD`) — the Monday that opens the cohort's
    /// 7-day window. Kept as a String because Swift's default Date
    /// decoder expects ISO-8601 timestamps, not bare dates.
    public let weekStart: String
    /// Server-side lifecycle: `"active"`, `"settling"`, `"closed"`.
    public let status: String

    enum CodingKeys: String, CodingKey {
        case id, status
        case leagueId = "league_id"
        case weekStart = "week_start"
    }
}

/// League tier metadata. `tierOrder` ascends from bottom tier (1) upward.
public struct LeagueTier: Codable, Equatable {
    public let id: String
    public let name: String
    public let tierOrder: Int32

    enum CodingKeys: String, CodingKey {
        case id, name
        case tierOrder = "tier_order"
    }
}

/// Anonymised cohort member returned by `leagues.cohort()`. Notably no
/// `userId` — only the user-picked `displayName` is exposed.
public struct LeagueCohortMember: Codable, Equatable {
    public let displayName: String?
    public let score: Int64
    public let rank: UInt32

    enum CodingKeys: String, CodingKey {
        case score, rank
        case displayName = "display_name"
    }
}

/// Reply from `leagues.cohort()`. `cohort` / `league` are `nil` for users
/// not yet assigned to a cohort.
public struct LeagueCohortResponse: Codable, Equatable {
    public let cohort: LeagueCohort?
    public let league: LeagueTier?
    public let members: [LeagueCohortMember]
}

/// Summary row returned by `storage.list()`. Subset of `MediaAssetFfi` —
/// the server omits `width` / `height` / `retentionDays` on the list
/// endpoint to keep the response cheap.
public struct MediaAssetSummary: Codable, Equatable {
    public let id: String
    public let bucket: String
    public let key: String
    public let url: String
    public let mimeType: String
    public let sizeBytes: UInt64
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, bucket, key, url
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case createdAt = "created_at"
    }
}

/// Internal wrapper for the `storage.list` JSON envelope. Server returns
/// `{ "data": [MediaAssetSummary, …] }`.
struct StorageListResponse: Decodable {
    let data: [MediaAssetSummary]
}

/// Internal wrapper for `collections.findNearest` — server returns
/// `{ "data": [row, …] }` where each row decodes to the caller's `T`.
struct NearestResponse<T: Decodable>: Decodable {
    let data: [T]
}

/// Internal wrapper for `collections.count` — server returns
/// `{ "data": { "count": N } }`.
struct CountResponse: Decodable {
    let data: CountInner
    struct CountInner: Decodable {
        let count: UInt64
    }
}

/// Options for `collections.findNearest`. Wire shape matches
/// `sdks/core/src/collections.rs::NearestOptions`.
struct NearestOptions: Encodable {
    let vectorField: String
    let queryVector: [Float]
    let k: UInt32
    let filter: AnyEncodable?

    enum CodingKeys: String, CodingKey {
        case k, filter
        case vectorField = "vector_field"
        case queryVector = "query_vector"
    }
}

// MARK: - Gamification types

public struct Achievement: Codable, Equatable {
    public let id: String
    public let key: String
    public let name: String
    public let description: String?
    public let iconUrl: String?
    public let xpReward: UInt32
    public let criteria: AnyDecodable?

    enum CodingKeys: String, CodingKey {
        case id, key, name, description, criteria
        case iconUrl = "icon_url"
        case xpReward = "xp_reward"
    }

    public static func == (lhs: Achievement, rhs: Achievement) -> Bool {
        lhs.id == rhs.id && lhs.key == rhs.key && lhs.name == rhs.name &&
            lhs.description == rhs.description && lhs.iconUrl == rhs.iconUrl &&
            lhs.xpReward == rhs.xpReward
    }
}

public struct AchievementProgress: Codable, Equatable {
    public let achievementId: String
    public let key: String
    public let progress: Float
    public let unlocked: Bool
    public let unlockedAt: Date?

    enum CodingKeys: String, CodingKey {
        case key, progress, unlocked
        case achievementId = "achievement_id"
        case unlockedAt = "unlocked_at"
    }
}

public struct Challenge: Codable, Equatable {
    public let id: String
    public let key: String
    public let name: String
    public let description: String?
    public let startsAt: Date
    public let endsAt: Date
    public let criteria: AnyDecodable?
    public let reward: AnyDecodable?

    enum CodingKeys: String, CodingKey {
        case id, key, name, description, criteria, reward
        case startsAt = "starts_at"
        case endsAt = "ends_at"
    }

    public static func == (lhs: Challenge, rhs: Challenge) -> Bool {
        lhs.id == rhs.id && lhs.key == rhs.key && lhs.name == rhs.name &&
            lhs.description == rhs.description && lhs.startsAt == rhs.startsAt &&
            lhs.endsAt == rhs.endsAt
    }
}

public struct ChallengeProgress: Codable, Equatable {
    public let challengeId: String
    public let progress: Float
    public let completed: Bool
    public let claimed: Bool
    public let completedAt: Date?
    public let claimedAt: Date?

    enum CodingKeys: String, CodingKey {
        case progress, completed, claimed
        case challengeId = "challenge_id"
        case completedAt = "completed_at"
        case claimedAt = "claimed_at"
    }
}

public struct CurrencyBalance: Codable, Equatable {
    public let currencyId: String
    public let key: String
    public let balance: Int64
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case key, balance
        case currencyId = "currency_id"
        case updatedAt = "updated_at"
    }
}

public struct CurrencyTransaction: Codable, Equatable {
    public let id: String
    public let currencyId: String
    public let delta: Int64
    public let balanceAfter: Int64
    public let reason: String?
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, delta, reason
        case currencyId = "currency_id"
        case balanceAfter = "balance_after"
        case createdAt = "created_at"
    }
}

public struct InventoryItem: Codable, Equatable {
    public let id: String
    public let catalogItemId: String
    public let sku: String
    public let quantity: UInt32
    public let acquiredAt: Date
    public let metadata: AnyDecodable?

    enum CodingKeys: String, CodingKey {
        case id, sku, quantity, metadata
        case catalogItemId = "catalog_item_id"
        case acquiredAt = "acquired_at"
    }

    public static func == (lhs: InventoryItem, rhs: InventoryItem) -> Bool {
        lhs.id == rhs.id && lhs.catalogItemId == rhs.catalogItemId &&
            lhs.sku == rhs.sku && lhs.quantity == rhs.quantity &&
            lhs.acquiredAt == rhs.acquiredAt
    }
}

public struct PurchaseRequest: Codable, Equatable {
    public let sku: String
    public let quantity: UInt32?
    public let currencyKey: String?

    public init(sku: String, quantity: UInt32? = nil, currencyKey: String? = nil) {
        self.sku = sku
        self.quantity = quantity
        self.currencyKey = currencyKey
    }

    enum CodingKeys: String, CodingKey {
        case sku, quantity
        case currencyKey = "currency_key"
    }
}

public struct ConsumeRequest: Codable, Equatable {
    public let itemId: String
    public let quantity: UInt32

    public init(itemId: String, quantity: UInt32) {
        self.itemId = itemId
        self.quantity = quantity
    }

    enum CodingKeys: String, CodingKey {
        case quantity
        case itemId = "item_id"
    }
}

public struct Leaderboard: Codable, Equatable {
    public let id: String
    public let key: String
    public let name: String
    public let period: String
    public let direction: String
    public let startsAt: Date?
    public let endsAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, key, name, period, direction
        case startsAt = "starts_at"
        case endsAt = "ends_at"
    }
}

public struct LeaderboardEntry: Codable, Equatable {
    public let rank: UInt32
    public let userId: String
    public let displayName: String?
    public let avatarUrl: String?
    public let score: Double

    enum CodingKeys: String, CodingKey {
        case rank, score
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
    }
}

public struct Store: Codable, Equatable {
    public let id: String
    public let key: String
    public let name: String
}

public struct PurchaseOption: Codable, Equatable {
    public let id: String
    public let storeId: String
    public let sku: String
    public let name: String
    public let priceCents: UInt32
    public let currency: String
    public let period: String?
    public let metadata: AnyDecodable?

    enum CodingKeys: String, CodingKey {
        case id, sku, name, currency, period, metadata
        case storeId = "store_id"
        case priceCents = "price_cents"
    }

    public static func == (lhs: PurchaseOption, rhs: PurchaseOption) -> Bool {
        lhs.id == rhs.id && lhs.storeId == rhs.storeId && lhs.sku == rhs.sku &&
            lhs.name == rhs.name && lhs.priceCents == rhs.priceCents &&
            lhs.currency == rhs.currency && lhs.period == rhs.period
    }
}

public struct PurchaseResult: Codable, Equatable {
    public let id: String
    public let userId: String
    public let purchaseOptionId: String
    public let status: String
    public let purchasedAt: Date
    public let receipt: AnyDecodable?

    enum CodingKeys: String, CodingKey {
        case id, status, receipt
        case userId = "user_id"
        case purchaseOptionId = "purchase_option_id"
        case purchasedAt = "purchased_at"
    }

    public static func == (lhs: PurchaseResult, rhs: PurchaseResult) -> Bool {
        lhs.id == rhs.id && lhs.userId == rhs.userId &&
            lhs.purchaseOptionId == rhs.purchaseOptionId &&
            lhs.status == rhs.status && lhs.purchasedAt == rhs.purchasedAt
    }
}

public struct XpBalance: Codable, Equatable {
    public let userId: String
    public let totalXp: Int64
    public let currentLevel: UInt32
    public let xpIntoLevel: Int64
    public let xpToNextLevel: Int64
    /// XP earned in the current rolling period (e.g. day/week, server-defined).
    /// Decoded with `#serde(default)` semantics — pre-rolling-period payloads
    /// decode to `0`.
    public let xpThisPeriod: Int64
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case totalXp = "total_xp"
        case currentLevel = "current_level"
        case xpIntoLevel = "xp_into_level"
        case xpToNextLevel = "xp_to_next_level"
        case xpThisPeriod = "xp_this_period"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.userId = try c.decode(String.self, forKey: .userId)
        self.totalXp = try c.decode(Int64.self, forKey: .totalXp)
        self.currentLevel = try c.decode(UInt32.self, forKey: .currentLevel)
        self.xpIntoLevel = try c.decode(Int64.self, forKey: .xpIntoLevel)
        self.xpToNextLevel = try c.decode(Int64.self, forKey: .xpToNextLevel)
        // Match Rust `#[serde(default)]` — absent → 0.
        self.xpThisPeriod = try c.decodeIfPresent(Int64.self, forKey: .xpThisPeriod) ?? 0
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    public init(
        userId: String,
        totalXp: Int64,
        currentLevel: UInt32,
        xpIntoLevel: Int64,
        xpToNextLevel: Int64,
        xpThisPeriod: Int64 = 0,
        updatedAt: Date
    ) {
        self.userId = userId
        self.totalXp = totalXp
        self.currentLevel = currentLevel
        self.xpIntoLevel = xpIntoLevel
        self.xpToNextLevel = xpToNextLevel
        self.xpThisPeriod = xpThisPeriod
        self.updatedAt = updatedAt
    }
}

public struct XpTransaction: Codable, Equatable {
    public let id: String
    public let delta: Int64
    public let reason: String?
    public let source: String?
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, delta, reason, source
        case createdAt = "created_at"
    }
}

public struct Streak: Codable, Equatable {
    public let id: String
    public let key: String
    public let name: String
    public let currentLength: UInt32
    public let longestLength: UInt32
    /// Rust serializes `NaiveDate` as `"YYYY-MM-DD"` — kept as a String
    /// here because Swift's default `Date` decoder expects ISO-8601
    /// timestamps. Customer code can re-parse if a `Date` is wanted.
    public let lastQualifiedOn: String?
    /// Streak lifecycle state: e.g. `"active"`, `"broken"`, `"at_risk"`.
    /// Decoded with `#serde(default)` semantics — pre-status payloads
    /// decode to an empty string.
    public let status: String
    /// Remaining streak freezes available (server-managed counter).
    /// Decoded with `#serde(default)` semantics — pre-freeze payloads
    /// decode to `0`.
    public let freezesRemaining: UInt32
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, key, name, status
        case currentLength = "current_length"
        case longestLength = "longest_length"
        case lastQualifiedOn = "last_qualified_on"
        case freezesRemaining = "freezes_remaining"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.key = try c.decode(String.self, forKey: .key)
        self.name = try c.decode(String.self, forKey: .name)
        self.currentLength = try c.decode(UInt32.self, forKey: .currentLength)
        self.longestLength = try c.decode(UInt32.self, forKey: .longestLength)
        self.lastQualifiedOn = try c.decodeIfPresent(String.self, forKey: .lastQualifiedOn)
        // Match Rust `#[serde(default)]` — absent → "" / 0.
        self.status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        self.freezesRemaining = try c.decodeIfPresent(UInt32.self, forKey: .freezesRemaining) ?? 0
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    public init(
        id: String,
        key: String,
        name: String,
        currentLength: UInt32,
        longestLength: UInt32,
        lastQualifiedOn: String? = nil,
        status: String = "",
        freezesRemaining: UInt32 = 0,
        updatedAt: Date
    ) {
        self.id = id
        self.key = key
        self.name = name
        self.currentLength = currentLength
        self.longestLength = longestLength
        self.lastQualifiedOn = lastQualifiedOn
        self.status = status
        self.freezesRemaining = freezesRemaining
        self.updatedAt = updatedAt
    }
}

// MARK: - Social types

public struct FeedItem: Codable, Equatable {
    public let id: String
    public let actorId: String
    public let verb: String
    public let objectType: String
    public let objectId: String
    public let targetType: String?
    public let targetId: String?
    public let data: AnyDecodable?
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, verb, data
        case actorId = "actor_id"
        case objectType = "object_type"
        case objectId = "object_id"
        case targetType = "target_type"
        case targetId = "target_id"
        case createdAt = "created_at"
    }

    public static func == (lhs: FeedItem, rhs: FeedItem) -> Bool {
        lhs.id == rhs.id && lhs.actorId == rhs.actorId && lhs.verb == rhs.verb &&
            lhs.objectType == rhs.objectType && lhs.objectId == rhs.objectId &&
            lhs.targetType == rhs.targetType && lhs.targetId == rhs.targetId &&
            lhs.createdAt == rhs.createdAt
    }
}

public struct FeedResponse: Codable, Equatable {
    public let data: [FeedItem]
    public let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case data
        case nextCursor = "next_cursor"
    }
}

public enum FriendshipState: String, Codable, Equatable {
    case pending
    case accepted
    case blocked
    case declined
}

public struct Friendship: Codable, Equatable {
    public let id: String
    public let userId: String
    public let friendId: String
    public let state: FriendshipState
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, state
        case userId = "user_id"
        case friendId = "friend_id"
        case createdAt = "created_at"
    }
}

public struct Group: Codable, Equatable {
    public let id: String
    public let name: String
    public let description: String?
    public let avatarUrl: String?
    public let createdBy: String
    public let memberCount: UInt32
    public let createdAt: Date
    public let updatedAt: Date
    public let metadata: AnyDecodable?

    enum CodingKeys: String, CodingKey {
        case id, name, description, metadata
        case avatarUrl = "avatar_url"
        case createdBy = "created_by"
        case memberCount = "member_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public static func == (lhs: Group, rhs: Group) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.description == rhs.description &&
            lhs.avatarUrl == rhs.avatarUrl && lhs.createdBy == rhs.createdBy &&
            lhs.memberCount == rhs.memberCount && lhs.createdAt == rhs.createdAt &&
            lhs.updatedAt == rhs.updatedAt
    }
}

public struct GroupMember: Codable, Equatable {
    public let groupId: String
    public let userId: String
    public let role: String
    public let joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case role
        case groupId = "group_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
    }
}

public struct GroupCreate: Codable, Equatable {
    public let name: String
    public let description: String?
    public let avatarUrl: String?
    public let metadata: AnyEncodableDecodable?

    public init(name: String, description: String? = nil, avatarUrl: String? = nil, metadata: AnyEncodableDecodable? = nil) {
        self.name = name
        self.description = description
        self.avatarUrl = avatarUrl
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case name, description, metadata
        case avatarUrl = "avatar_url"
    }

    public static func == (lhs: GroupCreate, rhs: GroupCreate) -> Bool {
        lhs.name == rhs.name && lhs.description == rhs.description &&
            lhs.avatarUrl == rhs.avatarUrl
    }
}

public struct GroupUpdate: Codable, Equatable {
    public let name: String?
    public let description: String?
    public let avatarUrl: String?
    public let metadata: AnyEncodableDecodable?

    public init(name: String? = nil, description: String? = nil, avatarUrl: String? = nil, metadata: AnyEncodableDecodable? = nil) {
        self.name = name
        self.description = description
        self.avatarUrl = avatarUrl
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case name, description, metadata
        case avatarUrl = "avatar_url"
    }

    public static func == (lhs: GroupUpdate, rhs: GroupUpdate) -> Bool {
        lhs.name == rhs.name && lhs.description == rhs.description &&
            lhs.avatarUrl == rhs.avatarUrl
    }
}

public struct Conversation: Codable, Equatable {
    public let id: String
    public let participants: [String]
    public let lastMessage: Message?
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, participants
        case lastMessage = "last_message"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct Message: Codable, Equatable {
    public let id: String
    public let conversationId: String
    public let senderId: String
    public let body: String
    public let metadata: AnyDecodable?
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body, metadata
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case createdAt = "created_at"
    }

    public static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id && lhs.conversationId == rhs.conversationId &&
            lhs.senderId == rhs.senderId && lhs.body == rhs.body &&
            lhs.createdAt == rhs.createdAt
    }
}

public struct SendMessageRequest: Codable, Equatable {
    public let conversationId: String?
    public let toUserId: String?
    public let body: String
    public let metadata: AnyEncodableDecodable?

    public init(conversationId: String? = nil, toUserId: String? = nil, body: String, metadata: AnyEncodableDecodable? = nil) {
        self.conversationId = conversationId
        self.toUserId = toUserId
        self.body = body
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case body, metadata
        case conversationId = "conversation_id"
        case toUserId = "to_user_id"
    }

    public static func == (lhs: SendMessageRequest, rhs: SendMessageRequest) -> Bool {
        lhs.conversationId == rhs.conversationId && lhs.toUserId == rhs.toUserId &&
            lhs.body == rhs.body
    }
}

public struct Report: Codable, Equatable {
    public let id: String
    public let reporterId: String
    public let targetType: String
    public let targetId: String
    public let reason: String
    public let status: String
    public let notes: String?
    public let createdAt: Date
    public let resolvedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, reason, status, notes
        case reporterId = "reporter_id"
        case targetType = "target_type"
        case targetId = "target_id"
        case createdAt = "created_at"
        case resolvedAt = "resolved_at"
    }
}

public struct ReportRequest: Codable, Equatable {
    public let targetId: String
    public let reason: String
    public let notes: String?

    public init(targetId: String, reason: String, notes: String? = nil) {
        self.targetId = targetId
        self.reason = reason
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case reason, notes
        case targetId = "target_id"
    }
}

public struct Review: Codable, Equatable {
    public let id: String
    public let authorId: String
    public let targetType: String
    public let targetId: String
    public let rating: Float
    public let title: String?
    public let body: String?
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, rating, title, body
        case authorId = "author_id"
        case targetType = "target_type"
        case targetId = "target_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct ReviewCreate: Codable, Equatable {
    public let targetType: String
    public let targetId: String
    public let rating: Float
    public let title: String?
    public let body: String?

    public init(targetType: String, targetId: String, rating: Float, title: String? = nil, body: String? = nil) {
        self.targetType = targetType
        self.targetId = targetId
        self.rating = rating
        self.title = title
        self.body = body
    }

    enum CodingKeys: String, CodingKey {
        case rating, title, body
        case targetType = "target_type"
        case targetId = "target_id"
    }
}

public struct ReviewUpdate: Codable, Equatable {
    public let rating: Float?
    public let title: String?
    public let body: String?

    public init(rating: Float? = nil, title: String? = nil, body: String? = nil) {
        self.rating = rating
        self.title = title
        self.body = body
    }
}

public struct Role: Codable, Equatable {
    public let id: String
    public let key: String
    public let name: String
    public let permissions: [String]
}

public struct ReferralCode: Codable, Equatable {
    public let id: String
    public let code: String
    public let ownerId: String
    public let usesCount: UInt32
    public let maxUses: UInt32?
    public let expiresAt: Date?
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, code
        case ownerId = "owner_id"
        case usesCount = "uses_count"
        case maxUses = "max_uses"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

public struct ReferralClaim: Codable, Equatable {
    public let id: String
    public let codeId: String
    public let referrerId: String
    public let refereeId: String
    public let reward: AnyDecodable?
    public let claimedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, reward
        case codeId = "code_id"
        case referrerId = "referrer_id"
        case refereeId = "referee_id"
        case claimedAt = "claimed_at"
    }

    public static func == (lhs: ReferralClaim, rhs: ReferralClaim) -> Bool {
        lhs.id == rhs.id && lhs.codeId == rhs.codeId &&
            lhs.referrerId == rhs.referrerId && lhs.refereeId == rhs.refereeId &&
            lhs.claimedAt == rhs.claimedAt
    }
}

// MARK: - Lifecycle types

public struct CatalogItem: Codable, Equatable {
    public let id: String
    public let sku: String
    public let name: String
    public let description: String?
    public let priceCents: UInt32?
    public let currency: String?
    public let metadata: AnyDecodable?

    enum CodingKeys: String, CodingKey {
        case id, sku, name, description, currency, metadata
        case priceCents = "price_cents"
    }

    public static func == (lhs: CatalogItem, rhs: CatalogItem) -> Bool {
        lhs.id == rhs.id && lhs.sku == rhs.sku && lhs.name == rhs.name &&
            lhs.description == rhs.description && lhs.priceCents == rhs.priceCents &&
            lhs.currency == rhs.currency
    }
}

public struct ContentItem: Codable, Equatable {
    public let id: String
    public let channel: String
    public let title: String?
    public let body: String?
    public let data: AnyDecodable?
    public let publishedAt: Date
    public let userState: AnyDecodable?

    enum CodingKeys: String, CodingKey {
        case id, channel, title, body, data
        case publishedAt = "published_at"
        case userState = "user_state"
    }

    public static func == (lhs: ContentItem, rhs: ContentItem) -> Bool {
        lhs.id == rhs.id && lhs.channel == rhs.channel &&
            lhs.title == rhs.title && lhs.body == rhs.body &&
            lhs.publishedAt == rhs.publishedAt
    }
}

public struct DeepLink: Codable, Equatable {
    public let id: String
    public let url: String
    public let shortCode: String
    public let targetPath: String?
    public let metadata: AnyDecodable?
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, url, metadata
        case shortCode = "short_code"
        case targetPath = "target_path"
        case createdAt = "created_at"
    }

    public static func == (lhs: DeepLink, rhs: DeepLink) -> Bool {
        lhs.id == rhs.id && lhs.url == rhs.url &&
            lhs.shortCode == rhs.shortCode && lhs.targetPath == rhs.targetPath &&
            lhs.createdAt == rhs.createdAt
    }
}

public struct DeepLinkCreate: Codable, Equatable {
    public let targetPath: String
    public let metadata: AnyEncodableDecodable?
    public let shortCode: String?

    public init(targetPath: String, metadata: AnyEncodableDecodable? = nil, shortCode: String? = nil) {
        self.targetPath = targetPath
        self.metadata = metadata
        self.shortCode = shortCode
    }

    enum CodingKeys: String, CodingKey {
        case metadata
        case targetPath = "target_path"
        case shortCode = "short_code"
    }

    public static func == (lhs: DeepLinkCreate, rhs: DeepLinkCreate) -> Bool {
        lhs.targetPath == rhs.targetPath && lhs.shortCode == rhs.shortCode
    }
}

public struct OnboardingStatus: Codable, Equatable {
    public let currentStep: String?
    public let completedSteps: [String]
    public let remainingSteps: [String]
    public let completed: Bool
    public let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case completed
        case currentStep = "current_step"
        case completedSteps = "completed_steps"
        case remainingSteps = "remaining_steps"
        case completedAt = "completed_at"
    }
}

// MARK: - Push extension types

/// JSON-decoded push token row returned by `Amba.push.getTokens()`.
/// Distinct from the engine-typed `PushTokenFfi` (which is what
/// `register()` returns) — `getTokens` goes through the JSON-string
/// path so the wire shape lands in a Codable struct.
public struct PushToken: Codable, Equatable {
    public let id: String
    public let token: String
    /// Server-side strings are lowercased: `"apns"`, `"fcm"`, `"web"`.
    public let platform: String
    public let bundleId: String?
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, token, platform
        case bundleId = "bundle_id"
        case createdAt = "created_at"
    }
}

// MARK: - AnyEncodableDecodable (used by social GroupCreate/Update etc.)

/// Type-erased Codable wrapper for JSON values whose shape isn't known
/// statically (e.g. `metadata` blobs on group create/update). Holds a
/// JSON-serializable Swift value (`Bool`, numeric, `String`, `[Any]`,
/// `[String: Any]`, or `NSNull`).
public struct AnyEncodableDecodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let b = try? container.decode(Bool.self) {
            value = b
        } else if let n = try? container.decode(Int64.self) {
            value = n
        } else if let n = try? container.decode(Double.self) {
            value = n
        } else if let s = try? container.decode(String.self) {
            value = s
        } else if let arr = try? container.decode([AnyDecodable].self) {
            value = arr.map { $0.value }
        } else if let obj = try? container.decode([String: AnyDecodable].self) {
            value = obj.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let b as Bool:
            try container.encode(b)
        case let i as Int:
            try container.encode(i)
        case let i as Int64:
            try container.encode(i)
        case let d as Double:
            try container.encode(d)
        case let f as Float:
            try container.encode(f)
        case let s as String:
            try container.encode(s)
        case let arr as [Any]:
            try container.encode(arr.map { AnyEncodableDecodable($0) })
        case let obj as [String: Any]:
            try container.encode(obj.mapValues { AnyEncodableDecodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
