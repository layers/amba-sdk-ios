//
//  AmbaWrapperTests.swift
//
//  Wrapper-API coverage. These tests exercise the `AmbaClient` class
//  directly — Constructor DI, no global state. Every test:
//
//      let core = MockAmbaCore()
//      let client = AmbaClient(core: core)
//      try await client.events.track("...")
//
//  Tests never touch `Amba.*` static state — the static facade is a
//  thin passthrough to the singleton built by `Amba.configure(...)`
//  and is smoke-tested separately. Same code path runs in both modes,
//  so coverage on `AmbaClient` covers the facade too.
//

import XCTest
@testable import Amba

// MARK: - Mock core

final class MockAmbaCore: AmbaCoreFfiProtocol, @unchecked Sendable {
    // Inputs captured per method
    var trackCalls: [(event: String, propsJson: String?)] = []
    var aiCalls: [String] = []
    var collectionsFindCalls: [(collection: String, optionsJson: String)] = []
    var collectionsFindOneCalls: [(collection: String, id: String)] = []
    var collectionsInsertCalls: [(collection: String, rowJson: String)] = []
    var collectionsUpdateCalls: [(collection: String, id: String, setJson: String)] = []
    var collectionsDeleteCalls: [(collection: String, id: String)] = []
    var pushRegisterCalls: [(token: String, platform: PushPlatformFfi, bundleId: String?)] = []
    var pushSubscribeCalls: [String] = []
    var storagePresignCalls: [(bucket: String, filename: String, mimeType: String, sizeBytes: UInt64, retentionDays: UInt32?)] = []
    var storageCommitCalls: [(uploadId: String, assetId: String)] = []
    var signInWithEmailCalls: [(email: String, password: String)] = []
    var signUpWithEmailCalls: [(email: String, password: String)] = []
    var signInWithSocialCalls: [(provider: SocialProviderFfi, idToken: String)] = []
    var signOutCalls: [Bool] = []
    var setDebugCalls: [Bool] = []
    var entitlementsHasCalls: [String] = []

    var signInAnonymouslyCount = 0
    var refreshSessionCount = 0
    var meCount = 0
    var entitlementsListCount = 0
    var flagsFetchCount = 0
    var configFetchCount = 0

    // Programmed responses
    var anonId: String = "anon-mock"
    var appUid: String? = "u_mock"
    var authed: Bool = false

    var nextAiResponseJson: String = #"{"content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":10,"output_tokens":3},"stop_reason":"end_turn","model":"claude-test"}"#
    var nextCollectionsFindResponseJson: String = #"{"data":[],"next_cursor":null,"has_more":false}"#
    var nextCollectionsFindOneResponseJson: String = #"{"id":"row-1","name":"alpha"}"#
    var nextCollectionsInsertResponseJson: String = #"{"id":"new-1","name":"alpha"}"#
    var nextCollectionsUpdateResponseJson: String = #"{"id":"row-1","name":"alpha-updated"}"#
    var nextCollectionsDeleteResponseJson: String = #"{"deleted":true}"#
    // Wire shape (post-item-5 #12 fix): { "version": "<etag-prefix>" | null,
    // "values": { ... } }. generated_at was dropped — it never existed
    // on the server response. version is nullable for new projects.
    var nextConfigFetchJson: String = #"{"version":"1","values":{"flagA":true}}"#

    var nextAuthResult: AuthResultFfi = AuthResultFfi(
        sessionToken: "sess",
        refreshToken: "refresh",
        user: UserFfi(
            id: "u_mock",
            email: nil,
            displayName: nil,
            avatarUrl: nil,
            externalId: nil,
            anonymousId: "anon-mock",
            authProviders: [],
            propertiesJson: "{}"
        ),
        anonymousId: "anon-mock",
        expiresAt: nil
    )
    var nextUser: UserFfi = UserFfi(
        id: "u_mock",
        email: "u@test",
        displayName: "U",
        avatarUrl: nil,
        externalId: nil,
        anonymousId: "anon-mock",
        authProviders: ["email"],
        propertiesJson: "{}"
    )
    var nextPushToken: PushTokenFfi = PushTokenFfi(
        id: "pt_1",
        token: "device-token",
        platform: .apns,
        bundleId: nil,
        createdAt: "2025-01-01T00:00:00Z"
    )
    var nextPresign: PresignDataFfi = PresignDataFfi(
        uploadId: "u1",
        uploadUrl: "https://r2.example/upload",
        uploadHeaders: [HttpHeader(name: "x-amz-test", value: "1")],
        assetId: "a1"
    )
    var nextMediaAsset: MediaAssetFfi = MediaAssetFfi(
        id: "a1",
        bucket: "b",
        key: "k",
        url: "https://r2.example/k",
        mimeType: "image/png",
        sizeBytes: 4,
        width: nil,
        height: nil,
        retentionDays: nil,
        createdAt: "2025-01-01T00:00:00Z"
    )
    var nextEntitlements: [UserEntitlementFfi] = []
    var nextFlags: [FlagAssignmentFfi] = []
    var nextEntitlementsHas: Bool = false

    // Error hooks — set non-nil to make the corresponding method throw.
    var trackError: Error?
    var configFetchError: Error?
    var collectionsFindError: Error?

    // MARK: AmbaCoreFfiProtocol

    func aiAnthropicMessages(requestJson: String) async throws -> String {
        aiCalls.append(requestJson)
        return nextAiResponseJson
    }
    func anonymousId() -> String { anonId }
    func appUserId() -> String? { appUid }
    func collectionsDelete(collection: String, id: String) async throws -> String {
        collectionsDeleteCalls.append((collection, id))
        return nextCollectionsDeleteResponseJson
    }
    func collectionsFind(collection: String, optionsJson: String) async throws -> String {
        if let e = collectionsFindError { throw e }
        collectionsFindCalls.append((collection, optionsJson))
        return nextCollectionsFindResponseJson
    }
    func collectionsFindOne(collection: String, id: String) async throws -> String {
        collectionsFindOneCalls.append((collection, id))
        return nextCollectionsFindOneResponseJson
    }
    func collectionsInsert(collection: String, rowJson: String) async throws -> String {
        collectionsInsertCalls.append((collection, rowJson))
        return nextCollectionsInsertResponseJson
    }
    func collectionsUpdate(collection: String, id: String, setJson: String) async throws -> String {
        collectionsUpdateCalls.append((collection, id, setJson))
        return nextCollectionsUpdateResponseJson
    }
    func configFetch() async throws -> String {
        if let e = configFetchError { throw e }
        configFetchCount += 1
        return nextConfigFetchJson
    }
    func entitlementsHas(name: String) async -> Bool {
        entitlementsHasCalls.append(name)
        return nextEntitlementsHas
    }
    func entitlementsList() async throws -> [UserEntitlementFfi] {
        entitlementsListCount += 1
        return nextEntitlements
    }
    func flagsFetch() async throws -> [FlagAssignmentFfi] {
        flagsFetchCount += 1
        return nextFlags
    }
    func isAuthenticated() -> Bool { authed }
    func me() async throws -> UserFfi {
        meCount += 1
        return nextUser
    }
    func pushRegister(token: String, platform: PushPlatformFfi, bundleId: String?) async throws -> PushTokenFfi {
        pushRegisterCalls.append((token, platform, bundleId))
        return nextPushToken
    }
    func pushSubscribe(topic: String) async throws {
        pushSubscribeCalls.append(topic)
    }
    func refreshSession() async throws -> AuthResultFfi {
        refreshSessionCount += 1
        return nextAuthResult
    }
    func setDebug(enabled: Bool) {
        setDebugCalls.append(enabled)
    }
    func signInAnonymously() async throws -> AuthResultFfi {
        signInAnonymouslyCount += 1
        return nextAuthResult
    }
    func signInWithEmail(email: String, password: String) async throws -> AuthResultFfi {
        signInWithEmailCalls.append((email, password))
        return nextAuthResult
    }
    func signInWithSocial(provider: SocialProviderFfi, idToken: String) async throws -> AuthResultFfi {
        signInWithSocialCalls.append((provider, idToken))
        return nextAuthResult
    }
    func signOut(rotateAnonymousId: Bool) async throws {
        signOutCalls.append(rotateAnonymousId)
    }
    func signUpWithEmail(email: String, password: String) async throws -> AuthResultFfi {
        signUpWithEmailCalls.append((email, password))
        return nextAuthResult
    }
    func storageCommit(uploadId: String, assetId: String) async throws -> MediaAssetFfi {
        storageCommitCalls.append((uploadId, assetId))
        return nextMediaAsset
    }
    func storagePresign(bucket: String, filename: String, mimeType: String, sizeBytes: UInt64, retentionDays: UInt32?) async throws -> PresignDataFfi {
        storagePresignCalls.append((bucket, filename, mimeType, sizeBytes, retentionDays))
        return nextPresign
    }
    func track(event: String, propertiesJson: String?) async throws {
        if let e = trackError { throw e }
        trackCalls.append((event, propertiesJson))
    }

    // MARK: New namespace stubs (gamification)
    //
    // Each new namespace method is a happy-path stub: it records the call
    // (so tests can assert the args) and returns a programmable JSON
    // string (so the wrapper's decode path is exercised).

    // ── achievements ──
    var achievementsGetAllCount = 0
    var achievementsGetProgressCount = 0
    var nextAchievementsGetAllJson: String = "[]"
    var nextAchievementsGetProgressJson: String = "[]"
    func achievementsGetAll() async throws -> String {
        achievementsGetAllCount += 1
        return nextAchievementsGetAllJson
    }
    func achievementsGetProgress() async throws -> String {
        achievementsGetProgressCount += 1
        return nextAchievementsGetProgressJson
    }

    // ── challenges ──
    var challengesGetActiveCount = 0
    var challengesGetCalls: [String] = []
    var challengesGetProgressCalls: [String] = []
    var challengesClaimCalls: [String] = []
    var nextChallengesGetActiveJson: String = "[]"
    var nextChallengesGetJson: String = "{}"
    var nextChallengesGetProgressJson: String = "{}"
    var nextChallengesClaimJson: String = "{}"
    func challengesGetActive() async throws -> String {
        challengesGetActiveCount += 1
        return nextChallengesGetActiveJson
    }
    func challengesGet(id: String) async throws -> String {
        challengesGetCalls.append(id)
        return nextChallengesGetJson
    }
    func challengesGetProgress(id: String) async throws -> String {
        challengesGetProgressCalls.append(id)
        return nextChallengesGetProgressJson
    }
    func challengesClaim(id: String) async throws -> String {
        challengesClaimCalls.append(id)
        return nextChallengesClaimJson
    }

