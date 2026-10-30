import CoreGraphics
import Foundation
import ImageIO

struct RoutePoint: Codable, Equatable, Sendable { var x: Double; var y: Double }

/// V1 stored x/y; V2 stores an extensible selection list and a reversible display switch.
struct HoldHighlightSettings: Codable, Equatable, Sendable {
    var selections: [RoutePoint]
    var tolerance: Double
    var isEnabled: Bool
    var x: Double { selections.first?.x ?? 0 }
    var y: Double { selections.first?.y ?? 0 }

    init(x: Double, y: Double, tolerance: Double) {
        self.init(selections: [RoutePoint(x: x, y: y)], tolerance: tolerance)
    }
    init(selections: [RoutePoint], tolerance: Double = 0.35, isEnabled: Bool = true) {
        self.selections = selections; self.tolerance = tolerance; self.isEnabled = isEnabled
    }
    private enum CodingKeys: String, CodingKey { case x, y, selections, tolerance, isEnabled }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tolerance = try values.decode(Double.self, forKey: .tolerance)
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        if values.contains(.selections) { selections = try values.decode([RoutePoint].self, forKey: .selections) }
        else { selections = [RoutePoint(x: try values.decode(Double.self, forKey: .x), y: try values.decode(Double.self, forKey: .y))] }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(selections, forKey: .selections)
        try values.encode(tolerance, forKey: .tolerance)
        try values.encode(isEnabled, forKey: .isEnabled)
    }
    var isValid: Bool {
        // A generous import bound prevents malicious backups from causing unbounded per-pixel work.
        !selections.isEmpty && selections.count <= 64 && tolerance.isFinite && (0...1).contains(tolerance) &&
        selections.allSatisfy { [$0.x, $0.y].allSatisfy { $0.isFinite && (0...1).contains($0) } }
    }
}

enum HoldHighlight {
    struct Color: Equatable {
        var hue: Double
        var saturation: Double
        var brightness: Double

        var isNeutral: Bool { saturation < 0.18 || brightness < 0.12 }

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

    /// Lift worn pigment without changing its hue. Neutrals keep their original tones.
    /// The remaining source contribution preserves texture instead of painting a flat color.
    static func emphasized(_ color: Color) -> (red: Double, green: Double, blue: Double) {
        // Keep very dark or weakly colored camera noise from becoming neon speckles.
        let strength = color.isNeutral ? 0 : 0.55 * min(1, max(0, (color.brightness - 0.12) / 0.18)) * min(1, max(0, (color.saturation - 0.18) / 0.3))
        let saturation = color.saturation + (1 - color.saturation) * strength
        let brightness = color.brightness + (1 - color.brightness) * strength
        let sector = color.hue * 6, chroma = brightness * saturation
        let secondary = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let offset = brightness - chroma
        let rgb: (Double, Double, Double)
        switch Int(sector) % 6 {
        case 0: rgb = (chroma, secondary, 0)
        case 1: rgb = (secondary, chroma, 0)
        case 2: rgb = (0, chroma, secondary)
        case 3: rgb = (0, secondary, chroma)
        case 4: rgb = (secondary, 0, chroma)
        default: rgb = (chroma, 0, secondary)
        }
        return (rgb.0 + offset, rgb.1 + offset, rgb.2 + offset)
    }

