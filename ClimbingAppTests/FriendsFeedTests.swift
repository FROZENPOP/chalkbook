import XCTest
@testable import ClimbingApp

@MainActor private final class FeedTestReader: FriendsFeedReading {
    var rows: [SharedSession] = []
    var profiles: [SocialProfile] = []
    var calls: [FriendsFeedCursor?] = []
    var limits: [Int] = []
    var failNext = false
    var suspendNext = false
    var waiting: CheckedContinuation<FriendsFeedPage, Never>?
    var override: [SharedSession]?
    func page(after:FriendsFeedCursor?,limit:Int) async throws -> FriendsFeedPage {
        calls.append(after);limits.append(limit)
        if failNext { failNext=false;throw SocialError.server }
        if suspendNext { suspendNext=false;return await withCheckedContinuation { waiting=$0 } }
        if let override { self.override=nil;return .init(entries:override,profiles:profiles) }
        let sorted=rows.sorted { $0.session_day == $1.session_day ? $0.id.uuidString > $1.id.uuidString : $0.session_day > $1.session_day }
        return .init(entries:Array(sorted.filter { entry in
            guard let after else { return true }
            return entry.session_day < after.day || (entry.session_day == after.day && entry.id.uuidString < after.id.uuidString)
        }.prefix(limit)),profiles:profiles)
    }
}

