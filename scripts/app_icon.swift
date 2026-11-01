import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Ascent: two amber chevrons on black, matching ClimbTheme.accent in dark mode.
// Usage: swift scripts/app_icon.swift ClimbingApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, a])! }
func chevron(_ y: CGFloat, _ stroke: CGColor) {
    ctx.setStrokeColor(stroke); ctx.setLineWidth(110); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.addLines(between: [CGPoint(x: 272, y: y), CGPoint(x: 512, y: y + 200), CGPoint(x: 752, y: y)]); ctx.strokePath()
}
ctx.setFillColor(color(0.043, 0.051, 0.047)); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
chevron(360, color(0.98, 0.69, 0.36, 0.45))
chevron(560, color(0.98, 0.69, 0.36))

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
