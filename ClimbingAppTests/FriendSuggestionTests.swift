import XCTest
@testable import ClimbingApp

@MainActor private final class SuggestionTestService: FriendSuggestionServing {
    var rows: [FriendSuggestion] = []
    var failure: String?
    var enabled = true
    var adds: [UUID] = []
    var offsets: [Int] = []
    var waiting: CheckedContinuation<[FriendSuggestion], Never>?
    var suspendFetch = false
    func fetch(limit:Int,offset:Int) async throws -> [FriendSuggestion] {
        offsets.append(offset)
        if failure == "fetch" { throw SocialError.server }
        if suspendFetch { return await withCheckedContinuation { waiting=$0 } }
        return Array(rows.dropFirst(offset).prefix(limit))
    }
    func dismiss(_ id:UUID) async throws {
        if failure == "dismiss" { throw SocialError.server }
        rows.removeAll { $0.id == id }
    }
    func add(_ id:UUID) async throws {
        if failure == "add" { throw SocialError.server }
        adds.append(id);rows.removeAll { $0.id == id }
    }
    func discovery() async throws -> Bool {
        if failure == "discovery" { throw SocialError.server }; return enabled
    }
    func setDiscovery(_ enabled:Bool) async throws {
        if failure == "setting" { throw SocialError.server };self.enabled=enabled
    }
}

