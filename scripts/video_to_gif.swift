// Converts a .mov/.mp4 into a looping animated GIF with AVFoundation and ImageIO (no ffmpeg needed).
// Usage: swift scripts/video_to_gif.swift <input.mov> <output.gif> [fps=12] [width=360] [trim=0.5]
// Drops `trim` seconds from each end, and merges runs of unchanged frames into one longer frame to keep the file small.
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: video_to_gif.swift <input> <output.gif> [fps] [width] [trim]\n".utf8)); exit(2)
}
let input = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
let fps = args.count > 3 ? Double(args[3])! : 12
let width = args.count > 4 ? Int(args[4])! : 360
let trim = args.count > 5 ? Double(args[5])! : 0.5

func fail(_ message: String) -> Never { FileHandle.standardError.write(Data("video_to_gif: \(message)\n".utf8)); exit(1) }

/// Frames redrawn into one fixed RGBA layout, so they can be compared byte for byte.
func pixels(_ image: CGImage) -> (CGImage, [UInt8]) {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let made: CGImage? = bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
    return (made!, bytes)
}
/// Video compression leaves faint noise on still screens; treat a mean channel difference under 0.6 as unchanged.
func same(_ a: [UInt8], _ b: [UInt8]) -> Bool {
    guard a.count == b.count else { return false }
    var total = 0
    for i in stride(from: 0, to: a.count, by: 4) { total += abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2])) }
    return Double(total) / Double(a.count / 4 * 3) < 0.6
}
assert(same([0, 0, 0, 255], [0, 0, 1, 255]) && !same([0, 0, 0, 255], [40, 40, 40, 255]), "frame comparison self-check")

let asset = AVURLAsset(url: input)
let duration = try await asset.load(.duration).seconds
guard duration > trim * 2 + 0.5 else { fail("\(input.lastPathComponent) is only \(duration)s long") }
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.maximumSize = CGSize(width: width, height: width * 10) // fits the width, keeps the aspect ratio
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

var frames: [(image: CGImage, bytes: [UInt8], delay: Double)] = []
let step = 1 / fps
var time = trim
while time < duration - trim {
    let (raw, _) = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
    let (image, bytes) = pixels(raw)
    if let last = frames.last, same(last.bytes, bytes) { frames[frames.count - 1].delay += step } else { frames.append((image, bytes, step)) }
    time += step
}
guard !frames.isEmpty else { fail("no frames decoded") }

guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { fail("can't write \(output.path)") }
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for frame in frames {
    // GIF delays are in hundredths of a second; the unclamped key keeps short delays as written.
    let delay = (frame.delay * 100).rounded() / 100
    CGImageDestinationAddImage(destination, frame.image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else { fail("can't finalize \(output.path)") }

// Self-check: the written file is an animated, looping GIF with every frame.
guard let check = CGImageSourceCreateWithURL(output as CFURL, nil), CGImageSourceGetCount(check) == frames.count,
      let properties = CGImageSourceCopyProperties(check, nil) as? [CFString: Any],
      let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any], (gif[kCGImagePropertyGIFLoopCount] as? Int) == 0 else { fail("\(output.path) didn't read back as a looping GIF") }
let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
let shown = frames.reduce(0) { $0 + $1.delay }
print(String(format: "%@: %d frames, %.1fs, %dx%d, %.2f MB", output.lastPathComponent, frames.count, shown, frames[0].image.width, frames[0].image.height, Double(size) / 1_048_576))
