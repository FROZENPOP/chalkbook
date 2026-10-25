import XCTest
import ImageIO
@testable import ClimbingApp

final class SocialPhotoTests:XCTestCase {
    func testAvatarIsBoundedReencodedAndInvalidRemoteDataIsIgnored() throws {
        let bundle=Bundle(for:Self.self)
        let url=try XCTUnwrap(bundle.url(forResource:"route-photo",withExtension:"png") ?? bundle.url(forResource:"route-photo",withExtension:"png",subdirectory:"Fixtures"))
        let avatar=try SocialPhoto.prepare(Data(contentsOf:url))
        XCTAssertLessThanOrEqual(avatar.count,65536)
        let source=try XCTUnwrap(CGImageSourceCreateWithData(avatar as CFData,nil))
        let properties=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any])
        XCTAssertLessThanOrEqual(try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int),256)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertNil(SocialProfileDetails(id:UUID(),bio:"",avatar_base64:"not-image-data").photo)
    }
    func testInvalidAndOversizedAvatarImportsAreRejected() {
        XCTAssertThrowsError(try SocialPhoto.prepare(Data([1,2,3])))
        XCTAssertThrowsError(try SocialPhoto.prepare(Data(repeating:0,count:10_000_001)))
    }
}
