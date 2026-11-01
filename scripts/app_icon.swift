import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// One amber hold on a forest wall, circled the way the app highlights holds on route photos.
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, a])! }
func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)! }
var seed: UInt64 = 7
func random() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }

// Wall: forest, lit from the upper left, with a faint T-nut grid.
ctx.drawRadialGradient(gradient([color(0.18, 0.47, 0.37), color(0.07, 0.24, 0.19)], [0, 1]),
                       startCenter: CGPoint(x: 300, y: 820), startRadius: 0, endCenter: CGPoint(x: 300, y: 820), endRadius: 1150, options: [.drawsAfterEndLocation])
for gx in stride(from: 128, through: 896, by: 192) { for gy in stride(from: 128, through: 896, by: 192) {
    ctx.setFillColor(color(0.03, 0.14, 0.11, 0.5)); ctx.fillEllipse(in: CGRect(x: gx - 8, y: gy - 8, width: 16, height: 16))
}}

struct Hold { var center: CGPoint; var tilt: CGFloat; var scale: CGFloat; var light, mid, dark: CGColor; var lobes: [CGFloat] }
func point(_ h: Hold, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
    let x = x * h.scale, y = y * h.scale
    return CGPoint(x: h.center.x + x * cos(h.tilt) - y * sin(h.tilt), y: h.center.y + x * sin(h.tilt) + y * cos(h.tilt))
}
// A lumpy blob from a few low-frequency lobes, so it reads as a cast hold, not a vessel.
func outline(_ h: Hold) -> CGPath {
    let p = CGMutablePath()
    for i in 0...200 {
        let t = CGFloat(i) / 200 * 2 * .pi
        let r = 250 + h.lobes[0] * sin(2 * t + 0.6) + h.lobes[1] * sin(3 * t + 2.1) + h.lobes[2] * sin(5 * t + 0.4)
        let q = point(h, 1.15 * r * cos(t), 0.9 * r * sin(t))
        i == 0 ? p.move(to: q) : p.addLine(to: q)
    }
    p.closeSubpath(); return p
}
func body(_ h: Hold) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 28 * h.scale, height: -40 * h.scale), blur: 48 * h.scale, color: color(0, 0.07, 0.05, 0.75))
    ctx.addPath(outline(h)); ctx.setFillColor(h.dark); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(outline(h)); ctx.clip()
    ctx.drawRadialGradient(gradient([h.light, h.mid, h.dark], [0, 0.45, 1]), startCenter: point(h, -90, 110), startRadius: 0,
                           endCenter: point(h, 20, 0), endRadius: 330 * h.scale, options: [.drawsAfterEndLocation])
    // Sandy grip texture.
    for _ in 0..<Int(1400 * h.scale * h.scale) {
        let q = point(h, (random() - 0.5) * 640, (random() - 0.5) * 520)
        let light = random() > 0.5
        ctx.setFillColor(light ? color(1, 0.95, 0.85, 0.16) : color(0.25, 0.08, 0, 0.16))
        let d = 2 + random() * 3; ctx.fillEllipse(in: CGRect(x: q.x, y: q.y, width: d, height: d))
    }
}

func smallBolt(_ h: Hold) {
    let b = point(h, 10, -20)
    ctx.setFillColor(color(0.2, 0.15, 0.1, 0.8)); ctx.fillEllipse(in: CGRect(x: b.x - 20, y: b.y - 21, width: 40, height: 40))
    ctx.setFillColor(color(0.78, 0.82, 0.80)); ctx.fillEllipse(in: CGRect(x: b.x - 13, y: b.y - 12, width: 26, height: 26))
}
// Two small holds set the scene as a wall with a route on it.
let cream = Hold(center: CGPoint(x: 845, y: 870), tilt: 0.5, scale: 0.36, light: color(1, 0.98, 0.92), mid: color(0.90, 0.86, 0.76), dark: color(0.60, 0.56, 0.48), lobes: [40, 18, 10])
body(cream); ctx.restoreGState(); smallBolt(cream)
let rose = Hold(center: CGPoint(x: 150, y: 120), tilt: -0.9, scale: 0.42, light: color(1, 0.72, 0.70), mid: color(0.90, 0.42, 0.44), dark: color(0.55, 0.18, 0.22), lobes: [30, 26, 8])
body(rose); ctx.restoreGState(); smallBolt(rose)

