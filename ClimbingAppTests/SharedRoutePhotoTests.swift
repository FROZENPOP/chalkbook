import XCTest
import UIKit
import ImageIO
@testable import ClimbingApp

final class SharedRoutePhotoTests: XCTestCase {
    private func source() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size:CGSize(width:120,height:80))
        let photo = renderer.image { context in
            UIColor.lightGray.setFill();context.fill(CGRect(x:0,y:0,width:120,height:80))
            UIColor.yellow.setFill();context.fill(CGRect(x:20,y:20,width:30,height:30))
        }
        let image = try XCTUnwrap(photo.cgImage), bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes,"public.jpeg" as CFString,1,nil))
        CGImageDestinationAddImage(destination,image,[kCGImagePropertyGPSDictionary:[kCGImagePropertyGPSLatitude:37.1,kCGImagePropertyGPSLongitude:121.2],kCGImagePropertyExifDictionary:[kCGImagePropertyExifUserComment:"Private notebook and Health values"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination));return bytes as Data
    }
    func testExplicitPairHasBothVersionsAndStripsMetadata() async throws {
        let data = try source(), original = data
        let pair = try await SharedRoutePhoto.prepare(data:data,settings:.init(x:0.25,y:0.4,tolerance:0.35))
        XCTAssertNotNil(pair.highlighted_base64)
        XCTAssertNotEqual(pair.original_base64,pair.highlighted_base64)
        XCTAssertEqual(data,original)
        XCTAssertEqual(Set(pair.rpcValues.keys),["id","original_base64","highlighted_base64"])
        for value in [pair.original_base64,pair.highlighted_base64!] {
            let bytes = try XCTUnwrap(Data(base64Encoded:value))
            XCTAssertLessThanOrEqual(bytes.count,SharedRoutePhoto.maximumBytes)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData,nil))
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any])
            XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString:Any]
            XCTAssertNil(exif?[kCGImagePropertyExifUserComment])
            XCTAssertNil(exif?[kCGImagePropertyExifDateTimeOriginal])
        }
        XCTAssertEqual(try JSONDecoder().decode(SharedRoutePhoto.self,from:JSONEncoder().encode(pair)),pair)
    }
    func testNoHighlightSharesOnlyOriginalAndInvalidInputsAreRejected() async throws {
        let pair = try await SharedRoutePhoto.prepare(data:source(),settings:nil)
        let disabled = try await SharedRoutePhoto.prepare(data:source(),settings:.init(selections:[.init(x:0.25,y:0.4)],isEnabled:false))
        XCTAssertNotNil(disabled.highlighted_base64) // Review can include the saved alternative without enabling it locally.
        XCTAssertNil(pair.highlighted_base64)
        XCTAssertNoThrow(try pair.validated())
        XCTAssertThrowsError(try SharedRoutePhoto(id:UUID(),original_base64:"not an image").validated())
        XCTAssertThrowsError(try SharedRoutePhoto(id:UUID(),original_base64:String(repeating:"A",count:174765)).validated())
    }
    @MainActor func testSummaryOnlyDraftDoesNotSelectOrUploadRoutePhotos() throws {
        let session = ClimbingSession(notes:"Private notes")
        let climb = ClimbEntry();climb.media=[RouteMedia(kind:.photo,filename:"private.jpg",contentType:"public.jpeg",data:try source())]
        session.climbs=[climb]
        let draft = SharedSession(session:session,owner:UUID())
        XCTAssertNil(draft.route_photo_count)
        XCTAssertNil(draft.rpcValues["photos"])
        XCTAssertFalse(String(describing:draft.rpcValues).contains("Private notes"))
    }

    func testStorageFullOutcomesExplainPhotosStayInTheLog() {
        let trimmed = SocialStore.photoNotice(Data(#""trimmed""#.utf8))
        let noSpace = SocialStore.photoNotice(Data(#""no_space""#.utf8))
        XCTAssertTrue(trimmed?.contains("removed from your older Friends posts") == true)
        XCTAssertEqual(noSpace,"Friends photo storage is full, so this post was shared without photos. Your photos are still saved in your log on this iPhone.")
        XCTAssertFalse(noSpace?.localizedCaseInsensitiveContains("beta") ?? true)
        for notice in [trimmed, noSpace] { XCTAssertTrue(notice?.contains("still saved in your log") == true) }
        XCTAssertNil(SocialStore.photoNotice(Data(#""saved""#.utf8)))
        XCTAssertNil(SocialStore.photoNotice(Data())) // older servers return nothing
    }

    @MainActor func testSavedPostReportsSuccessWhenTheRefreshFails() async throws {
        let account = ClimberAccount(provider:.google,subject:"publish-test-account",name:"Test",email:nil)
        let owner = UUID(), sessions = FriendsSessionVault(service:"com.frozenpop.ClimbingApp.tests.\(UUID().uuidString)")
        let directory = URL.temporaryDirectory.appending(path:"PublishTests-\(UUID().uuidString)")
        defer { sessions.clear(); try? FileManager.default.removeItem(at:directory) }
        let refresh = "Your post was saved, but Friends couldn’t refresh. Check your connection and pull to refresh."
        let noSpace = try XCTUnwrap(SocialStore.photoNotice(Data(#""no_space""#.utf8)))
        for (outcome,expected) in [("saved",refresh),("no_space","\(noSpace) \(refresh)")] {
            var paths: [String] = []
            PublishURLProtocol.handler = { request in
                let path = request.url!.path; paths.append(path)
                if path.hasPrefix("/auth/") { return (200,Data(#"{"access_token":"t","expires_in":3600,"user":{"id":"\#(owner)"}}"#.utf8)) }
                if path == "/rest/v1/rpc/save_shared_session_with_photos" { return (200,Data("\"\(outcome)\"".utf8)) }
                return (500,Data()) // the refresh after saving fails
            }
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [PublishURLProtocol.self]
            let social = SocialStore(configuration:.init(projectURL:URL(string:"https://test.invalid")!,publishableKey:"test"),network:URLSession(configuration:config),
                accountKey:account.storageKey,removals:RemovalOutbox(accountKey:account.storageKey,directory:directory),sessions:sessions,identityToken:{ _ in "id-token" })
            let auth = AccountSession(vault:PublishAccountVault(value:account),googleSignOut:{},friendsSessions:sessions)
            let published = await social.publish(auth,entry:SharedSession(session:ClimbingSession(),owner:owner),photos:[])
            XCTAssertTrue(published,"\(outcome): the save succeeded, so the post must not be reported as failed")
            XCTAssertTrue(paths.contains("/rest/v1/friendships"),"\(outcome): the refresh was attempted")
            XCTAssertEqual(social.photoNotice,expected,"\(outcome): the Shared alert explains the failed refresh")
            XCTAssertNil(social.errorMessage,"\(outcome): nothing claims the save failed")
        }
    }
}

private struct PublishAccountVault: AccountVault {
    let value: ClimberAccount
    func load() throws -> ClimberAccount? { value }
    func save(_ account: ClimberAccount) throws {}
    func clear() throws {}
}

private final class PublishURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int,Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (code,data) = Self.handler!(request)
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
