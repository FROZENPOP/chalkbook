import Foundation
import CoreGraphics
import ImageIO

/// A reviewed, metadata-free presentation pair. No notebook, markup, Health or local path fields.
struct SharedRoutePhoto: Codable, Equatable, Identifiable, Sendable {
    static let maximumBytes = 131_072
    var id: UUID
    var entry_id: UUID?
    var original_base64: String
    var highlighted_base64: String?

    func validated() throws -> Self {
        for encoded in [original_base64, highlighted_base64].compactMap({ $0 }) {
            guard encoded.utf8.count <= 174_764, let data = Data(base64Encoded: encoded), data.count <= Self.maximumBytes,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetType(source) as String? == "public.jpeg",
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int,
                  (1...1024).contains(width), (1...1024).contains(height) else { throw SocialError.photoUnreadable }
        }
        return self
    }
    var rpcValues: [String: Any] {
        ["id": id.uuidString, "original_base64": original_base64, "highlighted_base64": highlighted_base64 as Any? ?? NSNull()]
    }
    static func prepare(data: Data, settings: HoldHighlightSettings?) async throws -> Self {
        let worker = Task.detached(priority: .userInitiated) {
            let original = try HoldHighlight.load(data)
            try Task.checkCancellation()
            let highlighted = try settings.map { saved in
                var visible = saved; visible.isEnabled = true
                return try HoldHighlight.render(original, settings: visible)
            }
            return try SharedRoutePhoto(id: UUID(), original_base64: jpeg(original).base64EncodedString(),
                                        highlighted_base64: highlighted.map { try jpeg($0).base64EncodedString() }).validated()
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
    private static func jpeg(_ image: CGImage) throws -> Data {
        for quality in [0.85, 0.7, 0.55, 0.4, 0.25] {
            try Task.checkCancellation()
            let bytes = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(bytes, "public.jpeg" as CFString, 1, nil) else { throw SocialError.photoUnreadable }
            // CGImage pixels only: never copy source EXIF/GPS or private stroke annotations.
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            if CGImageDestinationFinalize(destination), bytes.length <= maximumBytes { return bytes as Data }
        }
        throw BackupError.invalid("This photo couldn’t be prepared for sharing. Try a smaller image. Your original is unchanged.")
    }
}
