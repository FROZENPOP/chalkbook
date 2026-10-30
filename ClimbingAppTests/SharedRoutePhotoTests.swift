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
}
