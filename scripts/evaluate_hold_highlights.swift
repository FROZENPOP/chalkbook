import Foundation
import CoreGraphics
import ImageIO

/// Mac command-line driver compiled with the production HoldHighlight.swift, no algorithm copy.
@main struct EvaluateHighlights {
    struct Fixture: Decodable {
        let filename: String
        let cases: [Tap]
    }
    struct Tap: Decodable { let number: Int; let x: Double; let y: Double; let color: String; let include: [RoutePoint]? }
    struct Result: Codable {
        let fixture: String; let number: Int; let color: String
        let previewMilliseconds: Double; let fullMilliseconds: Double
        let inputWidth: Int; let inputHeight: Int; let previewWidth: Int; let previewHeight: Int
        let before: String; let after: String; let compare: String
    }
    static func png(_ image: CGImage, _ path: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(path as CFURL, "public.png" as CFString, 1, nil) else { throw HoldHighlight.Failure.imageUnavailable }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw HoldHighlight.Failure.imageUnavailable }
    }
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fixtures = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOLD_HIGHLIGHT_FIXTURES"] ?? root.appending(path: "build/fixtures").path)
        guard FileManager.default.fileExists(atPath: fixtures.path) else { print("SKIP: no fixture directory at \(fixtures.path)"); return }
        let manifest = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: root.appending(path: "scripts/hold_highlight_fixtures.json")))
        let output = root.appending(path: "build/highlight-results")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var results = [Result]()
        for fixture in manifest {
            let data = try Data(contentsOf: fixtures.appending(path: fixture.filename))
            let original = try HoldHighlight.load(data, quality: .fullResolution)
            for tap in fixture.cases {
                let settings = HoldHighlightSettings(selections: [RoutePoint(x: tap.x, y: tap.y)] + (tap.include ?? []), tolerance: 0.35)
                var start = DispatchTime.now().uptimeNanoseconds
                let preview = try HoldHighlight.render(HoldHighlight.load(data), settings: settings)
                let previewTime = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                start = DispatchTime.now().uptimeNanoseconds
                let full = try HoldHighlight.render(HoldHighlight.load(data, quality: .fullResolution), settings: settings, quality: .fullResolution)
                let fullTime = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                let name = fixture.filename.replacingOccurrences(of: ".jpg", with: "") + "_\(tap.number)"
                let before = output.appending(path: name + "_before.png"), after = output.appending(path: name + "_after.png"), compare = output.appending(path: name + "_compare.png")
                try png(original, before); try png(full, after)
                let scale = min(1, 700 / Double(max(original.width, original.height)))
                let w = max(1, Int(Double(original.width) * scale)), h = max(1, Int(Double(original.height) * scale))
                guard let context = CGContext(data: nil, width: w * 2, height: h, bitsPerComponent: 8, bytesPerRow: w * 8, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw HoldHighlight.Failure.imageUnavailable }
                context.interpolationQuality = .high
                context.draw(original, in: CGRect(x: 0, y: 0, width: w, height: h))
                context.draw(full, in: CGRect(x: w, y: 0, width: w, height: h))
                try png(context.makeImage()!, compare)
                let result = Result(fixture: fixture.filename, number: tap.number, color: tap.color, previewMilliseconds: previewTime, fullMilliseconds: fullTime, inputWidth: original.width, inputHeight: original.height, previewWidth: preview.width, previewHeight: preview.height, before: before.path, after: after.path, compare: compare.path)
                results.append(result)
                print("\(name): \(original.width)×\(original.height) → \(preview.width)×\(preview.height); preview \(Int(previewTime)) ms; full \(Int(fullTime)) ms")
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(results).write(to: output.appending(path: "results.json"))
    }
}