    /// Neutral holds use brightness and saturation; hue has no meaning for white/gray/black.
    static func distance(_ color: Color, from reference: Color) -> Double {
        let saturation = abs(color.saturation - reference.saturation)
        let brightness = abs(color.brightness - reference.brightness)
        if reference.isNeutral {
            return min(1, sqrt(0.65 * brightness * brightness + 0.35 * saturation * saturation))
        }
        let hue = min(abs(color.hue - reference.hue), 1 - abs(color.hue - reference.hue)) * 2
        return min(1, sqrt(0.955 * hue * hue + 0.04 * saturation * saturation + 0.005 * brightness * brightness))
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
    enum Quality: Sendable { case preview, fullResolution }

    static func load(_ data: Data, quality: Quality = .preview) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0,
              quality == .preview || Double(width) * Double(height) <= 40_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: quality == .preview ? 1024 : max(width, height),
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

    static func pixels(_ image: CGImage, maximumDimension: Int = 1024) throws -> Pixels {
        let scale = min(1, Double(maximumDimension) / Double(max(image.width, image.height)))
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

    struct Mask {
        let width: Int
        let height: Int
        var alpha: [Float]
    }

    /// Color similarity is only a proposal. Compact connected regions reject wall-sized matches,
    /// isolated noise and low-chroma paint. This is a heuristic, not semantic hold recognition.
    static func mask(in pixels: Pixels, settings: HoldHighlightSettings) throws -> Mask {
        guard settings.isValid else { throw Failure.invalidSelection }
        let count = pixels.width * pixels.height
        var colors = [Color](); colors.reserveCapacity(count)
        for y in 0..<pixels.height {
            try Task.checkCancellation()
            for x in 0..<pixels.width { colors.append(pixels.color(x: x, y: y)) }
        }
        var union = [Float](repeating: 0, count: count)
        for point in settings.selections {
            try Task.checkCancellation()
            let sample = HoldHighlightSettings(x: point.x, y: point.y, tolerance: settings.tolerance)
            let reference = try reference(in: pixels, settings: sample)
            let seed = min(pixels.height - 1, Int(point.y * Double(pixels.height))) * pixels.width + min(pixels.width - 1, Int(point.x * Double(pixels.width)))
            let neutral = reference.isNeutral
            let threshold = 0.055 + settings.tolerance * (neutral ? 0.22 : 0.32)
            var candidates = [Float](repeating: 0, count: count)
            for i in 0..<count {
                if i % pixels.width == 0 { try Task.checkCancellation() }
                let color = colors[i]
                guard pixels.bytes[i * 4 + 3] > 0 else { continue }
                // Warm, highly saturated pigment must not recolor lower-chroma skin.
                // Cool pigment can lose much more saturation under chalk and directional light.
                let warmPigment = (reference.hue < 0.18 || reference.hue > 0.94) && reference.saturation > 0.75
                let minimumSaturation = warmPigment ? reference.saturation * 0.82 : max(0.16, reference.saturation * 0.30)
                if !neutral && color.saturation < minimumSaturation { continue }
                if neutral && color.saturation > max(0.22, reference.saturation + 0.14) { continue }
                let d = distance(color, from: reference)
                // A soft color ramp, followed by spatial feathering, avoids binary cutouts.
                candidates[i] = Float(min(1, max(0, (threshold - d) / (threshold * 0.30))))
            }
            // Close very small gaps caused by chalk, texture or JPEG noise before labelling.
            // Separable max/min filters keep this O(pixels), with only a two-pixel radius.
            if count >= 4096 {
                for dilate in [true, false] {
                    for horizontal in [true, false] {
                        var filtered = candidates
                        for y in 0..<pixels.height {
                            try Task.checkCancellation()
                            for x in 0..<pixels.width {
                                var value: Float = dilate ? 0 : 1
                                for offset in -2...2 {
                                    let column = horizontal ? min(pixels.width - 1, max(0, x + offset)) : x
                                    let row = horizontal ? y : min(pixels.height - 1, max(0, y + offset))
                                    let neighbor = candidates[row * pixels.width + column]
                                    value = dilate ? max(value, neighbor) : min(value, neighbor)
                                }
                                filtered[y * pixels.width + x] = value
                            }
                        }
                        candidates = filtered
                    }
                }
            }
            var visited = [Bool](repeating: false, count: count)
            for start in 0..<count where candidates[start] > 0.05 && !visited[start] {
                var region = [start], head = 0, touchesEdge = false, includesSeed = false
                var minX = pixels.width, minY = pixels.height, maxX = 0, maxY = 0
                visited[start] = true
                while head < region.count {
                    let i = region[head]; head += 1
                    includesSeed = includesSeed || i == seed
                    if head % 4096 == 0 { try Task.checkCancellation() }
                    let x = i % pixels.width, y = i / pixels.width
                    minX = min(minX,x); maxX = max(maxX,x); minY = min(minY,y); maxY = max(maxY,y)
                    touchesEdge = touchesEdge || x == 0 || y == 0 || x == pixels.width - 1 || y == pixels.height - 1
                    for neighbor in [x > 0 ? i - 1 : -1, x + 1 < pixels.width ? i + 1 : -1,
                                     y > 0 ? i - pixels.width : -1, y + 1 < pixels.height ? i + pixels.width : -1] {
                        if neighbor >= 0 && !visited[neighbor] && candidates[neighbor] > 0.05 {
                            visited[neighbor] = true; region.append(neighbor)
                        }
                    }
                }
                let fraction = Double(region.count) / Double(count)
                // Tiny/synthetic images have insufficient spatial evidence: retain the color result.
                let hasSpatialEvidence = count >= 4096
                let boxArea = (maxX - minX + 1) * (maxY - minY + 1)
                if hasSpatialEvidence && !includesSeed && boxArea > 64 && Double(region.count) / Double(boxArea) < 0.22 { continue }
                let largest = includesSeed ? 0.30 : (neutral ? 0.035 : 0.10)
                if hasSpatialEvidence && (region.count < 5 || fraction > largest || (touchesEdge && !includesSeed && fraction > 0.0025 && (neutral || Double(region.count) / Double(boxArea) < 0.35))) { continue }
                for i in region { union[i] = max(union[i], candidates[i]) }
            }
        }
        // Small separable tent filter: intermediate alpha at boundaries, no glow/color expansion.
        for horizontal in [true, false, true, false] {
            var blurred = union
            for y in 0..<pixels.height {
                try Task.checkCancellation()
                for x in 0..<pixels.width {
                    let i = y * pixels.width + x
                    let before = horizontal ? y * pixels.width + max(0, x - 1) : max(0, y - 1) * pixels.width + x
                    let after = horizontal ? y * pixels.width + min(pixels.width - 1, x + 1) : min(pixels.height - 1, y + 1) * pixels.width + x
                    blurred[i] = (union[before] + 2 * union[i] + union[after]) / 4
                }
            }
            union = blurred
        }
        return Mask(width: pixels.width, height: pixels.height, alpha: union)
    }

    /// Full output preserves source detail; only segmentation is bounded to the preview grid.
    /// No derived image is saved by the journal: the settings regenerate its presentation.
    static func render(_ image: CGImage, settings: HoldHighlightSettings, quality: Quality = .preview) throws -> CGImage {
        guard settings.isValid else { throw Failure.invalidSelection }
        guard quality == .preview || Double(image.width) * Double(image.height) <= 40_000_000 else { throw Failure.imageUnavailable }
        let working = try pixels(image)
        let mask = settings.isEnabled ? try mask(in: working, settings: settings) : Mask(width: working.width, height: working.height, alpha: [Float](repeating: 1, count: working.width * working.height))
        let darkSelection = try settings.isEnabled && settings.selections.contains { point in
            let color = try reference(in: working, settings: .init(x: point.x, y: point.y, tolerance: settings.tolerance))
            return (color.isNeutral && color.brightness < 0.45) || color.brightness < 0.16
        }
        let enhancePigment = try settings.isEnabled && (settings.selections.contains { point in
            try !reference(in:working,settings:.init(x:point.x,y:point.y,tolerance:settings.tolerance)).isNeutral
        })
        var output = try pixels(image, maximumDimension: quality == .preview ? 1024 : max(image.width, image.height))
        for y in 0..<output.height {
            try Task.checkCancellation()
            let my = max(0, min(Double(mask.height - 1), (Double(y) + 0.5) * Double(mask.height) / Double(output.height) - 0.5))
            let y0 = Int(my), y1 = min(mask.height - 1, y0 + 1), fy = Float(my - Double(y0))
            for x in 0..<output.width {
                let mx = max(0, min(Double(mask.width - 1), (Double(x) + 0.5) * Double(mask.width) / Double(output.width) - 0.5))
                let x0 = Int(mx), x1 = min(mask.width - 1, x0 + 1), fx = Float(mx - Double(x0))
                let a = mask.alpha[y0 * mask.width + x0] * (1 - fx) + mask.alpha[y0 * mask.width + x1] * fx
                let b = mask.alpha[y1 * mask.width + x0] * (1 - fx) + mask.alpha[y1 * mask.width + x1] * fx
                let alpha = Double(a * (1 - fy) + b * fy), i = (y * output.width + x) * 4
                let gray = 0.2126 * Double(output.bytes[i]) + 0.7152 * Double(output.bytes[i + 1]) + 0.0722 * Double(output.bytes[i + 2])
                let color = output.color(x: x, y: y)
                let vivid = enhancePigment ? emphasized(color) : (red: Double(output.bytes[i]) / 255, green: Double(output.bytes[i + 1]) / 255, blue: Double(output.bytes[i + 2]) / 255)
                for c in 0..<3 {
                    let original = Double(output.bytes[i + c])
                    // 58% luminance and 15% residual color retain wall context without crushed blacks.
                    // Dark holds need a pale context rather than disappearing into a dim wall.
                    // Alpha-scaled lift preserves premultiplied transparency and original hold detail.
                    let background = darkSelection
                        ? gray * 0.35 + Double(output.bytes[i + 3]) * 0.55
                        : (gray * 0.85 + original * 0.15) * 0.58
                    let foreground = enhancePigment ? (c == 0 ? vivid.red : c == 1 ? vivid.green : vivid.blue) * Double(output.bytes[i + 3]) : original
                    output.bytes[i + c] = UInt8(min(255, max(0, (foreground * alpha + background * (1 - alpha)).rounded())))
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(output.bytes) as CFData),
              let result = CGImage(width: output.width, height: output.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: output.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw Failure.imageUnavailable }
        return result
    }

}

/// A cancellable worker keeps decoding and every pixel operation off the main actor.
extension HoldHighlight {
    static func process(data: Data, settings: HoldHighlightSettings?, quality: Quality = .preview) async throws -> CGImage {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let original = try load(data, quality: quality)
            if let settings { return try render(original, settings: settings, quality: quality) }
            return original
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
}
