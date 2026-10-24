// Generate original, tiny route fixtures for simulator media-import tests.
// Usage: swift scripts/create_test_media.swift /absolute/output/directory
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let colorSpace = CGColorSpaceCreateDeviceRGB()
func draw(_ context: CGContext, width: Int, height: Int, offset: CGFloat = 0) {
    context.setFillColor(CGColor(red: 0.92, green: 0.90, blue: 0.84, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for index in 0..<6 {
        context.setFillColor(index.isMultiple(of: 2) ? CGColor(red: 0.1, green: 0.4, blue: 0.7, alpha: 1) : CGColor(red: 0.2, green: 0.5, blue: 0.3, alpha: 1))
        context.fillEllipse(in: CGRect(x: 25 + CGFloat(index % 3) * 90 + offset, y: 20 + CGFloat(index / 3) * 110, width: 30, height: 22))
    }
}
let context = CGContext(data: nil, width: 320, height: 240, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
draw(context, width: 320, height: 240)
let image = context.makeImage()!
let imageURL = directory.appendingPathComponent("route-photo.png")
let destination = CGImageDestinationCreateWithURL(imageURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
precondition(CGImageDestinationFinalize(destination))

let movieURL = directory.appendingPathComponent("route-video.mov")
if FileManager.default.fileExists(atPath: movieURL.path) { try FileManager.default.removeItem(at: movieURL) }
let writer = try AVAssetWriter(outputURL: movieURL, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 240])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 240])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)
for frame in 0..<20 {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
    var pixel: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixel)
    let buffer = pixel!
    CVPixelBufferLockBaseAddress(buffer, [])
    let canvas = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 320, height: 240, bitsPerComponent: 8,
                          bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorSpace,
                          bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
    draw(canvas, width: 320, height: 240, offset: CGFloat(frame) / 3)
    CVPixelBufferUnlockBaseAddress(buffer, [])
    precondition(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 10)))
}
input.markAsFinished()
let finished = DispatchSemaphore(value: 0)
writer.finishWriting { finished.signal() }
finished.wait()
if let error = writer.error { throw error }
print(imageURL.path)
print(movieURL.path)
