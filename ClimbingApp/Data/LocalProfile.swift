import Foundation
import ImageIO
import Observation
import UIKit

struct LocalProfile: Codable, Equatable {
    var name: String
    var bio: String
    var photo: Data?
    var setupComplete: Bool
    var updatedAt: Date
}

enum ProfilePhoto {
    static let maximumImportBytes = 10_000_000
    static let maximumStoredBytes = 1_000_000

    static func prepare(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= maximumImportBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary),
              let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.85),
              jpeg.count <= maximumStoredBytes else {
            throw BackupError.invalid("Choose a readable photo smaller than 10 MB.")
        }
        // Re-encoding the pixels keeps orientation and excludes original location/EXIF metadata.
        return jpeg
    }
}

@MainActor
@Observable
final class ProfileStore {
    private(set) var profile: LocalProfile?
    private(set) var errorMessage: String?
    private let file: URL
    private let validKey: Bool

    init(key: String, directory: URL? = nil) {
        let valid = key == "guest" || (key.count == 64 && key.allSatisfy { "0123456789abcdef".contains($0) })
        validKey = valid
        let root = directory ?? URL.applicationSupportDirectory.appending(path: "Profiles")
        file = root.appending(path: valid ? key : "invalid-profile-key").appending(path: "profile.json")
        guard valid else { errorMessage = "This profile’s storage identifier is invalid."; return }
        load()
    }

    func load() {
        guard validKey else { errorMessage = "This profile’s storage identifier is invalid."; return }
        do {
            guard FileManager.default.fileExists(atPath: file.path) else { profile = nil; errorMessage = nil; return }
            let data = try Data(contentsOf: file)
            guard data.count <= 2_000_000 else { throw BackupError.invalid("The saved profile is too large to open.") }
            let loaded = try JSONDecoder().decode(LocalProfile.self, from: data)
            try Self.validate(name: loaded.name, bio: loaded.bio, photo: loaded.photo)
            profile = loaded; errorMessage = nil
        } catch {
            errorMessage = "Your profile couldn’t be opened. Its saved file has been kept. Try again."
        }
    }

    static func validate(name: String, bio: String, photo: Data?) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60 else { throw BackupError.invalid("Enter a display name of 1–60 characters.") }
        guard bio.count <= 500 else { throw BackupError.invalid("Keep your bio to 500 characters or fewer.") }
        if let photo {
            guard photo.count <= ProfilePhoto.maximumStoredBytes,
                  let source = CGImageSourceCreateWithData(photo as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  (1...512).contains(width), (1...512).contains(height),
                  CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw BackupError.invalid("Choose a readable profile photo.") }
        }
    }

    @discardableResult
    func save(name: String, bio: String, photo: Data?, setupComplete: Bool = true) -> Bool {
        do {
            // Do not overwrite an unreadable existing profile as an incidental save.
            guard errorMessage == nil else { return false }
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            try Self.validate(name: name, bio: bio, photo: photo)
            let next = LocalProfile(name: name, bio: bio, photo: photo, setupComplete: setupComplete, updatedAt: .now)
            let data = try JSONEncoder().encode(next)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            profile = next
            return true
        } catch {
            // A write failure leaves the last saved profile and the editor draft intact.
            errorMessage = "Your profile couldn’t be saved. \(error.localizedDescription)"
            return false
        }
    }

    func retryLoading() { load() }
    func retrySave(name: String, bio: String, photo: Data?, setupComplete: Bool = true) -> Bool {
        // Re-read first so a damaged file is never overwritten by a retry.
        load()
        guard errorMessage == nil else { return false }
        return save(name: name, bio: bio, photo: photo, setupComplete: setupComplete)
    }
}