    // ── currencies ──
    var currenciesGetBalanceCount = 0
    var currenciesGetTransactionsCalls: [String] = []
    var nextCurrenciesGetBalanceJson: String = "[]"
    var nextCurrenciesGetTransactionsJson: String = "[]"
    func currenciesGetBalance() async throws -> String {
        currenciesGetBalanceCount += 1
        return nextCurrenciesGetBalanceJson
    }
    func currenciesGetTransactions(currencyKey: String) async throws -> String {
        currenciesGetTransactionsCalls.append(currencyKey)
        return nextCurrenciesGetTransactionsJson
    }

    // ── inventory ──
    var inventoryGetItemsCount = 0
    var inventoryGetItemCalls: [String] = []
    var inventoryPurchaseCalls: [String] = []
    var inventoryConsumeCalls: [String] = []
    var nextInventoryGetItemsJson: String = "[]"
    var nextInventoryGetItemJson: String = "{}"
    var nextInventoryPurchaseJson: String = "{}"
    var nextInventoryConsumeJson: String = "{}"
    func inventoryGetItems() async throws -> String {
        inventoryGetItemsCount += 1
        return nextInventoryGetItemsJson
    }
    func inventoryGetItem(id: String) async throws -> String {
        inventoryGetItemCalls.append(id)
        return nextInventoryGetItemJson
    }
    func inventoryPurchase(requestJson: String) async throws -> String {
        inventoryPurchaseCalls.append(requestJson)
        return nextInventoryPurchaseJson
    }
    func inventoryConsume(requestJson: String) async throws -> String {
        inventoryConsumeCalls.append(requestJson)
        return nextInventoryConsumeJson
    }

    // ── leaderboards ──
    var leaderboardsGetCalls: [String] = []
    var leaderboardsGetEntriesCalls: [(String, UInt32?)] = []
    var leaderboardsGetMyRankCalls: [String] = []
    var nextLeaderboardsGetJson: String = "{}"
    var nextLeaderboardsGetEntriesJson: String = "[]"
    var nextLeaderboardsGetMyRankJson: String = "{}"
    func leaderboardsGet(key: String) async throws -> String {
        leaderboardsGetCalls.append(key)
        return nextLeaderboardsGetJson
    }
    func leaderboardsGetEntries(key: String, limit: UInt32?) async throws -> String {
        leaderboardsGetEntriesCalls.append((key, limit))
        return nextLeaderboardsGetEntriesJson
    }
    func leaderboardsGetMyRank(key: String) async throws -> String {
        leaderboardsGetMyRankCalls.append(key)
        return nextLeaderboardsGetMyRankJson
    }

    // ── stores ──
    var storesListCount = 0
    var storesGetPurchaseOptionsCalls: [String] = []
    var storesPurchaseCalls: [(String, String, String)] = []
    var nextStoresListJson: String = "[]"
    var nextStoresGetPurchaseOptionsJson: String = "[]"
    var nextStoresPurchaseJson: String = "{}"
    func storesList() async throws -> String {
        storesListCount += 1
        return nextStoresListJson
    }
    func storesGetPurchaseOptions(storeKey: String) async throws -> String {
        storesGetPurchaseOptionsCalls.append(storeKey)
        return nextStoresGetPurchaseOptionsJson
    }
    func storesPurchase(storeKey: String, purchaseOptionId: String, receiptJson: String) async throws -> String {
        storesPurchaseCalls.append((storeKey, purchaseOptionId, receiptJson))
        return nextStoresPurchaseJson
    }

    // ── xp ──
    var xpGetBalanceCount = 0
    var xpGetHistoryCalls: [UInt32?] = []
    var xpClaimCalls: [String] = []
    var nextXpGetBalanceJson: String = "{}"
    var nextXpGetHistoryJson: String = "[]"
    var nextXpClaimJson: String = "{}"
    func xpGetBalance() async throws -> String {
        xpGetBalanceCount += 1
        return nextXpGetBalanceJson
    }
    func xpGetHistory(limit: UInt32?) async throws -> String {
        xpGetHistoryCalls.append(limit)
        return nextXpGetHistoryJson
    }
    func xpClaim(grantKey: String) async throws -> String {
        xpClaimCalls.append(grantKey)
        return nextXpClaimJson
    }

    // ── streaks ──
    var streaksGetAllCount = 0
    var streaksQualifyCalls: [String] = []
    var nextStreaksGetAllJson: String = "[]"
    var nextStreaksQualifyJson: String = "{}"
    func streaksGetAll() async throws -> String {
        streaksGetAllCount += 1
        return nextStreaksGetAllJson
    }
    func streaksQualify(streakKey: String) async throws -> String {
        streaksQualifyCalls.append(streakKey)
        return nextStreaksQualifyJson
    }

    // ── push extensions (stubs — exercised in commit 3) ──
    var pushUnregisterCalls: [String] = []
    var pushUnsubscribeCalls: [String] = []
    var pushGetTokensCount = 0
    var nextPushGetTokensJson: String = "[]"
    func pushUnregister(token: String) async throws { pushUnregisterCalls.append(token) }
    func pushUnsubscribe(topic: String) async throws { pushUnsubscribeCalls.append(topic) }
    func pushGetTokens() async throws -> String {
        pushGetTokensCount += 1
        return nextPushGetTokensJson
    }

    // ── social stubs (exercised in commit 2) ──
    var feedsGetActivityCalls: [(String?, String?)] = []
    var nextFeedsGetActivityJson: String = #"{"data":[],"next_cursor":null}"#
    func feedsGetActivity(feed: String?, cursor: String?) async throws -> String {
        feedsGetActivityCalls.append((feed, cursor))
        return nextFeedsGetActivityJson
    }

    var friendsGetListCount = 0
    var friendsGetFriendsCount = 0
    var friendsBlockUserCalls: [String] = []
    var friendsUnblockUserCalls: [String] = []
    var friendsRemoveBlockCalls: [String] = []
    var nextFriendsGetListJson: String = "[]"
    var nextFriendsGetFriendsJson: String = "[]"
    var nextFriendsBlockUserJson: String = "{}"
    func friendsGetList() async throws -> String {
        friendsGetListCount += 1
        return nextFriendsGetListJson
    }
    func friendsGetFriends() async throws -> String {
        friendsGetFriendsCount += 1
        return nextFriendsGetFriendsJson
    }
    func friendsBlockUser(userId: String) async throws -> String {
        friendsBlockUserCalls.append(userId)
        return nextFriendsBlockUserJson
    }
    func friendsUnblockUser(userId: String) async throws {
        friendsUnblockUserCalls.append(userId)
    }
    func friendsRemoveBlock(friendshipId: String) async throws {
        friendsRemoveBlockCalls.append(friendshipId)
    }

    var groupsCreateCalls: [String] = []
    var groupsGetCalls: [String] = []
    var groupsUpdateCalls: [(String, String)] = []
    var groupsDeleteCalls: [String] = []
    var groupsGetMembersCalls: [String] = []
    var groupsJoinCalls: [String] = []
    var groupsLeaveCalls: [String] = []
    var groupsInviteCalls: [(String, String)] = []
    var nextGroupsCreateJson: String = "{}"
    var nextGroupsGetJson: String = "{}"
    var nextGroupsUpdateJson: String = "{}"
    var nextGroupsGetMembersJson: String = "[]"
    var nextGroupsJoinJson: String = "{}"
    var nextGroupsInviteJson: String = "{}"
    func groupsCreate(paramsJson: String) async throws -> String {
        groupsCreateCalls.append(paramsJson)
        return nextGroupsCreateJson
    }
    func groupsGet(id: String) async throws -> String {
        groupsGetCalls.append(id)
        return nextGroupsGetJson
    }
    func groupsUpdate(id: String, patchJson: String) async throws -> String {
        groupsUpdateCalls.append((id, patchJson))
        return nextGroupsUpdateJson
    }
    func groupsDelete(id: String) async throws {
        groupsDeleteCalls.append(id)
    }
    func groupsGetMembers(id: String) async throws -> String {
        groupsGetMembersCalls.append(id)
        return nextGroupsGetMembersJson
    }
    func groupsJoin(id: String) async throws -> String {
        groupsJoinCalls.append(id)
        return nextGroupsJoinJson
    }
    func groupsLeave(id: String) async throws {
        groupsLeaveCalls.append(id)
    }
    func groupsInvite(id: String, userId: String) async throws -> String {
        groupsInviteCalls.append((id, userId))
        return nextGroupsInviteJson
    }

    var messagingGetConversationsCount = 0
    var messagingGetMessageCalls: [String] = []
    var messagingSendMessageCalls: [String] = []
    var nextMessagingGetConversationsJson: String = "[]"
    var nextMessagingGetMessageJson: String = "{}"
    var nextMessagingSendMessageJson: String = "{}"
    func messagingGetConversations() async throws -> String {
        messagingGetConversationsCount += 1
        return nextMessagingGetConversationsJson
    }
    func messagingGetMessage(id: String) async throws -> String {
        messagingGetMessageCalls.append(id)
        return nextMessagingGetMessageJson
    }
    func messagingSendMessage(requestJson: String) async throws -> String {
        messagingSendMessageCalls.append(requestJson)
        return nextMessagingSendMessageJson
    }

    // ── #158 messaging refactor — stubs so mock conforms to the
    // protocol. Tests below don't exercise these paths, so the stubs
    // are minimal. Real coverage lives in integration tests.
    var messagingCreateConversationCalls: [String] = []
    var nextMessagingCreateConversationJson: String = "{}"
    func messagingCreateConversation(requestJson: String) async throws -> String {
        messagingCreateConversationCalls.append(requestJson)
        return nextMessagingCreateConversationJson
    }
    var messagingListMessagesCalls: [(String, UInt32?, UInt32?)] = []
    var nextMessagingListMessagesJson: String = "[]"
    func messagingListMessages(
        conversationId: String,
        limit: UInt32?,
        offset: UInt32?
    ) async throws -> String {
        messagingListMessagesCalls.append((conversationId, limit, offset))
        return nextMessagingListMessagesJson
    }
    var messagingMarkReadCalls: [String] = []
    var nextMessagingMarkReadJson: String = "{}"
    func messagingMarkRead(conversationId: String) async throws -> String {
        messagingMarkReadCalls.append(conversationId)
        return nextMessagingMarkReadJson
    }

