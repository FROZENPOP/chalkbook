import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// App Store Header and Search Results art: the amber Ascent chevrons, name, tagline and fanned real screenshots on near-black.
// Usage: swift scripts/store_art.swift <screenshots-dir> <out-dir>
//        swift scripts/store_art.swift --self-test
// Safe areas are the centered "ART SAFE AREA" rectangles of Apple's creative-asset templates; the mark and text stay inside them.

let screens = ["2-session", "1-journal", "4-progress"]  // left, front (center), right
let tagline = "Log every attempt. Send your projects."
let screenSize = (width: 1206, height: 2622)

struct Art { let file: String; let width: Int; let height: Int; let safe: CGRect; let nameSize: CGFloat; let phoneHeight: CGFloat }
let arts = [
    Art(file: "header-3840x1646.png", width: 3840, height: 1646,
        safe: CGRect(x: 1097, y: 493, width: 1646, height: 661), nameSize: 150, phoneHeight: 1000),
    Art(file: "search-3840x2560.png", width: 3840, height: 2560,
        safe: CGRect(x: 836, y: 765, width: 2168, height: 1030), nameSize: 190, phoneHeight: 1400),
]

struct Failure: Error, CustomStringConvertible { let description: String }

let space = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, a])! }
let background = color(0.043, 0.051, 0.047), amber = color(0.98, 0.69, 0.36)

func loadScreens(_ dir: URL) throws -> [CGImage] {
    try screens.map { name in
        let url = dir.appendingPathComponent("\(name).png")
        guard FileManager.default.fileExists(atPath: url.path) else { throw Failure(description: "missing input \(url.path)") }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw Failure(description: "unreadable image \(url.path)") }
        guard image.width == screenSize.width, image.height == screenSize.height else {
            throw Failure(description: "\(url.path) is \(image.width)x\(image.height), expected \(screenSize.width)x\(screenSize.height)")
        }
        return image
    }
}

// The AscentMark chevrons (590x510 design box, top-left origin), scaled to `height` with the top-left at `origin`.
func drawMark(_ ctx: CGContext, origin: CGPoint, height: CGFloat) {
    let s = height / 510
    for (y, alpha) in [(455.0, 0.45), (255.0, 1.0)] {
        ctx.setStrokeColor(amber.copy(alpha: alpha)!); ctx.setLineWidth(110 * s); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.addLines(between: [CGPoint(x: origin.x + 55 * s, y: origin.y + y * s), CGPoint(x: origin.x + 295 * s, y: origin.y + (y - 200) * s),
                               CGPoint(x: origin.x + 535 * s, y: origin.y + y * s)])
        ctx.strokePath()
    }
}

func textLine(_ string: String, size: CGFloat, weight: NSFont.Weight, color: CGColor) -> (line: CTLine, width: CGFloat, ascent: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attrs))
    var ascent: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, nil, nil))
    return (line, width, ascent)
}

func draw(_ ctx: CGContext, _ text: CTLine, baseline: CGPoint) {
    ctx.saveGState(); ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1); ctx.textPosition = baseline; CTLineDraw(text, ctx); ctx.restoreGState()
}

// A plain rounded phone: dark body, thin rim, screenshot inset with rounded screen corners. Centered at `center`, rotated by `angle`.
func drawPhone(_ ctx: CGContext, _ image: CGImage, center: CGPoint, height: CGFloat, angle: CGFloat) {
    let bezel = height * 0.018
    let screenH = height - 2 * bezel, screenW = screenH * CGFloat(screenSize.width) / CGFloat(screenSize.height)
    let body = CGRect(x: -screenW / 2 - bezel, y: -height / 2, width: screenW + 2 * bezel, height: height)
    let screen = body.insetBy(dx: bezel, dy: bezel), radius = screenW * 0.135
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y); ctx.rotate(by: angle)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -height * 0.02), blur: height * 0.06, color: color(0, 0, 0, 0.75))
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: radius + bezel, cornerHeight: radius + bezel, transform: nil))
    ctx.setFillColor(color(0.11, 0.118, 0.114)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: bezel * 0.15, dy: bezel * 0.15), cornerWidth: radius + bezel * 0.85,
                       cornerHeight: radius + bezel * 0.85, transform: nil))
    ctx.setStrokeColor(color(1, 1, 1, 0.16)); ctx.setLineWidth(bezel * 0.3); ctx.strokePath()
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.clip()
    ctx.translateBy(x: screen.minX, y: screen.maxY); ctx.scaleBy(x: 1, y: -1)
    ctx.draw(image, in: CGRect(origin: .zero, size: screen.size))
    ctx.restoreGState()
}

