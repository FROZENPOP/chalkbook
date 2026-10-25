import Foundation
import UIKit
import ImageIO

enum SocialPhoto {
    static func prepare(_ data:Data) throws -> Data {
        guard data.count<=ProfilePhoto.maximumImportBytes,
              let source=CGImageSourceCreateWithData(data as CFData,nil),
              let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:256,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { throw BackupError.invalid("Choose a readable photo smaller than 10 MB.") }
        for quality in [0.8,0.6,0.4] {
            if let jpeg=UIImage(cgImage:image).jpegData(compressionQuality:quality),jpeg.count<=65_536 { return jpeg }
        }
        throw BackupError.invalid("Choose a simpler profile photo.")
    }
}
