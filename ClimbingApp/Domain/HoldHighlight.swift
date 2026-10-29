import CoreGraphics
import Foundation
import ImageIO

struct HoldHighlightSettings: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var tolerance: Double

    var isValid: Bool {
        [x, y, tolerance].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

enum HoldHighlight {
    struct Color: Equatable {
        var hue: Double
        var saturation: Double
        var brightness: Double

        init(red: Double, green: Double, blue: Double) {
            let high = max(red, green, blue), low = min(red, green, blue), delta = high - low
            brightness = high
            saturation = high == 0 ? 0 : delta / high
            if delta == 0 { hue = 0 }
            else if high == red { hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) / 6 }
            else if high == green { hue = ((blue - red) / delta + 2) / 6 }
            else { hue = ((red - green) / delta + 4) / 6 }
            if hue < 0 { hue += 1 }
        }
    }

    /// Neutral holds use brightness and saturation; hue has no meaning for white/gray/black.
    static func distance(_ color: Color, from reference: Color) -> Double {
        let saturation = abs(color.saturation - reference.saturation)
        let brightness = abs(color.brightness - reference.brightness)
        if reference.saturation < 0.18 || reference.brightness < 0.12 {
            return min(1, sqrt(0.65 * brightness * brightness + 0.35 * saturation * saturation))
        }
        let hue = min(abs(color.hue - reference.hue), 1 - abs(color.hue - reference.hue)) * 2
        return min(1, sqrt(0.7 * hue * hue + 0.2 * saturation * saturation + 0.1 * brightness * brightness))
    }

    /// Input coordinates use the displayed, orientation-normalized image, with a top-left origin.
    static func normalizedPoint(_ point: CGPoint, imageSize: CGSize, containerSize: CGSize) -> CGPoint? {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0,
              point.x.isFinite, point.y.isFinite else { return nil }
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: (containerSize.width - size.width) / 2, y: (containerSize.height - size.height) / 2)
        let x = (point.x - origin.x) / size.width, y = (point.y - origin.y) / size.height
        guard (0...1).contains(x), (0...1).contains(y) else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// ImageIO applies all EXIF rotations and mirrors before coordinates are sampled.
    static func load(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { throw Failure.imageUnavailable }
        return image
    }

    enum Failure: LocalizedError {
        case imageUnavailable, invalidSelection
        var errorDescription: String? {
            switch self {
            case .imageUnavailable: return "This photo couldn’t be processed. Try opening it again or choose another photo."
            case .invalidSelection: return "Tap a hold inside the photo to select its color."
            }
        }
    }

    struct Pixels {
        let width: Int
        let height: Int
        var bytes: [UInt8]
        func color(x: Int, y: Int) -> Color {
            let i = (y * width + x) * 4
            // Transparent pixels must not introduce a false black reference.
            let alpha = max(1, Double(bytes[i + 3]))
            return Color(red: min(1, Double(bytes[i]) / alpha), green: min(1, Double(bytes[i + 1]) / alpha), blue: min(1, Double(bytes[i + 2]) / alpha))
        }
    }

    static func pixels(_ image: CGImage) throws -> Pixels {
        let scale = min(1, 1024 / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { throw Failure.imageUnavailable }
        return Pixels(width: width, height: height, bytes: bytes)
    }

    /// Median RGB channels resist a few chalk/specular outliers, then convert to HSV.
    static func reference(in pixels: Pixels, settings: HoldHighlightSettings) throws -> Color {
        guard settings.isValid else { throw Failure.invalidSelection }
        let x = min(pixels.width - 1, Int(settings.x * Double(pixels.width)))
        let y = min(pixels.height - 1, Int(settings.y * Double(pixels.height)))
        var channels = [[Double](), [Double](), [Double]()]
        for row in max(0, y - 2)...min(pixels.height - 1, y + 2) {
            for column in max(0, x - 2)...min(pixels.width - 1, x + 2) {
                let i = (row * pixels.width + column) * 4
                guard pixels.bytes[i + 3] > 0 else { continue }
                for c in 0..<3 { channels[c].append(min(1, Double(pixels.bytes[i + c]) / Double(pixels.bytes[i + 3]))) }
            }
        }
        guard !channels[0].isEmpty else { throw Failure.invalidSelection }
        let median = channels.map { $0.sorted()[$0.count / 2] }
        return Color(red: median[0], green: median[1], blue: median[2])
    }

    static func render(_ image: CGImage, settings: HoldHighlightSettings) throws -> CGImage {
        var pixels = try pixels(image)
        let reference = try reference(in: pixels, settings: settings)
        for y in 0..<pixels.height {
            try Task.checkCancellation()
            for x in 0..<pixels.width {
                guard distance(pixels.color(x: x, y: y), from: reference) > settings.tolerance else { continue }
                let i = (y * pixels.width + x) * 4
                let gray = UInt8((0.2126 * Double(pixels.bytes[i]) + 0.7152 * Double(pixels.bytes[i + 1]) + 0.0722 * Double(pixels.bytes[i + 2])) * 0.3)
                pixels.bytes[i] = gray; pixels.bytes[i + 1] = gray; pixels.bytes[i + 2] = gray
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels.bytes) as CFData),
              let output = CGImage(width: pixels.width, height: pixels.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: pixels.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw Failure.imageUnavailable }
        return output
    }
}

/// A cancellable worker keeps decoding and every pixel operation off the main actor.
extension HoldHighlight {
    static func process(data: Data, settings: HoldHighlightSettings?) async throws -> CGImage {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let original = try load(data)
            if let settings { return try render(original, settings: settings) }
            return original
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
}
