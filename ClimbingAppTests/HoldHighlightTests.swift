import XCTest
import UIKit
import ImageIO
import SwiftData
@testable import ClimbingApp

final class HoldHighlightTests: XCTestCase {
    private func image(width: Int = 30, height: Int = 20, pixel: (Int, Int) -> [UInt8]) -> CGImage {
        let bytes = (0..<height).flatMap { y in (0..<width).flatMap { x in pixel(x, y) } }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
    private func wall() -> CGImage {
        image { x, y in
            if y < 12 && (x < 10 || x >= 20) { return [255, 0, 0, 255] }
            if y < 12 { return [0, 0, 255, 255] }
            return [160, 160, 160, 255]
        }
    }
    func testSampleMedianRejectsChalkOutlier() throws {
        let photo = image { x, y in x == 5 && y == 5 ? [255,255,255,255] : [255,0,0,255] }
        let reference = try HoldHighlight.reference(in: HoldHighlight.pixels(photo), settings: .init(x: 0.17, y: 0.25, tolerance: 0.2))
        XCTAssertEqual(reference.hue, 0, accuracy: 0.001)
        XCTAssertEqual(reference.saturation, 1)
    }
    func testRedBlobsStayColoredWhileBlueAndWallDimAndOriginalUnchanged() throws {
        let original = wall(), before = try HoldHighlight.pixels(original).bytes
        let output = try HoldHighlight.render(original, settings: .init(x: 0.15, y: 0.2, tolerance: 0.1))
        let result = try HoldHighlight.pixels(output)
        for x in [4, 24] {
            XCTAssertEqual(result.bytes[(4 * 30 + x) * 4], 255)
            XCTAssertEqual(result.bytes[(4 * 30 + x) * 4 + 1], 0)
        }
        for (x, y) in [(14,4),(4,16)] {
            let offset = (y * 30 + x) * 4
            XCTAssertEqual(result.bytes[offset], result.bytes[offset + 1])
            XCTAssertEqual(result.bytes[offset], result.bytes[offset + 2])
            XCTAssertLessThan(result.bytes[offset], 60)
        }
        XCTAssertEqual(try HoldHighlight.pixels(original).bytes, before)
    }
    func testToleranceWidensMatchMonotonicallyAndHueWraps() throws {
        let reference = HoldHighlight.Color(red: 1, green: 0, blue: 0)
        let near = HoldHighlight.Color(red: 1, green: 0.3, blue: 0)
        XCTAssertLessThan(HoldHighlight.distance(near, from: reference), 0.2)
        XCTAssertLessThan(HoldHighlight.distance(.init(red: 1, green: 0, blue: 0.03), from: reference), 0.02)
        let strict = try HoldHighlight.pixels(HoldHighlight.render(wall(), settings: .init(x: 0.15,y: 0.2,tolerance: 0))).bytes
        let broad = try HoldHighlight.pixels(HoldHighlight.render(wall(), settings: .init(x: 0.15,y: 0.2,tolerance: 1))).bytes
        XCTAssertNotEqual(strict, broad)
        XCTAssertEqual(broad, try HoldHighlight.pixels(wall()).bytes)
    }
    func testNeutralReferenceUsesBrightnessAndRejectsSaturatedColor() {
        let white = HoldHighlight.Color(red: 1, green: 1, blue: 1)
        let black = HoldHighlight.Color(red: 0, green: 0, blue: 0)
        XCTAssertGreaterThan(HoldHighlight.distance(black, from: white), 0.7)
        XCTAssertGreaterThan(HoldHighlight.distance(.init(red: 1,green: 0,blue: 0), from: white), 0.5)
        XCTAssertLessThan(HoldHighlight.distance(.init(red: 0.95,green: 0.94,blue: 0.96), from: white), 0.1)
    }
    func testAspectFitIgnoresLetterboxingAndOutOfBounds() {
        let size = CGSize(width: 200, height: 100), container = CGSize(width: 300, height: 300)
        XCTAssertNil(HoldHighlight.normalizedPoint(CGPoint(x: 150,y: 40), imageSize: size, containerSize: container))
        XCTAssertNil(HoldHighlight.normalizedPoint(CGPoint(x: -1,y: 150), imageSize: size, containerSize: container))
        XCTAssertEqual(HoldHighlight.normalizedPoint(CGPoint(x: 150,y: 150), imageSize: size, containerSize: container), CGPoint(x: 0.5,y: 0.5))
        XCTAssertEqual(HoldHighlight.normalizedPoint(CGPoint(x: 300,y: 225), imageSize: size, containerSize: container), CGPoint(x: 1,y: 1))
        XCTAssertNil(HoldHighlight.normalizedPoint(.zero, imageSize: .zero, containerSize: container))
    }
    func testTinyLargeTransparentAndGrayscaleImages() throws {
        let tiny = image(width: 1,height: 1) { _,_ in [80,80,80,255] }
        XCTAssertEqual(try HoldHighlight.render(tiny,settings: .init(x: 1,y: 1,tolerance: 0)).width,1)
        let large = image(width: 4096,height: 2) { _,_ in [255,0,0,255] }
        let result = try HoldHighlight.render(large,settings: .init(x: 0.5,y: 0.5,tolerance: 0.2))
        XCTAssertEqual(result.width,1024);XCTAssertEqual(result.height,1)
        let gray = CGImage(width: 1,height: 1,bitsPerComponent: 8,bitsPerPixel: 8,bytesPerRow: 1,space: CGColorSpaceCreateDeviceGray(),bitmapInfo: [],provider: CGDataProvider(data: Data([180]) as CFData)!,decode: nil,shouldInterpolate: false,intent: .defaultIntent)!
        XCTAssertNoThrow(try HoldHighlight.render(gray,settings: .init(x: 0,y: 0,tolerance: 0.2)))
        XCTAssertThrowsError(try HoldHighlight.render(image(width:1,height:1) { _,_ in [0,0,0,0] },settings: .init(x:0,y:0,tolerance:0.2)))
        XCTAssertThrowsError(try HoldHighlight.render(tiny,settings: .init(x:-0.01,y:0,tolerance:0.2)))
        XCTAssertThrowsError(try HoldHighlight.load(Data()))
    }
    func testLargePhotoIsBoundedAndResetRegeneratesOriginal() async throws {
        let context = CGContext(data: nil, width: 4096, height: 3072, bitsPerComponent: 8, bytesPerRow: 4096 * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(UIColor.red.cgColor); context.fill(CGRect(x:0,y:0,width:4096,height:3072))
        let large = try XCTUnwrap(context.makeImage())
        let bounded = try HoldHighlight.render(large,settings:.init(x:0.5,y:0.5,tolerance:0.2))
        XCTAssertEqual(bounded.width,1024);XCTAssertEqual(bounded.height,768)
        let data = try XCTUnwrap(UIImage(cgImage:wall()).pngData()), unchanged = data
        _ = try await HoldHighlight.process(data:data,settings:.init(x:0.15,y:0.2,tolerance:0.1))
        let reset = try await HoldHighlight.process(data:data,settings:nil)
        XCTAssertEqual(try HoldHighlight.pixels(reset).bytes,try HoldHighlight.pixels(HoldHighlight.load(data)).bytes)
        XCTAssertEqual(data,unchanged)
    }
    func testAllEXIFOrientationsNormalizeBeforeSampling() throws {
        let original = image(width: 12,height: 8) { x, y in
            x < 6 ? (y < 4 ? [255,0,0,255] : [0,255,0,255]) : (y < 4 ? [0,0,255,255] : [255,255,255,255])
        }
        // Top-left displayed quadrant after each EXIF rotation/mirror.
        let expected: [[UInt8]] = [[255,0,0],[0,0,255],[255,255,255],[0,255,0],[255,0,0],[0,255,0],[255,255,255],[0,0,255]]
        for orientation in 1...8 {
            let data = NSMutableData()
            let destination = CGImageDestinationCreateWithData(data,"public.png" as CFString,1,nil)!
            CGImageDestinationAddImage(destination,original,[kCGImagePropertyOrientation:orientation] as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let normalized = try HoldHighlight.load(data as Data)
            XCTAssertEqual(normalized.width, orientation >= 5 ? 8 : 12)
            let pixels = try HoldHighlight.pixels(normalized)
            let i = (1 * pixels.width + 1) * 4
            XCTAssertEqual(Array(pixels.bytes[i..<i+3]),expected[orientation-1],"EXIF \(orientation)")
        }
    }
    @MainActor func testSettingsBackupRoundTripLegacyCompatibilityAndOriginalBytes() throws {
        let container = try Persistence.container(inMemory: true), store = ClimbingStore(context: container.mainContext)
        let photo = try XCTUnwrap(UIImage(cgImage:wall()).pngData())
        let media = RouteMedia(kind:.photo,filename:"wall.png",contentType:"public.png",data:photo)
        let strokes = [RouteStroke(color:"orange",points:[RoutePoint(x:0.2,y:0.4)])]
        let legacy = try RouteAnnotations.encode(strokes)
        XCTAssertNil(try RouteAnnotations.document(legacy).highlight)
        let settings = HoldHighlightSettings(x:0.15,y:0.2,tolerance:0.22)
        media.annotationJSON = try RouteAnnotations.encode(RouteAnnotationDocument(strokes:strokes,highlight:settings))
        let climb = ClimbEntry();climb.media=[media];container.mainContext.insert(climb);try container.mainContext.save()
        let encoded = try JSONEncoder().encode(ClimbingBackup(sessions:[],defaultScale:.vScale,climbs:[climb]))
        let backup = try JSONDecoder().decode(ClimbingBackup.self, from: encoded).validated()
        XCTAssertEqual(backup.version,5)
        XCTAssertTrue(store.restore(backup))
        let restored = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<ClimbEntry>()).first?.media.first)
        XCTAssertEqual(restored.data,photo)
        XCTAssertEqual(try RouteAnnotations.document(restored.annotationJSON).highlight,settings)
        XCTAssertEqual(try RouteAnnotations.decode(restored.annotationJSON),strokes)
        var reset = try RouteAnnotations.document(restored.annotationJSON);reset.highlight=nil
        XCTAssertNil(try RouteAnnotations.document(RouteAnnotations.encode(reset)).highlight)
        XCTAssertEqual(reset.strokes,strokes)
        var old = ClimbingBackup(sessions: [], defaultScale: .vScale);old.version=4
        XCTAssertNoThrow(try old.validated())
        XCTAssertThrowsError(try RouteAnnotations.encode(RouteAnnotationDocument(strokes:[],highlight:.init(x:2,y:0,tolerance:0.2))))
    }
}