@MainActor final class FriendsFeedTests: XCTestCase {
    private let owner=UUID(uuidString:"00000000-0000-0000-0000-000000000002")!
    private func row(_ number:Int,day:String="2026-10-30") -> SharedSession {
        var entry=SharedSession(session:ClimbingSession(),owner:owner)
        entry.id=UUID(uuidString:String(format:"00000000-0000-0000-0000-%012d",number))!
        entry.session_day=day;entry.caption="Recap \(number)"
        return entry
    }
    func testQueryUsesDateAndUUIDCursorBoundedLimitAndNoOffset() throws {
        let first=try XCTUnwrap(URLComponents(string:FriendsFeedCursor.path(viewer:owner,after:nil)))
        let values=Dictionary(first.queryItems!.map { ($0.name,$0.value!) },uniquingKeysWith:{ _,new in new })
        XCTAssertEqual(first.path,"/rest/v1/shared_sessions");XCTAssertEqual(values["order"],"session_day.desc,id.desc")
        XCTAssertEqual(values["limit"],"20");XCTAssertEqual(values["owner_id"],"neq.\(owner.uuidString)")
        XCTAssertNil(values["or"]);XCTAssertNil(values["offset"])
        let cursor=FriendsFeedCursor(day:"2026-10-30",id:row(10).id)
        let next=try XCTUnwrap(URLComponents(string:FriendsFeedCursor.path(viewer:owner,after:cursor,limit:999)))
        XCTAssertEqual(next.queryItems?.first { $0.name == "or" }?.value,"(session_day.lt.2026-10-30,and(session_day.eq.2026-10-30,id.lt.\(row(10).id.uuidString)))")
        XCTAssertEqual(next.queryItems?.first { $0.name == "limit" }?.value,"20")
        XCTAssertThrowsError(try FriendsFeedCursor.path(viewer:owner,after:.init(day:"2026-10-30),id.gt.0",id:owner)))
    }
    func testFirstAndNextPageUseRawLastCursorAndMergeReferencedProfiles() async {
        let reader=FeedTestReader();reader.rows=(1...40).map { row($0) }
        let stranger=UUID()
        reader.profiles=[.init(id:owner,username:"buddy",display_name:"Buddy",is_private:true),.init(id:stranger,username:"unused",display_name:"Unused",is_private:false)]
        let feed=FriendsFeed();await feed.refresh(reader)
        XCTAssertEqual(feed.entries.count,20);XCTAssertTrue(feed.hasMore);XCTAssertTrue(feed.hasLoaded)
        XCTAssertEqual(feed.cursor,.init(day:"2026-10-30",id:row(21).id))
        XCTAssertEqual(feed.profiles.map(\.id),[owner]);XCTAssertNil(reader.calls[0])
        await feed.loadNext(reader)
        XCTAssertEqual(reader.calls[1],.init(day:"2026-10-30",id:row(21).id))
        XCTAssertEqual(feed.entries.map(\.id),(1...40).reversed().map { row($0).id })
        XCTAssertEqual(reader.limits,[20,20]);XCTAssertEqual(feed.cursor?.id,row(1).id)
    }
    func testDateOrderingAndTieBoundaryAcrossDifferentDays() async {
        let reader=FeedTestReader();reader.rows=(1...22).map { row($0) }+[row(999,day:"2026-10-29"),row(1000,day:"2026-10-28")]
        let feed=FriendsFeed();await feed.refresh(reader)
        XCTAssertEqual(feed.cursor?.id,row(3).id)
        await feed.loadNext(reader)
        XCTAssertEqual(feed.entries.count,24)
        XCTAssertEqual(Array(feed.entries.suffix(4).map(\.id)),[row(2).id,row(1).id,row(999).id,row(1000).id])
        XCTAssertFalse(feed.hasMore)
    }
    func testInsertionAboveCursorDoesNotShiftOlderItemsAndRefreshFindsNewPost() async {
        let reader=FeedTestReader();reader.rows=(1...40).map { row($0) }
        let feed=FriendsFeed();await feed.refresh(reader)
        reader.rows.append(row(50))
        await feed.loadNext(reader)
        XCTAssertEqual(feed.entries.count,40);XCTAssertFalse(feed.entries.contains { $0.id == row(50).id })
        XCTAssertEqual(Set(feed.entries.map(\.id)),Set((1...40).map { row($0).id }))
        await feed.refresh(reader)
        XCTAssertEqual(feed.entries.count,20);XCTAssertEqual(feed.entries.first?.id,row(50).id);XCTAssertNil(reader.calls.last!)
    }
    func testOverlappingShiftedRowsDeduplicateAndKeepServerCursor() async {
        let reader=FeedTestReader();reader.rows=(21...40).map { row($0) }
        let feed=FriendsFeed();await feed.refresh(reader)
        var edited=row(21);edited.caption="Updated recap"
        reader.override=[edited]+(2...20).reversed().map { row($0) }
        await feed.loadNext(reader)
        XCTAssertEqual(feed.entries.count,39);XCTAssertEqual(feed.entries.first { $0.id == edited.id }?.caption,"Updated recap")
        XCTAssertEqual(feed.cursor?.id,row(2).id)
        reader.override=[row(1)];await feed.loadNext(reader)
        XCTAssertEqual(feed.entries.count,40);XCTAssertFalse(feed.hasMore)
    }
    func testEmptySingleAndExactPageEndDetection() async {
        for count in [0,3,20] {
            let reader=FeedTestReader();if count>0 { reader.rows=(1...count).map { row($0) } }
            let feed=FriendsFeed();await feed.refresh(reader)
            XCTAssertEqual(feed.entries.count,count);XCTAssertEqual(feed.hasMore,count==20)
            await feed.loadNext(reader);await feed.loadNext(reader)
            XCTAssertFalse(feed.hasMore);XCTAssertEqual(reader.calls.count,count==20 ? 2 : 1)
        }
    }
    func testSecondPageErrorKeepsFirstPageAndAllowsRetryAtSameCursor() async {
        let reader=FeedTestReader();reader.rows=(1...23).map { row($0) }
        let feed=FriendsFeed();await feed.refresh(reader)
        let before=feed.entries.map(\.id),cursor=feed.cursor
        reader.failNext=true;await feed.loadNext(reader)
        XCTAssertEqual(feed.entries.map(\.id),before);XCTAssertEqual(feed.cursor,cursor)
        XCTAssertNotNil(feed.errorMessage);XCTAssertFalse(feed.loading);XCTAssertTrue(feed.hasMore)
        await feed.loadNext(reader)
        XCTAssertEqual(reader.calls[1],reader.calls[2]);XCTAssertEqual(feed.entries.count,23)
        XCTAssertNil(feed.errorMessage);XCTAssertFalse(feed.hasMore)
    }
    func testRefreshDropsRevokedRowsAndProfileCache() async {
        let reader=FeedTestReader();reader.rows=[row(2)]
        reader.profiles=[.init(id:owner,username:"buddy",display_name:"Buddy",is_private:true)]
        let feed=FriendsFeed();await feed.refresh(reader)
        reader.rows=[];reader.profiles=[] // Represents RLS after a removal, visibility change or block.
        await feed.refresh(reader)
        XCTAssertTrue(feed.entries.isEmpty);XCTAssertTrue(feed.profiles.isEmpty);XCTAssertNil(feed.cursor)
        XCTAssertFalse(feed.hasMore);XCTAssertNil(reader.calls.last!)
    }
    func testConcurrentDuplicateLoadIsIgnored() async {
        let reader=FeedTestReader();reader.suspendNext=true
        let feed=FriendsFeed();let pending=Task { await feed.loadNext(reader) }
        while reader.waiting == nil { await Task.yield() }
        await feed.loadNext(reader)
        XCTAssertEqual(reader.calls.count,1);XCTAssertTrue(feed.loading)
        reader.waiting?.resume(returning:.init(entries:[row(1)]));await pending.value
        XCTAssertEqual(feed.entries.count,1);XCTAssertFalse(feed.loading)
    }
    func testRefreshInvalidatesLatePageWithoutClearingNewLoadState() async {
        let reader=FeedTestReader();reader.suspendNext=true
        let feed=FriendsFeed();let old=Task { await feed.loadNext(reader) }
        while reader.waiting == nil { await Task.yield() }
        reader.rows=[row(99)];await feed.refresh(reader)
        reader.waiting?.resume(returning:.init(entries:[row(1)]));await old.value
        XCTAssertEqual(feed.entries.map(\.id),[row(99).id]);XCTAssertFalse(feed.loading)
    }
    func testLocalRemovalKeepsCursorAndDoesNotSkipOlderRows() async {
        let reader=FeedTestReader();reader.rows=(1...40).map { row($0) }
        let feed=FriendsFeed();await feed.refresh(reader)
        feed.remove { $0.id == row(21).id };reader.rows.removeAll { $0.id == row(21).id }
        XCTAssertEqual(feed.cursor?.id,row(21).id)
        await feed.loadNext(reader)
        XCTAssertEqual(feed.entries.count,39);XCTAssertTrue(feed.entries.contains { $0.id == row(20).id })
    }
}