    var moderationReportUserCalls: [String] = []
    var moderationReportContentCalls: [String] = []
    var moderationGetReportStatusCalls: [String] = []
    var nextModerationReportUserJson: String = "{}"
    var nextModerationReportContentJson: String = "{}"
    var nextModerationGetReportStatusJson: String = "{}"
    func moderationReportUser(requestJson: String) async throws -> String {
        moderationReportUserCalls.append(requestJson)
        return nextModerationReportUserJson
    }
    func moderationReportContent(requestJson: String) async throws -> String {
        moderationReportContentCalls.append(requestJson)
        return nextModerationReportContentJson
    }
    func moderationGetReportStatus(id: String) async throws -> String {
        moderationGetReportStatusCalls.append(id)
        return nextModerationGetReportStatusJson
    }

    var reviewsListCalls: [(String, String)] = []
    var reviewsCreateCalls: [String] = []
    var reviewsUpdateCalls: [(String, String)] = []
    var reviewsDeleteCalls: [String] = []
    var nextReviewsListJson: String = "[]"
    var nextReviewsCreateJson: String = "{}"
    var nextReviewsUpdateJson: String = "{}"
    func reviewsList(targetType: String, targetId: String) async throws -> String {
        reviewsListCalls.append((targetType, targetId))
        return nextReviewsListJson
    }
    func reviewsCreate(paramsJson: String) async throws -> String {
        reviewsCreateCalls.append(paramsJson)
        return nextReviewsCreateJson
    }
    func reviewsUpdate(id: String, patchJson: String) async throws -> String {
        reviewsUpdateCalls.append((id, patchJson))
        return nextReviewsUpdateJson
    }
    func reviewsDelete(id: String) async throws {
        reviewsDeleteCalls.append(id)
    }

    var rolesGetMyRolesCount = 0
    var rolesHasPermissionCalls: [String] = []
    var nextRolesGetMyRolesJson: String = "[]"
    var nextRolesHasPermission: Bool = false
    func rolesGetMyRoles() async throws -> String {
        rolesGetMyRolesCount += 1
        return nextRolesGetMyRolesJson
    }
    func rolesHasPermission(permission: String) async throws -> Bool {
        rolesHasPermissionCalls.append(permission)
        return nextRolesHasPermission
    }

    var referralsGetReferralCodeCount = 0
    var referralsClaimReferralCalls: [String] = []
    var referralsCreateCalls: [(String?, UInt32?)] = []
    var nextReferralsGetReferralCodeJson: String = "{}"
    var nextReferralsClaimReferralJson: String = "{}"
    var nextReferralsCreateJson: String = "{}"
    func referralsGetReferralCode() async throws -> String {
        referralsGetReferralCodeCount += 1
        return nextReferralsGetReferralCodeJson
    }
    func referralsClaimReferral(code: String) async throws -> String {
        referralsClaimReferralCalls.append(code)
        return nextReferralsClaimReferralJson
    }
    func referralsCreate(code: String?, maxUses: UInt32?) async throws -> String {
        referralsCreateCalls.append((code, maxUses))
        return nextReferralsCreateJson
    }

    // ── lifecycle stubs (exercised in commit 3) ──
    var catalogListCount = 0
    var nextCatalogListJson: String = "[]"
    func catalogList() async throws -> String {
        catalogListCount += 1
        return nextCatalogListJson
    }

    var contentGetTodayCalls: [String?] = []
    var contentGetLibraryCalls: [(String?, UInt32?, String?)] = []
    var contentGetItemCalls: [String] = []
    var contentUpdateItemCalls: [(String, String)] = []
    var contentCreateItemCalls: [(String, String)] = []
    var nextContentGetTodayJson: String = "null"
    var nextContentGetLibraryJson: String = "[]"
    var nextContentGetItemJson: String = "{}"
    var nextContentUpdateItemJson: String = "{}"
    var nextContentCreateItemJson: String = "{}"
    func contentGetToday(channel: String?) async throws -> String {
        contentGetTodayCalls.append(channel)
        return nextContentGetTodayJson
    }
    func contentGetLibrary(channel: String?, limit: UInt32?, cursor: String?) async throws -> String {
        contentGetLibraryCalls.append((channel, limit, cursor))
        return nextContentGetLibraryJson
    }
    func contentGetItem(id: String) async throws -> String {
        contentGetItemCalls.append(id)
        return nextContentGetItemJson
    }
    func contentUpdateItem(id: String, stateJson: String) async throws -> String {
        contentUpdateItemCalls.append((id, stateJson))
        return nextContentUpdateItemJson
    }
    func contentCreateItem(channel: String, itemJson: String) async throws -> String {
        contentCreateItemCalls.append((channel, itemJson))
        return nextContentCreateItemJson
    }

    var deepLinksGetCalls: [String] = []
    var deepLinksCreateCalls: [String] = []
    var nextDeepLinksGetJson: String = "{}"
    var nextDeepLinksCreateJson: String = "{}"
    func deepLinksGet(shortCode: String) async throws -> String {
        deepLinksGetCalls.append(shortCode)
        return nextDeepLinksGetJson
    }
    func deepLinksCreate(paramsJson: String) async throws -> String {
        deepLinksCreateCalls.append(paramsJson)
        return nextDeepLinksCreateJson
    }

    // ── diagnostics ──
    //
    // `diagnosticsPing` returns a JSON-encoded `PingResult` envelope.
    // Test cases override `nextDiagnosticsPingJson` to drive both the
    // happy path (`ok:true`) and the server-side-failure path
    // (`ok:false, error:"..."`); the auth-failure path is exercised by
    // setting `diagnosticsPingError` so the protocol method throws,
    // matching how the Rust core surfaces 401 as `AmbaError::Unauthorized`.
    var diagnosticsPingCount = 0
    var nextDiagnosticsPingJson: String = #"{"ok":true,"server_project_id":"proj_abc","environment":"sandbox","key_fingerprint":"4f8a","latency_ms":73,"error":null}"#
    var diagnosticsPingError: Error?
    func diagnosticsPing() async throws -> String {
        diagnosticsPingCount += 1
        if let e = diagnosticsPingError { throw e }
        return nextDiagnosticsPingJson
    }

    var onboardingGetStatusCount = 0
    var onboardingNextStepCalls: [String] = []
    var onboardingSkipStepCount = 0
    var onboardingCompleteCount = 0
    var nextOnboardingGetStatusJson: String = "{}"
    var nextOnboardingNextStepJson: String = "{}"
    var nextOnboardingSkipStepJson: String = "{}"
    var nextOnboardingCompleteJson: String = "{}"
    func onboardingGetStatus() async throws -> String {
        onboardingGetStatusCount += 1
        return nextOnboardingGetStatusJson
    }
    func onboardingNextStep(payloadJson: String) async throws -> String {
        onboardingNextStepCalls.append(payloadJson)
        return nextOnboardingNextStepJson
    }
    func onboardingSkipStep() async throws -> String {
        onboardingSkipStepCount += 1
        return nextOnboardingSkipStepJson
    }
    func onboardingComplete() async throws -> String {
        onboardingCompleteCount += 1
        return nextOnboardingCompleteJson
    }
}

// MARK: - URLProtocol stub for storage.upload PUT

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var captured: [URLRequest] = []
    nonisolated(unsafe) static var capturedBodies: [Data] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.captured.append(request)
        if let body = request.httpBody {
            Self.capturedBodies.append(body)
        } else if let stream = request.httpBodyStream {
            var data = Data()
            stream.open()
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
            defer { buf.deallocate(); stream.close() }
            while stream.hasBytesAvailable {
                let n = stream.read(buf, maxLength: 1024)
                if n <= 0 { break }
                data.append(buf, count: n)
            }
            Self.capturedBodies.append(data)
        }
        let (response, data) = (Self.handler ?? { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        })(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

// MARK: - Helpers

private func makeUploadSession(stubbing protocolClass: AnyClass) -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [protocolClass]
    return URLSession(configuration: config)
}

private func makeClient(_ mock: MockAmbaCore, uploadSession: URLSession = .shared) -> AmbaClient {
    return AmbaClient(core: mock, uploadSession: uploadSession)
}

// MARK: - AmbaClient tests (Constructor DI)

final class AmbaClientTests: XCTestCase {
    var mock: MockAmbaCore!
    var client: AmbaClient!

    override func setUp() {
        super.setUp()
        mock = MockAmbaCore()
        client = makeClient(mock)
        StubURLProtocol.handler = nil
        StubURLProtocol.captured = []
        StubURLProtocol.capturedBodies = []
    }

    // 1. AmbaClient.init(apiKey:) validates apiKey before touching the core
    func testClientPublicInitRejectsEmptyApiKey() {
        XCTAssertThrowsError(try AmbaClient(apiKey: "")) { err in
            guard case AmbaSwiftError.invalidConfig = err else {
                XCTFail("expected invalidConfig, got \(err)")
                return
            }
        }
    }

    // 2. anonymousId / appUserId / isAuthenticated pass-through
    func testIdentityAccessorsDelegateToCore() {
        mock.anonId = "anon-XYZ"
        mock.appUid = "user-42"
        mock.authed = true
        XCTAssertEqual(client.anonymousId, "anon-XYZ")
        XCTAssertEqual(client.appUserId, "user-42")
        XCTAssertTrue(client.isAuthenticated)
    }

    // 3. setDebug forwards
    func testSetDebugForwards() {
        client.setDebug(true)
        client.setDebug(false)
        XCTAssertEqual(mock.setDebugCalls, [true, false])
    }

    // 4. events.track with no properties
    func testEventsTrackWithoutProperties() async throws {
        try await client.events.track("session_start")
        XCTAssertEqual(mock.trackCalls.count, 1)
        XCTAssertEqual(mock.trackCalls[0].event, "session_start")
        XCTAssertNil(mock.trackCalls[0].propsJson)
    }

    // 5. events.track with properties serializes to JSON
    func testEventsTrackSerializesProperties() async throws {
        try await client.events.track("purchase", properties: ["amount": 12.5, "currency": "USD"])
        XCTAssertEqual(mock.trackCalls.count, 1)
        let json = try XCTUnwrap(mock.trackCalls[0].propsJson)
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        XCTAssertEqual(parsed?["amount"] as? Double, 12.5)
        XCTAssertEqual(parsed?["currency"] as? String, "USD")
    }

