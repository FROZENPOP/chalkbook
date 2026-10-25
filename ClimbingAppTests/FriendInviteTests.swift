import XCTest
@testable import ClimbingApp

final class FriendInviteTests:XCTestCase {
    func testStableAppAndWebLinksRoundTripWithoutAutoAccepting() {
        let id=UUID(),base=URL(string:"https://example.com/climb")!
        XCTAssertEqual(FriendInvite.parse(FriendInvite.appURL(id:id),webBase:nil),id)
        let web=FriendInvite.shareURL(id:id,username:"climb_buddy",webBase:base)
        XCTAssertEqual(FriendInvite.parse(web,webBase:base),id)
        XCTAssertNil(FriendInvite.parse(web,webBase:URL(string:"https://other.example")!))
        XCTAssertNil(FriendInvite.parse(URL(string:"climblog://friend/not-a-uuid")!,webBase:nil))
        XCTAssertNil(FriendInvite.parse(URL(string:"climblog://friend/\(id)/extra")!,webBase:nil))
    }
    func testInsecureWebBaseFallsBackToInstalledAppLink() {
        let id=UUID()
        XCTAssertEqual(FriendInvite.shareURL(id:id,username:"test",webBase:URL(string:"http://example.com")),FriendInvite.appURL(id:id))
    }
}