func render(_ art: Art, _ images: [CGImage]) throws -> CGImage {
    let ctx = CGContext(data: nil, width: art.width, height: art.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.translateBy(x: 0, y: CGFloat(art.height)); ctx.scaleBy(x: 1, y: -1)  // top-left origin, like the AscentMark design box
    ctx.setFillColor(background); ctx.fill(CGRect(x: 0, y: 0, width: art.width, height: art.height))

    // Brand block (mark + name on one line, tagline sentences below) and phone fan, centered as one row on the canvas.
    // The brand block is clamped into the safe area; the fan overlaps it and may bleed past it.
    let safe = art.safe, nameSize = art.nameSize, tagSize = nameSize * 0.36
    let name = textLine("Chalkbook", size: nameSize, weight: .bold, color: color(0.96, 0.95, 0.93))
    let tags = tagline.replacingOccurrences(of: ". ", with: ".\n").split(separator: "\n")
        .map { textLine(String($0), size: tagSize, weight: .medium, color: color(1, 1, 1, 0.62)) }
    let markH = name.ascent * 0.92, markW = markH * 590 / 510, markGap = nameSize * 0.28
    let tagGap = nameSize * 0.42, tagLead = tagSize * 1.3
    let blockW = max(markW + markGap + name.width, tags.map(\.width).max() ?? 0)
    let blockH = name.ascent + tagGap + CGFloat(tags.count) * tagLead

    let phoneW = art.phoneHeight * CGFloat(screenSize.width) / CGFloat(screenSize.height)
    let side = phoneW * 0.52, sideScale: CGFloat = 0.86, tilt = 7 * CGFloat.pi / 180
    let fanHalf = side + phoneW * sideScale / 2 + art.phoneHeight * 0.05, gap = phoneW * 0.3
    let left = max(safe.minX, (CGFloat(art.width) - blockW - gap - 2 * fanHalf) / 2)
    let block = CGRect(x: left, y: safe.midY - blockH / 2, width: blockW, height: blockH)
    guard safe.contains(block) else { throw Failure(description: "\(art.file): name and tagline don't fit the safe area \(safe)") }

    let nameBaseline = block.minY + name.ascent
    drawMark(ctx, origin: CGPoint(x: left, y: nameBaseline - markH), height: markH)
    draw(ctx, name.line, baseline: CGPoint(x: left + markW + markGap, y: nameBaseline))
    for (i, tag) in tags.enumerated() {
        draw(ctx, tag.line, baseline: CGPoint(x: left + nameSize * 0.03, y: nameBaseline + tagGap + tagSize * 0.9 + CGFloat(i) * tagLead))
    }

    let fan = CGPoint(x: block.maxX + gap + fanHalf, y: safe.midY)
    let glow = CGGradient(colorsSpace: space, colors: [amber.copy(alpha: 0.12)!, amber.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: fan, startRadius: 0, endCenter: fan, endRadius: art.phoneHeight * 0.85, options: [])
    let sideY = fan.y + art.phoneHeight * 0.04
    drawPhone(ctx, images[0], center: CGPoint(x: fan.x - side, y: sideY), height: art.phoneHeight * sideScale, angle: -tilt)
    drawPhone(ctx, images[2], center: CGPoint(x: fan.x + side, y: sideY), height: art.phoneHeight * sideScale, angle: tilt)
    drawPhone(ctx, images[1], center: fan, height: art.phoneHeight, angle: 0)
    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw Failure(description: "can't create \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw Failure(description: "can't write \(url.path)") }
}

// Reads the written file back: exact size, sRGB, no alpha.
func verify(_ url: URL, _ art: Art) throws {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    else { throw Failure(description: "can't read back \(url.path)") }
    guard image.width == art.width, image.height == art.height else {
        throw Failure(description: "\(url.lastPathComponent) is \(image.width)x\(image.height), expected \(art.width)x\(art.height)")
    }
    guard props[kCGImagePropertyHasAlpha] as? Bool != true, [.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo) else {
        throw Failure(description: "\(url.lastPathComponent) has an alpha channel")
    }
    guard image.colorSpace?.name == CGColorSpace.sRGB else { throw Failure(description: "\(url.lastPathComponent) is not sRGB") }
}

func run(input: URL, output: URL) throws {
    let images = try loadScreens(input)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for art in arts {
        let url = output.appendingPathComponent(art.file)
        try write(try render(art, images), to: url)
        try verify(url, art)
    }
}

// Missing and wrong-size inputs must fail; right-size inputs must render and verify.
func selfTest() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("store_art-\(ProcessInfo.processInfo.processIdentifier)")
    defer { try? FileManager.default.removeItem(at: tmp) }
    func fixtures(_ dir: String, width: Int, height: Int) throws -> URL {
        let url = tmp.appendingPathComponent(dir)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(color(0.5, 0.5, 0.5)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for name in screens { try write(ctx.makeImage()!, to: url.appendingPathComponent("\(name).png")) }
        return url
    }
    func expectFailure(_ label: String, _ input: URL, containing needle: String) throws {
        do { try run(input: input, output: tmp.appendingPathComponent("out-\(label)")) } catch let error as Failure {
            guard error.description.contains(needle) else { throw Failure(description: "self-test \(label): unexpected error: \(error)") }
            print("self-test \(label): failed as expected (\(error))"); return
        }
        throw Failure(description: "self-test \(label): rendered from bad input")
    }
    try expectFailure("missing", tmp.appendingPathComponent("empty"), containing: "missing input")
    try expectFailure("wrong-size", fixtures("small", width: 1179, height: 2556), containing: "expected 1206x2622")
    let out = tmp.appendingPathComponent("out-ok")
    try run(input: fixtures("ok", width: screenSize.width, height: screenSize.height), output: out)
    print("self-test right-size: rendered and verified \(arts.map(\.file).joined(separator: ", "))")
}

let args = Array(CommandLine.arguments.dropFirst())
do {
    if args == ["--self-test"] { try selfTest() }
    else if args.count == 2 {
        try run(input: URL(fileURLWithPath: args[0]), output: URL(fileURLWithPath: args[1]))
        print("wrote \(arts.map { args[1] + "/" + $0.file }.joined(separator: ", "))")
    } else {
        FileHandle.standardError.write("usage: swift scripts/store_art.swift <screenshots-dir> <out-dir> | --self-test\n".data(using: .utf8)!)
        exit(2)
    }
} catch {
    FileHandle.standardError.write("store_art: \(error)\n".data(using: .utf8)!)
    exit(1)
}