    // 6. events.track surfaces core errors
    func testEventsTrackPropagatesCoreError() async {
        struct Boom: Error {}
        mock.trackError = Boom()
        do {
            try await client.events.track("x")
            XCTFail("expected throw")
        } catch is Boom {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // 7. auth.signInAnonymously dispatches
    func testAuthSignInAnonymouslyDispatches() async throws {
        let res = try await client.auth.signInAnonymously()
        XCTAssertEqual(mock.signInAnonymouslyCount, 1)
        XCTAssertEqual(res.sessionToken, "sess")
        XCTAssertEqual(res.user.id, "u_mock")
    }

    // 8. auth.signInWithEmail forwards credentials
    func testAuthSignInWithEmailForwardsCredentials() async throws {
        _ = try await client.auth.signInWithEmail(email: "a@b.test", password: "hunter2")
        XCTAssertEqual(mock.signInWithEmailCalls.count, 1)
        XCTAssertEqual(mock.signInWithEmailCalls[0].email, "a@b.test")
        XCTAssertEqual(mock.signInWithEmailCalls[0].password, "hunter2")
    }

    // 9. auth.signUpWithEmail forwards
    func testAuthSignUpWithEmailForwards() async throws {
        _ = try await client.auth.signUpWithEmail(email: "new@b.test", password: "passw")
        XCTAssertEqual(mock.signUpWithEmailCalls.count, 1)
        XCTAssertEqual(mock.signUpWithEmailCalls[0].email, "new@b.test")
    }

    // 10. auth.signInWithApple maps to Apple provider
    func testAuthSignInWithAppleMapsProvider() async throws {
        _ = try await client.auth.signInWithApple(identityToken: "apple-id-token")
        XCTAssertEqual(mock.signInWithSocialCalls.count, 1)
        XCTAssertEqual(mock.signInWithSocialCalls[0].provider, .apple)
        XCTAssertEqual(mock.signInWithSocialCalls[0].idToken, "apple-id-token")
    }

    // 11. auth.signInWithGoogle maps to Google provider
    func testAuthSignInWithGoogleMapsProvider() async throws {
        _ = try await client.auth.signInWithGoogle(idToken: "g-id-token")
        XCTAssertEqual(mock.signInWithSocialCalls[0].provider, .google)
    }

    // 12. auth.signOut default rotate=false
    func testAuthSignOutDefaultRotateFalse() async throws {
        try await client.auth.signOut()
        XCTAssertEqual(mock.signOutCalls, [false])
    }

    // 13. auth.signOut rotate=true
    func testAuthSignOutRotateTrue() async throws {
        try await client.auth.signOut(rotateAnonymousId: true)
        XCTAssertEqual(mock.signOutCalls, [true])
    }

    // 14. auth.refresh and auth.me dispatch
    func testAuthRefreshAndMe() async throws {
        _ = try await client.auth.refresh()
        let me = try await client.auth.me()
        XCTAssertEqual(mock.refreshSessionCount, 1)
        XCTAssertEqual(mock.meCount, 1)
        XCTAssertEqual(me.id, "u_mock")
    }

    // 14b. auth.getSession returns nil when unauthenticated.
    func testAuthGetSessionReturnsNilWhenUnauthenticated() async throws {
        mock.authed = false
        let session = try await client.auth.getSession()
        XCTAssertNil(session)
        // me() should NOT be called when unauthenticated.
        XCTAssertEqual(mock.meCount, 0)
    }

    // 14c. auth.getSession snapshots user when authenticated.
    func testAuthGetSessionSnapshotsUserWhenAuthenticated() async throws {
        mock.authed = true
        let session = try await client.auth.getSession()
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.user.id, "u_mock")
        // SDK-managed tokens are empty per docs.
        XCTAssertEqual(session?.sessionToken, "")
        XCTAssertEqual(session?.refreshToken, "")
        XCTAssertEqual(session?.expiresAt, "")
    }

    // 14d. auth.getAnonymousId reads core anonymous id.
    func testAuthGetAnonymousId() async throws {
        mock.anonId = "anon-foo"
        let anon = await client.auth.getAnonymousId()
        XCTAssertEqual(anon, "anon-foo")
    }

    // 14e. auth.onAuthStateChange fires after signIn and after signOut,
    // and the unsubscribe closure removes the listener.
    func testAuthOnAuthStateChangeFiresAndUnsubscribes() async throws {
        actor Recorder {
            var sessions: [Session?] = []
            func append(_ s: Session?) { sessions.append(s) }
            func snapshot() -> [Session?] { sessions }
        }
        let recorder = Recorder()
        let unsubscribe = client.auth.onAuthStateChange { session in
            Task { await recorder.append(session) }
        }

        _ = try await client.auth.signInAnonymously()
        try await Task.sleep(nanoseconds: 50_000_000)
        var snap = await recorder.snapshot()
        XCTAssertEqual(snap.count, 1)
        XCTAssertNotNil(snap[0])
        XCTAssertEqual(snap[0]?.user.id, "u_mock")

        try await client.auth.signOut()
        try await Task.sleep(nanoseconds: 50_000_000)
        snap = await recorder.snapshot()
        XCTAssertEqual(snap.count, 2)
        XCTAssertNil(snap[1])

        // Unsubscribe — subsequent auth events must NOT reach the listener.
        unsubscribe()
        _ = try await client.auth.signInAnonymously()
        try await Task.sleep(nanoseconds: 50_000_000)
        snap = await recorder.snapshot()
        XCTAssertEqual(snap.count, 2, "listener was unsubscribed but still fired")
    }

    // 15. collections.find encodes empty options to "{}" and decodes typed response
    func testCollectionsFindEncodesEmptyOptionsAndDecodes() async throws {
        struct Post: Decodable, Equatable { let id: String; let title: String }
        mock.nextCollectionsFindResponseJson = #"{"data":[{"id":"p1","title":"hi"},{"id":"p2","title":"yo"}],"next_cursor":"cur","has_more":true}"#
        let resp = try await client.collections.find("posts", as: Post.self)
        XCTAssertEqual(mock.collectionsFindCalls.count, 1)
        XCTAssertEqual(mock.collectionsFindCalls[0].collection, "posts")
        XCTAssertEqual(mock.collectionsFindCalls[0].optionsJson, "{}")
        XCTAssertEqual(resp.data, [Post(id: "p1", title: "hi"), Post(id: "p2", title: "yo")])
        XCTAssertEqual(resp.nextCursor, "cur")
        XCTAssertTrue(resp.hasMore)
    }

    // 16. collections.find with FindOptions encodes snake-case + filter
    func testCollectionsFindEncodesOptionsWithFilterAndOrder() async throws {
        struct Row: Decodable { let id: String }
        let options = FindOptions(
            filter: AnyEncodable(["status": "active"]),
            order: [OrderBy(column: "created_at", direction: .desc)],
            limit: 25,
            cursor: "page-2",
            select: ["id", "name"],
            includeDeleted: true
        )
        _ = try await client.collections.find("widgets", options: options, as: Row.self)
        let sent = mock.collectionsFindCalls[0].optionsJson
        XCTAssertTrue(sent.contains("\"include_deleted\":true"), "expected snake_case include_deleted in: \(sent)")
        XCTAssertTrue(sent.contains("\"limit\":25"))
        XCTAssertTrue(sent.contains("\"cursor\":\"page-2\""))
        XCTAssertTrue(sent.contains("\"status\":\"active\""))
        XCTAssertTrue(sent.contains("\"direction\":\"desc\""))
    }

    // 17. collections.findOne decodes into typed shape
    func testCollectionsFindOneDecodes() async throws {
        struct Row: Decodable, Equatable { let id: String; let name: String }
        mock.nextCollectionsFindOneResponseJson = #"{"id":"row-9","name":"zeta"}"#
        let row = try await client.collections.findOne("widgets", id: "row-9", as: Row.self)
        XCTAssertEqual(row, Row(id: "row-9", name: "zeta"))
        XCTAssertEqual(mock.collectionsFindOneCalls[0].collection, "widgets")
        XCTAssertEqual(mock.collectionsFindOneCalls[0].id, "row-9")
    }

    // 18. collections.insert serializes row + decodes response
    func testCollectionsInsertSerializesRow() async throws {
        struct Row: Decodable, Equatable { let id: String; let name: String }
        mock.nextCollectionsInsertResponseJson = #"{"id":"i-1","name":"alpha"}"#
        let row: Row = try await client.collections.insert("widgets", row: ["name": "alpha", "count": 3])
        XCTAssertEqual(row, Row(id: "i-1", name: "alpha"))
        let sent = mock.collectionsInsertCalls[0].rowJson
        let parsed = try JSONSerialization.jsonObject(with: Data(sent.utf8)) as? [String: Any]
        XCTAssertEqual(parsed?["name"] as? String, "alpha")
        XCTAssertEqual(parsed?["count"] as? Int, 3)
    }

    // 19. collections.update serializes set + ids
    func testCollectionsUpdateSerializesSet() async throws {
        struct Row: Decodable, Equatable { let id: String; let name: String }
        mock.nextCollectionsUpdateResponseJson = #"{"id":"r-1","name":"beta"}"#
        let row: Row = try await client.collections.update("widgets", id: "r-1", set: ["name": "beta"])
        XCTAssertEqual(row.name, "beta")
        XCTAssertEqual(mock.collectionsUpdateCalls[0].id, "r-1")
        XCTAssertTrue(mock.collectionsUpdateCalls[0].setJson.contains("\"name\":\"beta\""))
    }

    // 20. collections.delete forwards
    func testCollectionsDeleteForwards() async throws {
        try await client.collections.delete("widgets", id: "r-9")
        XCTAssertEqual(mock.collectionsDeleteCalls[0].collection, "widgets")
        XCTAssertEqual(mock.collectionsDeleteCalls[0].id, "r-9")
    }

    // 21. collections.find surfaces invalid JSON as decode error
    func testCollectionsFindBubblesDecodeFailure() async {
        struct Row: Decodable { let id: String }
        mock.nextCollectionsFindResponseJson = "not-json-at-all"
        do {
            _ = try await client.collections.find("widgets", as: Row.self)
            XCTFail("expected decode failure")
        } catch is DecodingError {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // 22. storage.presign forwards args
    func testStoragePresignForwards() async throws {
        let pre = try await client.storage.presign(
            bucket: "media",
            filename: "kitten.png",
            mimeType: "image/png",
            sizeBytes: 4096,
            retentionDays: 30
        )
        XCTAssertEqual(pre.uploadUrl, "https://r2.example/upload")
        let call = mock.storagePresignCalls[0]
        XCTAssertEqual(call.bucket, "media")
        XCTAssertEqual(call.filename, "kitten.png")
        XCTAssertEqual(call.mimeType, "image/png")
        XCTAssertEqual(call.sizeBytes, 4096)
        XCTAssertEqual(call.retentionDays, 30)
    }

    // 23. storage.commit forwards
    func testStorageCommitForwards() async throws {
        let asset = try await client.storage.commit(uploadId: "u1", assetId: "a1")
        XCTAssertEqual(asset.id, "a1")
        XCTAssertEqual(mock.storageCommitCalls[0].uploadId, "u1")
    }

    // 24. storage.upload does presign → PUT → commit and forwards body + headers
    func testStorageUploadEndToEnd() async throws {
        let body = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x10, 0x20])
        mock.nextPresign = PresignDataFfi(
            uploadId: "U-99",
            uploadUrl: "https://r2.example/upload/path",
            uploadHeaders: [HttpHeader(name: "x-amba-test", value: "yes"), HttpHeader(name: "Content-Type", value: "image/png")],
            assetId: "A-99"
        )
        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        let session = makeUploadSession(stubbing: StubURLProtocol.self)
        let injectedClient = makeClient(mock, uploadSession: session)

        let asset = try await injectedClient.storage.upload(bucket: "media", data: body, filename: "k.png", mimeType: "image/png", retentionDays: 14)

        XCTAssertEqual(asset.id, "a1") // mock's default committed asset
        // presign forwarded args
        let pre = mock.storagePresignCalls[0]
        XCTAssertEqual(pre.bucket, "media")
        XCTAssertEqual(pre.sizeBytes, UInt64(body.count))
        XCTAssertEqual(pre.retentionDays, 14)
        // commit fired with the presign IDs
        XCTAssertEqual(mock.storageCommitCalls[0].uploadId, "U-99")
        XCTAssertEqual(mock.storageCommitCalls[0].assetId, "A-99")
        // PUT happened
        XCTAssertEqual(StubURLProtocol.captured.count, 1)
        let req = StubURLProtocol.captured[0]
        XCTAssertEqual(req.httpMethod, "PUT")
        XCTAssertEqual(req.url?.absoluteString, "https://r2.example/upload/path")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-amba-test"), "yes")
        // Body forwarded
        XCTAssertEqual(StubURLProtocol.capturedBodies.first, body)
    }

    // 25. storage.upload surfaces non-2xx as uploadFailed
    func testStorageUploadFailsOnNon2xx() async {
        StubURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        let session = makeUploadSession(stubbing: StubURLProtocol.self)
        let injectedClient = makeClient(mock, uploadSession: session)
        do {
            _ = try await injectedClient.storage.upload(bucket: "b", data: Data([0x01]), filename: "x", mimeType: "image/png")
            XCTFail("expected uploadFailed")
        } catch AmbaSwiftError.uploadFailed {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // 26. push.register forwards platform + bundleId
    func testPushRegisterForwards() async throws {
        let tok = try await client.push.register(token: "device-1", platform: .fcm, bundleId: "app.bundle")
        XCTAssertEqual(tok.id, "pt_1")
        let call = mock.pushRegisterCalls[0]
        XCTAssertEqual(call.token, "device-1")
        XCTAssertEqual(call.platform, .fcm)
        XCTAssertEqual(call.bundleId, "app.bundle")
    }

    // 27. push.subscribe forwards
    func testPushSubscribeForwards() async throws {
        try await client.push.subscribe(topic: "news")
        XCTAssertEqual(mock.pushSubscribeCalls, ["news"])
    }

    // 28. entitlements.list returns mock list
    func testEntitlementsList() async throws {
        mock.nextEntitlements = [UserEntitlementFfi(id: "e-1", name: "pro", isActive: true, source: "rc", expiresAt: nil, grantedAt: nil, metadataJson: "{}")]
        let ents = try await client.entitlements.list()
        XCTAssertEqual(ents.count, 1)
        XCTAssertEqual(ents[0].name, "pro")
    }

    // 29. entitlements.has — true and missing both
    func testEntitlementsHas() async {
        mock.nextEntitlementsHas = true
        let yes = await client.entitlements.has("pro")
        mock.nextEntitlementsHas = false
        let no = await client.entitlements.has("ultra")
        XCTAssertTrue(yes)
        XCTAssertFalse(no)
        XCTAssertEqual(mock.entitlementsHasCalls, ["pro", "ultra"])
    }

    // 30. ai.anthropic.messages.create encodes the request + decodes response
    func testAiAnthropicMessagesEncodeDecode() async throws {
        mock.nextAiResponseJson = #"{"content":[{"type":"text","text":"yo"}],"usage":{"input_tokens":7,"output_tokens":2},"stop_reason":"end_turn","model":"claude-x"}"#
        let req = AiMessageRequest(promptSlug: "haiku", variables: AnyEncodable(["mood": "calm"]), maxTokens: 256, temperature: 0.7, enablePromptCache: true)
        let resp = try await client.ai.anthropic.messages.create(request: req)
        XCTAssertEqual(resp.model, "claude-x")
        XCTAssertEqual(resp.usage.inputTokens, 7)
        XCTAssertEqual(resp.usage.outputTokens, 2)
        XCTAssertEqual(resp.stopReason, "end_turn")
        XCTAssertEqual(resp.content.count, 1)
        let sent = mock.aiCalls[0]
        XCTAssertTrue(sent.contains("\"prompt_slug\":\"haiku\""))
        XCTAssertTrue(sent.contains("\"max_tokens\":256"))
        XCTAssertTrue(sent.contains("\"enable_prompt_cache\":true"))
    }

    // 31. config.fetch decodes ConfigBundle from wire shape.
    //
    // Post-item-5 (#12) the wire shape is `{ "version": "<etag-prefix>" | null,
    // "values": {...} }`. The pre-fix shape had a `generated_at` field
    // that never matched server reality; we no longer decode it.
    func testConfigFetchDecodesBundle() async throws {
        mock.nextConfigFetchJson = #"{"version":"3","values":{"x":1}}"#
        let bundle = try await client.config.fetch()
        XCTAssertEqual(bundle.version, "3")
    }

    // 31b. config.fetch tolerates null version (new project, no
    // config_versions row → server omits ETag).
    func testConfigFetchTolerantesNullVersion() async throws {
        mock.nextConfigFetchJson = #"{"version":null,"values":{}}"#
        let bundle = try await client.config.fetch()
        XCTAssertNil(bundle.version)
    }

    // 32. flags.fetch dispatches and returns list
    func testFlagsFetchReturnsList() async throws {
        mock.nextFlags = [FlagAssignmentFfi(name: "exp.checkout", enabled: true, variant: "v2", payloadJson: "{}")]
        let flags = try await client.flags.fetch()
        XCTAssertEqual(flags.count, 1)
        XCTAssertEqual(flags[0].name, "exp.checkout")
        XCTAssertEqual(flags[0].variant, "v2")
    }

    // 33. AnyEncodable encodes deeply nested structures
    func testAnyEncodableEncodesNestedStructure() throws {
        struct W: Encodable {
            let any: AnyEncodable
        }
        let nested = W(any: AnyEncodable([
            "outer": [
                "inner": ["a": 1, "b": 2]
            ]
        ] as [String: [String: [String: Int]]]))
        let data = try JSONEncoder().encode(nested)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let outer = (parsed?["any"] as? [String: Any])?["outer"] as? [String: Any]
        let inner = outer?["inner"] as? [String: Any]
        XCTAssertEqual(inner?["a"] as? Int, 1)
        XCTAssertEqual(inner?["b"] as? Int, 2)
    }

    // 34. AnyDecodable decodes mixed-type arrays
    func testAnyDecodableMixedArray() throws {
        let json = #"[1, "two", true, null, {"k":"v"}, [10, 20]]"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AnyDecodable.self, from: json)
        let arr = try XCTUnwrap(decoded.value as? [Any])
        XCTAssertEqual(arr.count, 6)
        XCTAssertEqual(arr[0] as? Int64, 1)
        XCTAssertEqual(arr[1] as? String, "two")
        XCTAssertEqual(arr[2] as? Bool, true)
        XCTAssertTrue(arr[3] is NSNull)
        let obj = arr[4] as? [String: Any]
        XCTAssertEqual(obj?["k"] as? String, "v")
        let nestedArr = arr[5] as? [Any]
        XCTAssertEqual(nestedArr?.count, 2)
    }

    // 35. AnyDecodable decodes nested objects
    func testAnyDecodableNestedObject() throws {
        let json = #"{"a":{"b":{"c":42}}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AnyDecodable.self, from: json)
        let a = (decoded.value as? [String: Any])?["a"] as? [String: Any]
        let b = a?["b"] as? [String: Any]
        XCTAssertEqual(b?["c"] as? Int64, 42)
    }
}

// MARK: - Static facade smoke test
//
// The `Amba.*` static facade is a one-line passthrough to its singleton
// `AmbaClient`. Behavioral coverage lives on `AmbaClient` above. This
// single smoke test verifies the facade's input validation (which fires
// *before* building the client) so the unhappy path doesn't regress.
//
// The facade's singleton state is intentionally not asserted/mutated here
// — there is no test-only setter to reset it. Once `Amba.configure(...)`
// succeeds in a process, the singleton persists; production lifecycle
// is "configure once at app start, never again".

final class AmbaFacadeTests: XCTestCase {
    func testStaticConfigureRejectsEmptyApiKey() {
        XCTAssertThrowsError(try Amba.configure(apiKey: "")) { err in
            guard case AmbaSwiftError.invalidConfig = err else {
                XCTFail("expected invalidConfig, got \(err)")
                return
            }
        }
    }
}

// MARK: - Constructor DI isolation tests
//
// These tests explicitly verify the Constructor DI contract — the
// reason we did this refactor. Multiple `AmbaClient` instances are
// independent of each other and of `Amba.*` static state. A test
// that constructs one client cannot leak into another test that
// constructs a different one.

final class AmbaClientIsolationTests: XCTestCase {
    // 1. Two clients with separate mock cores receive their own traffic.
    //    Calls on clientA only land in mockA; calls on clientB only land
    //    in mockB. This is the central DI guarantee.
    func testTwoClientsWithDifferentCoresDoNotShareState() async throws {
        let mockA = MockAmbaCore()
        let mockB = MockAmbaCore()
        let clientA = AmbaClient(core: mockA)
        let clientB = AmbaClient(core: mockB)

        try await clientA.events.track("a1")
        try await clientA.events.track("a2")
        try await clientB.events.track("b1")

        XCTAssertEqual(mockA.trackCalls.map(\.event), ["a1", "a2"])
        XCTAssertEqual(mockB.trackCalls.map(\.event), ["b1"])
    }

    // 2. Each client owns its own namespace instances — they are not
    //    shared singletons across clients.
    func testEachClientHasOwnNamespaceInstances() {
        let mockA = MockAmbaCore()
        let mockB = MockAmbaCore()
        let a = AmbaClient(core: mockA)
        let b = AmbaClient(core: mockB)

        XCTAssertFalse(a.events === b.events)
        XCTAssertFalse(a.auth === b.auth)
        XCTAssertFalse(a.collections === b.collections)
        XCTAssertFalse(a.storage === b.storage)
        XCTAssertFalse(a.push === b.push)
        XCTAssertFalse(a.entitlements === b.entitlements)
        XCTAssertFalse(a.ai === b.ai)
        XCTAssertFalse(a.config === b.config)
        XCTAssertFalse(a.flags === b.flags)
    }

    // 3. Per-mock state changes don't leak across clients.
    //    Programming mockA's `nextAuthResult` to a custom value does not
    //    change what clientB sees when it calls auth.signInAnonymously().
    func testMockStateIsPerClient() async throws {
        let mockA = MockAmbaCore()
        let mockB = MockAmbaCore()
        let clientA = AmbaClient(core: mockA)
        let clientB = AmbaClient(core: mockB)

        let customUser = UserFfi(
            id: "u_A_only",
            email: nil, displayName: nil, avatarUrl: nil, externalId: nil,
            anonymousId: "anon-A",
            authProviders: [], propertiesJson: "{}"
        )
        mockA.nextAuthResult = AuthResultFfi(
            sessionToken: "sess_A",
            refreshToken: "refresh_A",
            user: customUser,
            anonymousId: "anon-A",
            expiresAt: nil
        )
        // mockB stays on its default

        let aResult = try await clientA.auth.signInAnonymously()
        let bResult = try await clientB.auth.signInAnonymously()

        XCTAssertEqual(aResult.sessionToken, "sess_A")
        XCTAssertEqual(aResult.user.id, "u_A_only")
        XCTAssertEqual(bResult.sessionToken, "sess") // mockB default
        XCTAssertEqual(bResult.user.id, "u_mock")    // mockB default
    }

    // 4. A single mock can power multiple clients — state sharing is
    //    opt-in, not accidental. (This is the inverse of test 1: when
    //    callers explicitly share a core, they get shared state.)
    func testSingleSharedCorePowersMultipleClients() async throws {
        let sharedMock = MockAmbaCore()
        let client1 = AmbaClient(core: sharedMock)
        let client2 = AmbaClient(core: sharedMock)

        try await client1.events.track("from-1")
        try await client2.events.track("from-2")

        XCTAssertEqual(sharedMock.trackCalls.map(\.event), ["from-1", "from-2"])
    }

    // 5. The `AmbaClient` internal init does not depend on, mutate, or
    //    consult `Amba.*` static state. Constructing a client never
    //    accidentally registers as the global singleton.
    func testClientConstructionDoesNotTouchStaticFacade() async throws {
        // Snapshot the facade's identity-state before: try to call a
        // facade method that would throw if no singleton was set, OR
        // succeed if one was set by a prior test. We don't actually
        // care about the value — only that constructing a fresh
        // AmbaClient below doesn't change it.
        let facadeBeforeAnonId = Amba.anonymousId

        let mock = MockAmbaCore()
        mock.anonId = "isolated-client-anon"
        let isolated = AmbaClient(core: mock)

        // isolated client reflects its own mock
        XCTAssertEqual(isolated.anonymousId, "isolated-client-anon")
        // facade is unchanged — constructing AmbaClient did not register
        // the new client as the singleton.
        XCTAssertEqual(Amba.anonymousId, facadeBeforeAnonId)
    }

    // 6. Construction is cheap — building many clients is fine, no
    //    accidental shared-mutable-state bookkeeping behind the scenes.
    func testManyClientsCanCoexist() async throws {
        let mocks = (0..<8).map { _ in MockAmbaCore() }
        let clients = mocks.map { AmbaClient(core: $0) }

        for (i, c) in clients.enumerated() {
            try await c.events.track("e-\(i)")
        }
        for (i, m) in mocks.enumerated() {
            XCTAssertEqual(m.trackCalls.map(\.event), ["e-\(i)"])
        }
    }
}

// MARK: - New namespace happy-path tests
//
// One happy-path test per new namespace. Each test programs a realistic
// JSON shape on the mock and asserts the wrapper decodes + forwards
// correctly. The fixture JSON mirrors the actual Rust core's wire shape
// (snake_case keys, ISO-8601 timestamps).
//
// These tests are deliberately compact — the Rust core has 276+ tests
// covering server-shape correctness, so what's verified here is the
// Swift-side decode + dispatch path, not the wire shape itself.

final class AmbaNewNamespaceTests: XCTestCase {
    var mock: MockAmbaCore!
    var client: AmbaClient!

    override func setUp() {
        super.setUp()
        mock = MockAmbaCore()
        client = AmbaClient(core: mock)
    }

    // MARK: Gamification

    func testAchievementsAllDecodes() async throws {
        mock.nextAchievementsGetAllJson = #"""
        [{"id":"a1","key":"first_login","name":"Welcome","description":"Sign in once","icon_url":"https://cdn/x.png","xp_reward":10,"criteria":{}}]
        """#
        let achs = try await client.achievements.all()
        XCTAssertEqual(achs.count, 1)
        XCTAssertEqual(achs[0].key, "first_login")
        XCTAssertEqual(achs[0].iconUrl, "https://cdn/x.png")
        XCTAssertEqual(achs[0].xpReward, 10)
        XCTAssertEqual(mock.achievementsGetAllCount, 1)
    }

    func testAchievementsProgressDecodes() async throws {
        mock.nextAchievementsGetProgressJson = #"""
        [{"achievement_id":"a1","key":"k1","progress":0.5,"unlocked":false},
         {"achievement_id":"a2","key":"k2","progress":1.0,"unlocked":true,"unlocked_at":"2026-05-12T00:00:00Z"}]
        """#
        let prog = try await client.achievements.progress()
        XCTAssertEqual(prog.count, 2)
        XCTAssertFalse(prog[0].unlocked)
        XCTAssertTrue(prog[1].unlocked)
        XCTAssertNotNil(prog[1].unlockedAt)
    }

    func testChallengesActiveDecodesAndForwards() async throws {
        mock.nextChallengesGetActiveJson = #"""
        [{"id":"c1","key":"weekly","name":"Weekly Burst","starts_at":"2026-05-01T00:00:00Z","ends_at":"2026-05-08T00:00:00Z","criteria":{"x":1},"reward":{}}]
        """#
        let cs = try await client.challenges.active()
        XCTAssertEqual(cs.count, 1)
        XCTAssertEqual(cs[0].id, "c1")
        XCTAssertEqual(cs[0].name, "Weekly Burst")
    }

    func testChallengesClaimForwardsId() async throws {
        mock.nextChallengesClaimJson = #"""
        {"challenge_id":"c1","progress":1.0,"completed":true,"claimed":true,"completed_at":"2026-05-08T00:00:00Z","claimed_at":"2026-05-08T01:00:00Z"}
        """#
        let p = try await client.challenges.claim(id: "c1")
        XCTAssertEqual(mock.challengesClaimCalls, ["c1"])
        XCTAssertTrue(p.claimed)
    }

    func testCurrenciesBalanceDecodes() async throws {
        mock.nextCurrenciesGetBalanceJson = #"""
        [{"currency_id":"cur_gold","key":"gold","balance":120,"updated_at":"2026-05-12T10:00:00Z"}]
        """#
        let balances = try await client.currencies.balance()
        XCTAssertEqual(balances.count, 1)
        XCTAssertEqual(balances[0].key, "gold")
        XCTAssertEqual(balances[0].balance, 120)
    }

    func testCurrenciesTransactionsForwardsKey() async throws {
        mock.nextCurrenciesGetTransactionsJson = #"""
        [{"id":"tx1","currency_id":"cur_gold","delta":-5,"balance_after":115,"reason":"purchase","created_at":"2026-05-12T11:00:00Z"}]
        """#
        let txs = try await client.currencies.transactions(currencyKey: "gold")
        XCTAssertEqual(mock.currenciesGetTransactionsCalls, ["gold"])
        XCTAssertEqual(txs.count, 1)
        XCTAssertEqual(txs[0].delta, -5)
    }

    func testInventoryItemsAndPurchase() async throws {
        mock.nextInventoryGetItemsJson = #"""
        [{"id":"i1","catalog_item_id":"c1","sku":"sword","quantity":1,"acquired_at":"2026-05-12T00:00:00Z","metadata":{}}]
        """#
        let items = try await client.inventory.items()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].sku, "sword")

        mock.nextInventoryPurchaseJson = #"""
        {"id":"i2","catalog_item_id":"c2","sku":"shield","quantity":1,"acquired_at":"2026-05-12T00:00:00Z","metadata":{}}
        """#
        let purchased = try await client.inventory.purchase(PurchaseRequest(sku: "shield"))
        XCTAssertEqual(purchased.sku, "shield")
        let sent = mock.inventoryPurchaseCalls[0]
        XCTAssertTrue(sent.contains("\"sku\":\"shield\""))
    }

    func testInventoryConsumeSerializesRequest() async throws {
        mock.nextInventoryConsumeJson = #"""
        {"id":"i1","catalog_item_id":"c1","sku":"potion","quantity":1,"acquired_at":"2026-05-12T00:00:00Z","metadata":{}}
        """#
        _ = try await client.inventory.consume(ConsumeRequest(itemId: "i1", quantity: 2))
        let sent = mock.inventoryConsumeCalls[0]
        XCTAssertTrue(sent.contains("\"item_id\":\"i1\""))
        XCTAssertTrue(sent.contains("\"quantity\":2"))
    }

    func testLeaderboardsGetAndEntries() async throws {
        mock.nextLeaderboardsGetJson = #"""
        {"id":"lb1","key":"global","name":"Global","period":"alltime","direction":"desc","starts_at":null,"ends_at":null}
        """#
        let lb = try await client.leaderboards.get(key: "global")
        XCTAssertEqual(lb.key, "global")
        XCTAssertNil(lb.startsAt)

        mock.nextLeaderboardsGetEntriesJson = #"""
        [{"rank":1,"user_id":"u_a","display_name":"Alice","avatar_url":null,"score":98.5}]
        """#
        let entries = try await client.leaderboards.entries(key: "global", limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].rank, 1)
        XCTAssertEqual(entries[0].displayName, "Alice")
        XCTAssertEqual(mock.leaderboardsGetEntriesCalls[0].0, "global")
        XCTAssertEqual(mock.leaderboardsGetEntriesCalls[0].1, 10)
    }

    func testStoresListAndPurchase() async throws {
        mock.nextStoresListJson = #"""
        [{"id":"s1","key":"main","name":"Main Store"}]
        """#
        let stores = try await client.stores.list()
        XCTAssertEqual(stores.count, 1)

        mock.nextStoresPurchaseJson = #"""
        {"id":"p1","user_id":"u1","purchase_option_id":"po1","status":"completed","purchased_at":"2026-05-12T00:00:00Z","receipt":{"raw":"x"}}
        """#
        let result = try await client.stores.purchase(storeKey: "main", purchaseOptionId: "po1", receipt: ["raw": "x"])
        XCTAssertEqual(result.status, "completed")
        let call = mock.storesPurchaseCalls[0]
        XCTAssertEqual(call.0, "main")
        XCTAssertEqual(call.1, "po1")
        XCTAssertTrue(call.2.contains("\"raw\":\"x\""))
    }

    func testXpBalanceAndClaim() async throws {
        // Payload includes the new xp_this_period field.
        mock.nextXpGetBalanceJson = #"""
        {"user_id":"u1","total_xp":1500,"current_level":3,"xp_into_level":500,"xp_to_next_level":500,"xp_this_period":120,"updated_at":"2026-05-12T00:00:00Z"}
        """#
        let bal = try await client.xp.balance()
        XCTAssertEqual(bal.totalXp, 1500)
        XCTAssertEqual(bal.currentLevel, 3)
        XCTAssertEqual(bal.xpThisPeriod, 120)

        mock.nextXpClaimJson = #"""
        {"id":"tx1","delta":50,"reason":"daily","source":"grant","created_at":"2026-05-12T00:00:00Z"}
        """#
        let tx = try await client.xp.claim(grantKey: "daily")
        XCTAssertEqual(mock.xpClaimCalls, ["daily"])
        XCTAssertEqual(tx.delta, 50)
    }

    /// Backward-compat: payloads from older servers without xp_this_period
    /// must decode (matches Rust `#[serde(default)]`).
    func testXpBalanceWithoutThisPeriodDefaultsToZero() async throws {
        mock.nextXpGetBalanceJson = #"""
        {"user_id":"u1","total_xp":1500,"current_level":3,"xp_into_level":500,"xp_to_next_level":500,"updated_at":"2026-05-12T00:00:00Z"}
        """#
        let bal = try await client.xp.balance()
        XCTAssertEqual(bal.xpThisPeriod, 0)
    }

    func testStreaksAllAndQualify() async throws {
        // Payload includes the new status + freezes_remaining fields.
        mock.nextStreaksGetAllJson = #"""
        [{"id":"s1","key":"daily_login","name":"Daily Login","current_length":3,"longest_length":10,"last_qualified_on":"2026-05-11","status":"active","freezes_remaining":2,"updated_at":"2026-05-12T00:00:00Z"}]
        """#
        let all = try await client.streaks.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].currentLength, 3)
        XCTAssertEqual(all[0].lastQualifiedOn, "2026-05-11")
        XCTAssertEqual(all[0].status, "active")
        XCTAssertEqual(all[0].freezesRemaining, 2)

        mock.nextStreaksQualifyJson = #"""
        {"id":"s1","key":"daily_login","name":"Daily Login","current_length":4,"longest_length":10,"last_qualified_on":"2026-05-12","status":"active","freezes_remaining":2,"updated_at":"2026-05-12T12:00:00Z"}
        """#
        let s = try await client.streaks.qualify(streakKey: "daily_login")
        XCTAssertEqual(s.currentLength, 4)
        XCTAssertEqual(s.status, "active")
        XCTAssertEqual(mock.streaksQualifyCalls, ["daily_login"])
    }

    /// Backward-compat: pre-status / pre-freezes payloads must still decode
    /// (matches Rust `#[serde(default)]`).
    func testStreakWithoutStatusOrFreezesDefaults() async throws {
        mock.nextStreaksGetAllJson = #"""
        [{"id":"s1","key":"daily_login","name":"Daily Login","current_length":3,"longest_length":10,"last_qualified_on":"2026-05-11","updated_at":"2026-05-12T00:00:00Z"}]
        """#
        let all = try await client.streaks.all()
        XCTAssertEqual(all[0].status, "")
        XCTAssertEqual(all[0].freezesRemaining, 0)
    }

    // MARK: Social

    func testFeedsActivityDecodes() async throws {
        mock.nextFeedsGetActivityJson = #"""
        {"data":[{"id":"f1","actor_id":"u1","verb":"posted","object_type":"post","object_id":"p1","target_type":null,"target_id":null,"data":{},"created_at":"2026-05-12T00:00:00Z"}],"next_cursor":"abc"}
        """#
        let resp = try await client.feeds.activity(feed: "timeline", cursor: nil)
        XCTAssertEqual(resp.data.count, 1)
        XCTAssertEqual(resp.nextCursor, "abc")
        XCTAssertEqual(mock.feedsGetActivityCalls[0].0, "timeline")
    }

    func testFriendsListAndBlock() async throws {
        mock.nextFriendsGetListJson = #"""
        [{"id":"f1","user_id":"u1","friend_id":"u2","state":"accepted","created_at":"2026-05-01T00:00:00Z"}]
        """#
        let list = try await client.friends.list()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].state, .accepted)

        mock.nextFriendsBlockUserJson = #"""
        {"id":"f2","user_id":"u1","friend_id":"u3","state":"blocked","created_at":"2026-05-12T00:00:00Z"}
        """#
        let blocked = try await client.friends.blockUser(userId: "u3")
        XCTAssertEqual(blocked.state, .blocked)
        XCTAssertEqual(mock.friendsBlockUserCalls, ["u3"])
    }

    func testFriendsFriendsAndUnblock() async throws {
        mock.nextFriendsGetFriendsJson = #"""
        [{"id":"f1","user_id":"u1","friend_id":"u2","state":"accepted","created_at":"2026-05-01T00:00:00Z"}]
        """#
        let frs = try await client.friends.friends()
        XCTAssertEqual(frs.count, 1)

        try await client.friends.unblockUser(userId: "u3")
        XCTAssertEqual(mock.friendsUnblockUserCalls, ["u3"])

        try await client.friends.removeBlock(friendshipId: "fr-99")
        XCTAssertEqual(mock.friendsRemoveBlockCalls, ["fr-99"])
    }

    func testGroupsCreateAndJoin() async throws {
        mock.nextGroupsCreateJson = #"""
        {"id":"g1","name":"Heroes","description":null,"avatar_url":null,"created_by":"u1","member_count":1,"created_at":"2026-05-12T00:00:00Z","updated_at":"2026-05-12T00:00:00Z","metadata":{}}
        """#
        let g = try await client.groups.create(GroupCreate(name: "Heroes"))
        XCTAssertEqual(g.name, "Heroes")
        XCTAssertTrue(mock.groupsCreateCalls[0].contains("\"name\":\"Heroes\""))

        mock.nextGroupsJoinJson = #"""
        {"group_id":"g1","user_id":"u2","role":"member","joined_at":"2026-05-12T00:00:00Z"}
        """#
        let m = try await client.groups.join(id: "g1")
        XCTAssertEqual(m.role, "member")
        XCTAssertEqual(mock.groupsJoinCalls, ["g1"])
    }

    func testGroupsUpdateAndMembersAndDelete() async throws {
        mock.nextGroupsUpdateJson = #"""
        {"id":"g1","name":"Heroes United","description":null,"avatar_url":null,"created_by":"u1","member_count":1,"created_at":"2026-05-12T00:00:00Z","updated_at":"2026-05-12T01:00:00Z","metadata":{}}
        """#
        _ = try await client.groups.update(id: "g1", patch: GroupUpdate(name: "Heroes United"))
        XCTAssertEqual(mock.groupsUpdateCalls[0].0, "g1")
        XCTAssertTrue(mock.groupsUpdateCalls[0].1.contains("\"name\":\"Heroes United\""))

        mock.nextGroupsGetMembersJson = "[]"
        let members = try await client.groups.members(id: "g1")
        XCTAssertEqual(members.count, 0)

        try await client.groups.delete(id: "g1")
        XCTAssertEqual(mock.groupsDeleteCalls, ["g1"])

        try await client.groups.leave(id: "g1")
        XCTAssertEqual(mock.groupsLeaveCalls, ["g1"])

        mock.nextGroupsInviteJson = #"""
        {"group_id":"g1","user_id":"u9","role":"invited","joined_at":"2026-05-12T00:00:00Z"}
        """#
        let invited = try await client.groups.invite(id: "g1", userId: "u9")
        XCTAssertEqual(invited.userId, "u9")
    }

    func testMessagingConversationsAndSend() async throws {
        mock.nextMessagingGetConversationsJson = "[]"
        let convos = try await client.messaging.conversations()
        XCTAssertEqual(convos.count, 0)

        mock.nextMessagingSendMessageJson = #"""
        {"id":"m1","conversation_id":"c1","sender_id":"u1","body":"hi","metadata":{},"created_at":"2026-05-12T00:00:00Z"}
        """#
        let m = try await client.messaging.sendMessage(SendMessageRequest(toUserId: "u2", body: "hi"))
        XCTAssertEqual(m.body, "hi")
        XCTAssertTrue(mock.messagingSendMessageCalls[0].contains("\"body\":\"hi\""))
        XCTAssertTrue(mock.messagingSendMessageCalls[0].contains("\"to_user_id\":\"u2\""))
    }

    func testModerationReportUser() async throws {
        mock.nextModerationReportUserJson = #"""
        {"id":"r1","reporter_id":"u1","target_type":"user","target_id":"u9","reason":"spam","status":"pending","notes":null,"created_at":"2026-05-12T00:00:00Z","resolved_at":null}
        """#
        let r = try await client.moderation.reportUser(ReportRequest(targetId: "u9", reason: "spam"))
        XCTAssertEqual(r.status, "pending")
        XCTAssertEqual(r.reason, "spam")
        XCTAssertTrue(mock.moderationReportUserCalls[0].contains("\"target_id\":\"u9\""))
    }

    func testModerationReportContentAndStatus() async throws {
        mock.nextModerationReportContentJson = #"""
        {"id":"r2","reporter_id":"u1","target_type":"post","target_id":"p1","reason":"nsfw","status":"pending","notes":"flag","created_at":"2026-05-12T00:00:00Z","resolved_at":null}
        """#
        _ = try await client.moderation.reportContent(ReportRequest(targetId: "p1", reason: "nsfw", notes: "flag"))
        XCTAssertTrue(mock.moderationReportContentCalls[0].contains("\"notes\":\"flag\""))

        mock.nextModerationGetReportStatusJson = #"""
        {"id":"r2","reporter_id":"u1","target_type":"post","target_id":"p1","reason":"nsfw","status":"resolved","notes":null,"created_at":"2026-05-12T00:00:00Z","resolved_at":"2026-05-12T03:00:00Z"}
        """#
        let st = try await client.moderation.reportStatus(id: "r2")
        XCTAssertEqual(st.status, "resolved")
        XCTAssertNotNil(st.resolvedAt)
    }

    func testReviewsCRUD() async throws {
        mock.nextReviewsListJson = "[]"
        let list = try await client.reviews.list(targetType: "product", targetId: "p1")
        XCTAssertEqual(list.count, 0)
        XCTAssertEqual(mock.reviewsListCalls[0].0, "product")

        mock.nextReviewsCreateJson = #"""
        {"id":"rv1","author_id":"u1","target_type":"product","target_id":"p1","rating":4.5,"title":"Good","body":"liked it","created_at":"2026-05-12T00:00:00Z","updated_at":"2026-05-12T00:00:00Z"}
        """#
        let r = try await client.reviews.create(ReviewCreate(targetType: "product", targetId: "p1", rating: 4.5, title: "Good"))
        XCTAssertEqual(r.rating, 4.5)

        mock.nextReviewsUpdateJson = #"""
        {"id":"rv1","author_id":"u1","target_type":"product","target_id":"p1","rating":5.0,"title":"Great","body":"loved it","created_at":"2026-05-12T00:00:00Z","updated_at":"2026-05-12T01:00:00Z"}
        """#
        _ = try await client.reviews.update(id: "rv1", patch: ReviewUpdate(rating: 5.0, title: "Great"))

        try await client.reviews.delete(id: "rv1")
        XCTAssertEqual(mock.reviewsDeleteCalls, ["rv1"])
    }

    func testRolesAndPermissions() async throws {
        mock.nextRolesGetMyRolesJson = #"""
        [{"id":"r1","key":"admin","name":"Admin","permissions":["users.read","users.write"]}]
        """#
        let roles = try await client.roles.myRoles()
        XCTAssertEqual(roles.count, 1)
        XCTAssertEqual(roles[0].permissions.count, 2)

        mock.nextRolesHasPermission = true
        let ok = try await client.roles.hasPermission("users.read")
        XCTAssertTrue(ok)
        XCTAssertEqual(mock.rolesHasPermissionCalls, ["users.read"])
    }

    func testReferralsFlow() async throws {
        mock.nextReferralsGetReferralCodeJson = #"""
        {"id":"rc1","code":"FRIEND10","owner_id":"u1","uses_count":2,"max_uses":10,"expires_at":null,"created_at":"2026-05-01T00:00:00Z"}
        """#
        let rc = try await client.referrals.referralCode()
        XCTAssertEqual(rc.code, "FRIEND10")

        mock.nextReferralsClaimReferralJson = #"""
        {"id":"clm1","code_id":"rc1","referrer_id":"u1","referee_id":"u2","reward":{"xp":50},"claimed_at":"2026-05-12T00:00:00Z"}
        """#
        let claim = try await client.referrals.claimReferral(code: "FRIEND10")
        XCTAssertEqual(claim.refereeId, "u2")
        XCTAssertEqual(mock.referralsClaimReferralCalls, ["FRIEND10"])

        mock.nextReferralsCreateJson = #"""
        {"id":"rc2","code":"NEWCODE","owner_id":"u1","uses_count":0,"max_uses":5,"expires_at":null,"created_at":"2026-05-12T00:00:00Z"}
        """#
        let created = try await client.referrals.create(code: "NEWCODE", maxUses: 5)
        XCTAssertEqual(created.code, "NEWCODE")
        XCTAssertEqual(mock.referralsCreateCalls[0].0, "NEWCODE")
        XCTAssertEqual(mock.referralsCreateCalls[0].1, 5)
    }

    // MARK: Lifecycle + push extensions

    func testPushUnregisterForwards() async throws {
        try await client.push.unregister(token: "tok-1")
        XCTAssertEqual(mock.pushUnregisterCalls, ["tok-1"])
    }

    func testPushUnsubscribeForwards() async throws {
        try await client.push.unsubscribe(topic: "news")
        XCTAssertEqual(mock.pushUnsubscribeCalls, ["news"])
    }

    func testPushGetTokensDecodes() async throws {
        mock.nextPushGetTokensJson = #"""
        [{"id":"pt_1","token":"abc","platform":"apns","bundle_id":"com.amba.test","created_at":"2026-05-01T12:00:00Z"}]
        """#
        let tokens = try await client.push.getTokens()
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].id, "pt_1")
        XCTAssertEqual(tokens[0].platform, "apns")
        XCTAssertEqual(tokens[0].bundleId, "com.amba.test")
    }

    func testCatalogList() async throws {
        mock.nextCatalogListJson = #"""
        [{"id":"c1","sku":"sword","name":"Sword","description":"a sword","price_cents":499,"currency":"USD","metadata":{}}]
        """#
        let items = try await client.catalog.list()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].sku, "sword")
        XCTAssertEqual(items[0].priceCents, 499)
    }

    func testContentTodayCanBeNull() async throws {
        mock.nextContentGetTodayJson = "null"
        let item = try await client.content.today(channel: "daily_quote")
        XCTAssertNil(item)
        XCTAssertEqual(mock.contentGetTodayCalls, ["daily_quote"])
    }

    /// `today()` with no channel forwards `nil` to the core, which lets the
    /// server fall back to the `"default"` channel (parity with the TS SDKs).
    func testContentTodayDefaultChannel() async throws {
        mock.nextContentGetTodayJson = "null"
        _ = try await client.content.today()
        XCTAssertEqual(mock.contentGetTodayCalls.count, 1)
        XCTAssertNil(mock.contentGetTodayCalls[0])
    }

    /// `library()` with no args forwards all-nil to the core. The new `limit`
    /// parameter is optional and threads through unchanged.
    func testContentLibraryDefaults() async throws {
        mock.nextContentGetLibraryJson = "[]"
        _ = try await client.content.library()
        XCTAssertEqual(mock.contentGetLibraryCalls.count, 1)
        XCTAssertNil(mock.contentGetLibraryCalls[0].0)
        XCTAssertNil(mock.contentGetLibraryCalls[0].1)
        XCTAssertNil(mock.contentGetLibraryCalls[0].2)
    }

    func testContentTodayWithValue() async throws {
        mock.nextContentGetTodayJson = #"""
        {"id":"ci1","channel":"daily_quote","title":"Hello","body":"World","data":{},"published_at":"2026-05-12T00:00:00Z","user_state":{}}
        """#
        let item = try await client.content.today(channel: "daily_quote")
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.title, "Hello")
    }

    func testContentLibraryAndItem() async throws {
        mock.nextContentGetLibraryJson = "[]"
        let lib = try await client.content.library(channel: "daily_quote", limit: 25, cursor: "abc")
        XCTAssertEqual(lib.count, 0)
        XCTAssertEqual(mock.contentGetLibraryCalls[0].0, "daily_quote")
        XCTAssertEqual(mock.contentGetLibraryCalls[0].1, 25)
        XCTAssertEqual(mock.contentGetLibraryCalls[0].2, "abc")

        mock.nextContentGetItemJson = #"""
        {"id":"ci1","channel":"daily_quote","title":null,"body":null,"data":{},"published_at":"2026-05-12T00:00:00Z","user_state":{}}
        """#
        let item = try await client.content.item(id: "ci1")
        XCTAssertEqual(item.id, "ci1")
        XCTAssertEqual(mock.contentGetItemCalls, ["ci1"])
    }

    func testContentUpdateAndCreate() async throws {
        mock.nextContentUpdateItemJson = #"""
        {"id":"ci1","channel":"daily","title":null,"body":null,"data":{},"published_at":"2026-05-12T00:00:00Z","user_state":{"read":true}}
        """#
        _ = try await client.content.updateItem(id: "ci1", state: ["read": true])
        XCTAssertEqual(mock.contentUpdateItemCalls[0].0, "ci1")
        XCTAssertTrue(mock.contentUpdateItemCalls[0].1.contains("\"read\":true"))

        mock.nextContentCreateItemJson = #"""
        {"id":"ci2","channel":"daily","title":"New","body":null,"data":{"x":1},"published_at":"2026-05-12T00:00:00Z","user_state":{}}
        """#
        _ = try await client.content.createItem(channel: "daily", item: ["title": "New", "data": ["x": 1]])
        XCTAssertEqual(mock.contentCreateItemCalls[0].0, "daily")
    }

    func testDeepLinksGetAndCreate() async throws {
        mock.nextDeepLinksGetJson = #"""
        {"id":"dl1","url":"https://amba.host/dl/abc","short_code":"abc","target_path":"/onboarding","metadata":{},"created_at":"2026-05-12T00:00:00Z"}
        """#
        let dl = try await client.deepLinks.get(shortCode: "abc")
        XCTAssertEqual(dl.shortCode, "abc")
        XCTAssertEqual(mock.deepLinksGetCalls, ["abc"])

        mock.nextDeepLinksCreateJson = #"""
        {"id":"dl2","url":"https://amba.host/dl/xyz","short_code":"xyz","target_path":"/welcome","metadata":{},"created_at":"2026-05-12T00:00:00Z"}
        """#
        let made = try await client.deepLinks.create(DeepLinkCreate(targetPath: "/welcome"))
        XCTAssertEqual(made.shortCode, "xyz")
        // Swift's JSONEncoder escapes forward slashes by default — accept either form.
        let sent = mock.deepLinksCreateCalls[0]
        XCTAssertTrue(sent.contains("\"target_path\""), "missing target_path in: \(sent)")
        XCTAssertTrue(sent.contains("welcome"), "missing 'welcome' in: \(sent)")
    }

    func testOnboardingFlow() async throws {
        mock.nextOnboardingGetStatusJson = #"""
        {"current_step":"profile","completed_steps":[],"remaining_steps":["profile","verify"],"completed":false,"completed_at":null}
        """#
        let s = try await client.onboarding.status()
        XCTAssertEqual(s.currentStep, "profile")
        XCTAssertFalse(s.completed)

        mock.nextOnboardingNextStepJson = #"""
        {"current_step":"verify","completed_steps":["profile"],"remaining_steps":["verify"],"completed":false,"completed_at":null}
        """#
        _ = try await client.onboarding.nextStep(payload: ["answer": "yes"])
        XCTAssertTrue(mock.onboardingNextStepCalls[0].contains("\"answer\":\"yes\""))

        mock.nextOnboardingSkipStepJson = mock.nextOnboardingGetStatusJson
        _ = try await client.onboarding.skipStep()
        XCTAssertEqual(mock.onboardingSkipStepCount, 1)

        mock.nextOnboardingCompleteJson = #"""
        {"current_step":null,"completed_steps":["profile","verify"],"remaining_steps":[],"completed":true,"completed_at":"2026-05-12T00:00:00Z"}
        """#
        let done = try await client.onboarding.complete()
        XCTAssertTrue(done.completed)
        XCTAssertEqual(mock.onboardingCompleteCount, 1)
    }
}