// The hero: an amber jug with chalk on its incut lip and a bolt below.
let jug = Hold(center: CGPoint(x: 505, y: 505), tilt: -0.3, scale: 1, light: color(1, 0.84, 0.55), mid: color(0.97, 0.61, 0.25), dark: color(0.58, 0.25, 0.06), lobes: [30, 20, 10])
body(jug)
let scoop = CGMutablePath()
scoop.move(to: point(jug, -195, 110))
scoop.addCurve(to: point(jug, 190, 100), control1: point(jug, -100, 190), control2: point(jug, 100, 185))
scoop.addCurve(to: point(jug, -195, 110), control1: point(jug, 95, 140), control2: point(jug, -95, 148))
ctx.addPath(scoop); ctx.setFillColor(color(0.34, 0.12, 0.02, 0.92)); ctx.fillPath()
let lip = CGMutablePath()
lip.move(to: point(jug, -175, 145)); lip.addCurve(to: point(jug, 165, 138), control1: point(jug, -85, 215), control2: point(jug, 85, 210))
ctx.addPath(lip); ctx.setStrokeColor(color(1, 0.93, 0.76, 0.85)); ctx.setLineWidth(12); ctx.setLineCap(.round); ctx.strokePath()
for (x, y, r, a) in [(-110.0, 180.0, 70.0, 0.55), (0, 195, 80, 0.6), (100, 175, 65, 0.5), (40, 50, 60, 0.16), (-130, 20, 50, 0.12)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
    let c = point(jug, x, y)
    ctx.drawRadialGradient(gradient([color(1, 1, 1, a), color(1, 1, 1, 0)], [0, 1]), startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
}
ctx.restoreGState()
let bolt = point(jug, 25, -50)
ctx.setFillColor(color(0.36, 0.15, 0.03)); ctx.fillEllipse(in: CGRect(x: bolt.x - 50, y: bolt.y - 54, width: 100, height: 100))
ctx.drawRadialGradient(gradient([color(0.94, 0.96, 0.95), color(0.52, 0.57, 0.55)], [0, 1]), startCenter: CGPoint(x: bolt.x - 12, y: bolt.y + 14), startRadius: 0, endCenter: bolt, endRadius: 37, options: [])
ctx.beginPath()
for i in 0..<6 { let a = CGFloat(i) * .pi / 3 + .pi / 6; let q = CGPoint(x: bolt.x + 16 * cos(a), y: bolt.y + 16 * sin(a)); i == 0 ? ctx.move(to: q) : ctx.addLine(to: q) }
ctx.closePath(); ctx.setFillColor(color(0.20, 0.23, 0.22)); ctx.fillPath()

// Highlight ring: a mint marker loop that overshoots where it closes, like a hand-drawn circle.
ctx.saveGState()
ctx.translateBy(x: 505, y: 505); ctx.rotate(by: -0.3)
let ring = CGMutablePath()
for i in 0...200 {
    let f = CGFloat(i) / 200, t = 2.2 + f * (2 * .pi + 0.6)
    let grow = 0.93 + 0.14 * f
    let q = CGPoint(x: 400 * grow * cos(t), y: 340 * grow * sin(t))
    i == 0 ? ring.move(to: q) : ring.addLine(to: q)
}
ctx.addPath(ring)
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0, 0.08, 0.05, 0.45))
ctx.setStrokeColor(color(0.50, 0.90, 0.74)); ctx.setLineWidth(36); ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.strokePath()
ctx.restoreGState()

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
