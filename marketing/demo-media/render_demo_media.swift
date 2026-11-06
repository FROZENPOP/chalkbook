#!/usr/bin/env swift
// Renders the demo route photos and avatar used only by the App Store screenshot run.
// Usage: swift marketing/demo-media/render_demo_media.swift [out-dir]
// Every route's start hold sits at (0.5, 0.86) of the image; ScreenshotDemo selects it to highlight the route.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Generator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 { state &+= 0x9E3779B97F4A7C15; var z = state; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
}
typealias RGB = (CGFloat, CGFloat, CGFloat)
let palette: [String: RGB] = [
    "pink": (0.93, 0.20, 0.55), "blue": (0.16, 0.42, 0.88), "green": (0.18, 0.68, 0.32), "yellow": (0.98, 0.82, 0.12),
    "purple": (0.52, 0.27, 0.80), "orange": (0.97, 0.50, 0.12), "black": (0.12, 0.12, 0.13), "white": (0.95, 0.95, 0.93), "teal": (0.10, 0.66, 0.66),
]
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "marketing/demo-media")
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func context(_ width: Int, _ height: Int) -> CGContext {
    let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    c.translateBy(x: 0, y: CGFloat(height)); c.scaleBy(x: 1, y: -1) // top-left origin, like the photos' normalized points
    return c
}
func color(_ rgb: RGB, _ scale: CGFloat = 1, alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [min(1, rgb.0 * scale), min(1, rgb.1 * scale), min(1, rgb.2 * scale), alpha])!
}
func save(_ c: CGContext, _ name: String) {
    let url = out.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, c.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write \(url.path)") }
    print("wrote \(url.path)")
}
/// An irregular rounded blob: a smooth closed curve through jittered radial points.
func blob(center: CGPoint, radius: CGFloat, rng: inout Generator) -> CGPath {
    let count = 7
    let points = (0..<count).map { i -> CGPoint in
        let angle = CGFloat(i) / CGFloat(count) * 2 * .pi + CGFloat.random(in: -0.25...0.25, using: &rng)
        let r = radius * CGFloat.random(in: 0.7...1.15, using: &rng)
        return CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r * 0.82)
    }
    let path = CGMutablePath()
    func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    path.move(to: mid(points[count - 1], points[0]))
    for i in 0..<count { path.addQuadCurve(to: mid(points[i], points[(i + 1) % count]), control: points[i]) }
    path.closeSubpath()
    return path
}
func hold(_ c: CGContext, at center: CGPoint, radius: CGFloat, rgb: RGB, rng: inout Generator) {
    let path = blob(center: center, radius: radius, rng: &rng)
    c.saveGState()
    c.setShadow(offset: CGSize(width: radius * 0.18, height: radius * 0.28), blur: radius * 0.45, color: CGColor(gray: 0, alpha: 0.45))
    c.addPath(path); c.setFillColor(color(rgb)); c.fillPath()
    c.restoreGState()
    // Light from the top left: brighter rim up there, darker underside.
    c.saveGState(); c.addPath(path); c.clip()
    let gradient = CGGradient(colorsSpace: sRGB, colors: [color(rgb, 1.18), color(rgb), color(rgb, 0.72)] as CFArray, locations: [0, 0.5, 1])!
    c.drawLinearGradient(gradient, start: CGPoint(x: center.x - radius, y: center.y - radius), end: CGPoint(x: center.x + radius, y: center.y + radius), options: [])
    for _ in 0..<3 { // chalk dust
        let p = CGPoint(x: center.x + .random(in: -radius...radius, using: &rng) * 0.6, y: center.y + .random(in: -radius...radius, using: &rng) * 0.5)
        let s = CGFloat.random(in: 2...radius * 0.18, using: &rng)
        c.setFillColor(CGColor(gray: 1, alpha: 0.10)); c.fillEllipse(in: CGRect(x: p.x - s, y: p.y - s, width: s * 2, height: s * 2))
    }
    c.restoreGState()
    c.setFillColor(CGColor(gray: 0.1, alpha: 0.8)) // bolt
    c.fillEllipse(in: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
}

/// `highlighted` dims everything but the route, like the app's hold highlight, for the Friends feed photos.
func wall(_ name: String, route: String, seed: UInt64, tint: RGB, highlighted: Bool = false) {
    let width = 1200, height = 900, w = CGFloat(width), h = CGFloat(height)
    var rng = Generator(state: seed)
    let c = context(width, height)
    // Painted plywood, lit from above.
    let light = CGGradient(colorsSpace: sRGB, colors: [color(tint, 1.08), color(tint, 0.78)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(light, start: .zero, end: CGPoint(x: w * 0.3, y: h), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // An angled volume on one side.
    let left = seed % 2 == 0
    let volume = CGMutablePath()
    volume.addLines(between: left ? [CGPoint(x: 0, y: h * 0.15), CGPoint(x: w * 0.26, y: h * 0.42), CGPoint(x: 0, y: h * 0.78)]
                                  : [CGPoint(x: w, y: h * 0.1), CGPoint(x: w * 0.72, y: h * 0.36), CGPoint(x: w, y: h * 0.7)])
    volume.closeSubpath()
    c.addPath(volume); c.setFillColor(color(tint, 0.62)); c.fillPath()
    // Panel seams and the T-nut grid.
    c.setStrokeColor(CGColor(gray: 0, alpha: 0.18)); c.setLineWidth(3)
    for x in stride(from: w / 3, to: w, by: w / 3) { c.move(to: CGPoint(x: x, y: 0)); c.addLine(to: CGPoint(x: x, y: h)) }
    c.move(to: CGPoint(x: 0, y: h / 2)); c.addLine(to: CGPoint(x: w, y: h / 2)); c.strokePath()
    c.setFillColor(CGColor(gray: 0.15, alpha: 0.55))
    for x in stride(from: CGFloat(30), to: w, by: 50) { for y in stride(from: CGFloat(30), to: h, by: 50) { c.fillEllipse(in: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)) } }
    for _ in 0..<14 { // old chalk marks
        let p = CGPoint(x: .random(in: 0...w, using: &rng), y: .random(in: 0...h, using: &rng)), s = CGFloat.random(in: 10...40, using: &rng)
        c.setFillColor(CGColor(gray: 1, alpha: 0.08)); c.fillEllipse(in: CGRect(x: p.x - s, y: p.y - s * 0.6, width: s * 2, height: s * 1.2))
    }
    var placed: [(CGPoint, CGFloat)] = []
    func free(_ p: CGPoint, _ r: CGFloat) -> Bool { placed.allSatisfy { hypot($0.0.x - p.x, $0.0.y - p.y) > $0.1 + r + 14 } }
    // The route zigzags up from the start hold at (0.5, 0.86).
    var routeHolds = [(CGPoint(x: w * 0.5, y: h * 0.86), CGFloat(34))]
    for step in 1..<9 {
        let y = h * (0.86 - CGFloat(step) * 0.095)
        let x = w * (0.5 + (step % 2 == 0 ? -1 : 1) * CGFloat.random(in: 0.06...0.16, using: &rng))
        routeHolds.append((CGPoint(x: x, y: y), CGFloat.random(in: 18...34, using: &rng)))
    }
    placed = routeHolds
    var others: [(CGPoint, CGFloat, RGB)] = []
    let otherColors = palette.keys.filter { $0 != route }.sorted()
    var tries = 0
    while others.count < 46 && tries < 5000 {
        tries += 1
        let r = CGFloat.random(in: 14...36, using: &rng)
        let p = CGPoint(x: .random(in: r + 20...(w - r - 20), using: &rng), y: .random(in: r + 20...(h - r - 20), using: &rng))
        guard free(p, r) else { continue }
        placed.append((p, r)); others.append((p, r, palette[otherColors.randomElement(using: &rng)!]!))
    }
    for item in others { hold(c, at: item.0, radius: item.1, rgb: item.2, rng: &rng) }
    if highlighted { // desaturate, then dim
        c.setBlendMode(.saturation); c.setFillColor(CGColor(gray: 0.5, alpha: 0.88)); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        c.setBlendMode(.normal); c.setFillColor(CGColor(gray: 0, alpha: 0.45)); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
    }
    for item in routeHolds { hold(c, at: item.0, radius: item.1, rgb: palette[route]!, rng: &rng) }
    save(c, name)
}

func avatar() {
    // A made-up climber silhouette on a boulder at dusk: no real person.
    let size = 512, s = CGFloat(size)
    let c = context(size, size)
    let sky = CGGradient(colorsSpace: sRGB, colors: [color((0.20, 0.17, 0.35)), color((0.98, 0.55, 0.30)), color((0.99, 0.75, 0.40))] as CFArray, locations: [0, 0.65, 1])!
    c.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: s), options: [])
    c.setFillColor(color((1, 0.9, 0.7), alpha: 0.9)); c.fillEllipse(in: CGRect(x: s * 0.62, y: s * 0.52, width: s * 0.2, height: s * 0.2))
    let rock = CGMutablePath()
    rock.addLines(between: [CGPoint(x: 0, y: s), CGPoint(x: 0, y: s * 0.62), CGPoint(x: s * 0.18, y: s * 0.48), CGPoint(x: s * 0.5, y: s * 0.44),
                            CGPoint(x: s * 0.66, y: s * 0.6), CGPoint(x: s * 0.84, y: s * 0.7), CGPoint(x: s, y: s * 0.78), CGPoint(x: s, y: s)])
    rock.closeSubpath()
    c.addPath(rock); c.setFillColor(color((0.10, 0.08, 0.12))); c.fillPath()
    // Climber topping out: head, torso, arms up, legs on the face.
    let ink = color((0.10, 0.08, 0.12))
    c.setFillColor(ink); c.fillEllipse(in: CGRect(x: s * 0.40, y: s * 0.22, width: s * 0.08, height: s * 0.08))
    c.setStrokeColor(ink); c.setLineCap(.round); c.setLineWidth(s * 0.045)
    c.move(to: CGPoint(x: s * 0.44, y: s * 0.31)); c.addLine(to: CGPoint(x: s * 0.42, y: s * 0.43)) // torso
    c.move(to: CGPoint(x: s * 0.44, y: s * 0.33)); c.addLine(to: CGPoint(x: s * 0.33, y: s * 0.24)); c.addLine(to: CGPoint(x: s * 0.30, y: s * 0.14)) // arm up
    c.move(to: CGPoint(x: s * 0.44, y: s * 0.34)); c.addLine(to: CGPoint(x: s * 0.55, y: s * 0.40)) // arm on the lip
    c.move(to: CGPoint(x: s * 0.42, y: s * 0.43)); c.addLine(to: CGPoint(x: s * 0.33, y: s * 0.50)); c.addLine(to: CGPoint(x: s * 0.36, y: s * 0.58)) // leg
    c.move(to: CGPoint(x: s * 0.42, y: s * 0.43)); c.addLine(to: CGPoint(x: s * 0.50, y: s * 0.52)) // leg
    c.strokePath()
    save(c, "avatar.jpg")
}

try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for highlighted in [false, true] {
    let suffix = highlighted ? "-highlighted.jpg" : ".jpg"
    wall("wall-pink" + suffix, route: "pink", seed: 11, tint: (0.80, 0.78, 0.74), highlighted: highlighted)
    wall("wall-blue" + suffix, route: "blue", seed: 12, tint: (0.72, 0.74, 0.76), highlighted: highlighted)
    wall("wall-green" + suffix, route: "green", seed: 13, tint: (0.82, 0.80, 0.76), highlighted: highlighted)
    wall("wall-yellow" + suffix, route: "yellow", seed: 14, tint: (0.46, 0.48, 0.52), highlighted: highlighted)
    wall("wall-purple" + suffix, route: "purple", seed: 15, tint: (0.78, 0.77, 0.75), highlighted: highlighted)
}
avatar()