@MainActor final class FriendSuggestionTests: XCTestCase {
    private let owner=UUID(uuidString:"00000000-0000-0000-0000-000000000001")!
    private func row(_ number:Int,count:Int=2) -> FriendSuggestion {
        .init(id:UUID(uuidString:String(format:"00000000-0000-0000-0000-%012d",number))!,display_name:"Climber \(number)",avatar_base64:nil,mutual_count:count,mutual_names:["Sam","Jo"])
    }
    func testDecodeBoundedMutualSummaryAndOptionalAvatar() throws {
        let json=Data(#"{"id":"00000000-0000-0000-0000-000000000002","display_name":"Alex","mutual_count":4,"mutual_names":["Sam","Jo","Lee","Hidden"]}"#.utf8)
        let decoded=try JSONDecoder().decode(FriendSuggestion.self,from:json)
        XCTAssertNil(decoded.avatar_base64)
        XCTAssertEqual(decoded.mutualSummary,"4 mutual friends · Sam, Jo, Lee")
        XCTAssertEqual(FriendSuggestion(id:decoded.id,display_name:"Alex",avatar_base64:nil,mutual_count:1,mutual_names:[]).mutualSummary,"1 mutual friend")
    }
    func testRankingDeduplicatesAndExcludesCallerFriendsPendingBlockedAndDismissed() {
        let excluded=Set([owner,row(2).id,row(3).id,row(4).id,row(5).id])
        let rows=[row(7),row(6),row(8,count:5),row(6),row(9,count:0)]+(1...5).map { row($0) }
        XCTAssertEqual(FriendSuggestion.ranked(rows,excluding:excluded).map(\.id),[row(8).id,row(6).id,row(7).id])
    }
    func testAddIsConfirmedPendingAndDismissPersistsOnReload() async {
        let service=SuggestionTestService();service.rows=[row(2),row(3)]
        let state=FriendSuggestions();await state.load(service,owner:owner)
        await state.act(row(2).id,dismiss:false,service:service)
        XCTAssertTrue(state.sent.contains(row(2).id));XCTAssertEqual(service.adds,[row(2).id])
        await state.act(row(2).id,dismiss:false,service:service)
        XCTAssertEqual(service.adds.count,1)
        await state.act(row(3).id,dismiss:true,service:service)
        XCTAssertFalse(state.items.contains { $0.id == row(3).id })
        await state.load(service,owner:owner)
        XCTAssertTrue(state.items.isEmpty)
    }
    func testFailedAddAndDismissKeepRowAndOfferCorrectRetry() async {
        let service=SuggestionTestService();service.rows=[row(2)]
        let state=FriendSuggestions();await state.load(service,owner:owner)
        service.failure="add";await state.act(row(2).id,dismiss:false,service:service)
        XCTAssertTrue(state.sent.isEmpty);XCTAssertNotNil(state.rowErrors[row(2).id]);XCTAssertTrue(state.working.isEmpty)
        service.failure="dismiss";await state.act(row(2).id,dismiss:true,service:service)
        XCTAssertEqual(state.items.count,1);XCTAssertTrue(state.retryDismiss.contains(row(2).id))
        service.failure=nil;await state.act(row(2).id,dismiss:true,service:service)
        XCTAssertTrue(state.items.isEmpty)
    }
    func testFetchFailureClearsStaleRowsAndEmptyRetryHidesSection() async {
        let service=SuggestionTestService();service.rows=[row(2)]
        let state=FriendSuggestions();await state.load(service,owner:owner)
        service.failure="fetch";await state.load(service,owner:owner)
        XCTAssertTrue(state.items.isEmpty);XCTAssertNotNil(state.errorMessage)
        service.failure=nil;service.rows=[];await state.load(service,owner:owner)
        XCTAssertTrue(state.items.isEmpty);XCTAssertNil(state.errorMessage);XCTAssertFalse(state.hasMore)
    }
    func testPaginationAfterDismissDoesNotSkipNextCandidate() async {
        let service=SuggestionTestService();service.rows=(2...23).map { row($0) }
        let state=FriendSuggestions();await state.load(service,owner:owner)
        XCTAssertTrue(state.hasMore)
        await state.act(row(2).id,dismiss:true,service:service)
        await state.load(service,owner:owner,more:true)
        XCTAssertEqual(service.offsets,[0,9])
        XCTAssertTrue(state.items.contains { $0.id == row(12).id })
        XCTAssertEqual(Set(state.items.map(\.id)).count,state.items.count)
    }
    func testDiscoveryOptOutAndFailureNeverClaimUnsavedSetting() async {
        let service=SuggestionTestService();let state=FriendSuggestions()
        await state.loadDiscovery(service);XCTAssertEqual(state.discoveryEnabled,true)
        service.failure="setting";await state.setDiscovery(false,service:service)
        XCTAssertEqual(state.discoveryEnabled,true);XCTAssertNotNil(state.settingError)
        service.failure=nil;await state.setDiscovery(false,service:service)
        XCTAssertEqual(state.discoveryEnabled,false);XCTAssertFalse(service.enabled)
        service.failure="discovery";await state.loadDiscovery(service)
        XCTAssertNil(state.discoveryEnabled);XCTAssertNotNil(state.settingError)
    }
    func testResetDiscardsInFlightResponseAndDiscoveryAcrossAccounts() async {
        let service=SuggestionTestService();service.suspendFetch=true
        let state=FriendSuggestions()
        await state.loadDiscovery(service)
        let task=Task { await state.load(service,owner:owner) }
        while service.waiting == nil { await Task.yield() }
        state.reset();service.waiting?.resume(returning:[row(2)])
        await task.value
        XCTAssertTrue(state.items.isEmpty);XCTAssertNil(state.discoveryEnabled);XCTAssertFalse(state.loading)
    }
    func testSignedOutServiceDoesNotFetchOrInventSuggestions() async {
        let config=SupabaseConfiguration(projectURL:URL(string:"https://example.supabase.co")!,publishableKey:"sb_publishable_test")
        let store=SocialStore(configuration:config)
        let service=SocialSuggestionService(store:store,auth:AccountSession(vault:GuestAccountVault()))
        do { _ = try await service.fetch(limit:10,offset:0);XCTFail("Must require sign-in before making a network request") }
        catch { XCTAssertEqual(error.localizedDescription,SocialError.signIn.localizedDescription) }
        XCTAssertTrue(store.suggestions.items.isEmpty)
    }
}
