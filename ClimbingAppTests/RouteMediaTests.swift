import AVFoundation
import UIKit
import SwiftData
import XCTest
@testable import ClimbingApp

@MainActor
final class RouteMediaTests: XCTestCase {
    private func fixture(_ name: String, extension ext: String) throws -> URL {
        let bundle = Bundle(for: Self.self)
        return try XCTUnwrap(bundle.url(forResource: name, withExtension: ext) ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    }

    func testPhotoAndVideoFileImportSurviveDatabaseReopening() async throws {
        let photo = try ImportedRouteFile.read(fixture("route-photo", extension: "png"), kind: .photo).draft
        let video = try ImportedRouteFile.read(fixture("route-video", extension: "mov"), kind: .video).draft
        XCTAssertNotNil(UIImage(data: photo.data))
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try Persistence.container(rootDirectory: root)
        let store = ClimbingStore(context: container.mainContext)
        let session = try XCTUnwrap(store.start(date: .now, location: "Media gym", notes: ""))
        let climb = ClimbEntry(grade: "V2")
        XCTAssertTrue(store.save {
            store.context.insert(climb); session.climbs.append(climb)
            for draft in [photo, video] {
                let media = RouteMedia(id: draft.id, kind: draft.kind, filename: draft.filename, contentType: draft.contentType, data: draft.data)
                store.context.insert(media); climb.media.append(media)
            }
        })
        let reopened = try Persistence.container(rootDirectory: root)
        let saved = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<ClimbEntry>()).first)
        XCTAssertEqual(saved.media.count, 2)
        XCTAssertEqual(saved.media.first { $0.kind == .photo }?.data, photo.data)
        let savedVideo = try XCTUnwrap(saved.media.first { $0.kind == .video })
        XCTAssertEqual(savedVideo.data, video.data)
        let playback = root.appending(path: "playback.mov")
        try savedVideo.data.write(to: playback)
        let duration = try await AVURLAsset(url: playback).load(.duration)
        XCTAssertGreaterThan(duration.seconds, 1.5)
    }

    func testDamagedAttachmentBackupDoesNotReplaceSavedMedia() throws {
        let container = try Persistence.container(inMemory: true)
        let store = ClimbingStore(context: container.mainContext)
        let session = try XCTUnwrap(store.start(date: .now, location: "", notes: ""))
        let climb = ClimbEntry(grade: "V1")
        let photo = try ImportedRouteFile.read(fixture("route-photo", extension: "png"), kind: .photo).draft
        XCTAssertTrue(store.save {
            store.context.insert(climb); session.climbs.append(climb)
            let media = RouteMedia(kind: .photo, filename: photo.filename, contentType: photo.contentType, data: photo.data)
            store.context.insert(media); climb.media.append(media)
        })
        var backup = ClimbingBackup(sessions: [session], defaultScale: .vScale)
        backup.sessions[0].climbs[0].media?[0].data = Data([9, 9, 9])
        XCTAssertThrowsError(try backup.validated())
        XCTAssertFalse(store.restore(backup))
        XCTAssertEqual(climb.media.first?.data, photo.data)
    }

    func testMediaAddedLaterToASavedClimbSurvivesReopening() throws {
        let photo = try ImportedRouteFile.read(fixture("route-photo", extension: "png"), kind: .photo).draft
        let video = try ImportedRouteFile.read(fixture("route-video", extension: "mov"), kind: .video).draft
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try Persistence.container(rootDirectory: root)
        let store = ClimbingStore(context: container.mainContext)
        let session = try XCTUnwrap(store.start(date: .now, location: "", notes: ""))
        let climb = ClimbEntry(grade: "V3")
        XCTAssertTrue(store.save { store.context.insert(climb); session.climbs.append(climb) })
        // What the editor does when the saved climb is reopened and media is added.
        let drafts = climb.media.map(\.draft) + [photo, video]
        XCTAssertTrue(store.save { try ClimbEditorView.applyMedia(drafts, to: climb, in: store.context) })
        let reopened = try Persistence.container(rootDirectory: root)
        let saved = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<ClimbEntry>()).first)
        XCTAssertEqual(Set(saved.media.map(\.kind)), [.photo, .video])
        XCTAssertEqual(saved.media.first { $0.kind == .video }?.data, video.data)
    }

    func testCancelledMediaLoadEndsWithAMessageAndNothingAdded() async throws {
        let photo = try ImportedRouteFile.read(fixture("route-photo", extension: "png"), kind: .photo).draft
        let load = Task { await RouteMediaEditor.load([1]) { _ in try await Task.sleep(for: .seconds(30)); return photo } }
        load.cancel()
        let (drafts, message) = await load.value
        XCTAssertTrue(drafts.isEmpty)
        XCTAssertEqual(message, "Adding media was interrupted. Choose it again.")
    }

    func testMediaLoadProblemsArePlainEnglish() async throws {
        let photo = try ImportedRouteFile.read(fixture("route-photo", extension: "png"), kind: .photo).draft
        let loaded = await RouteMediaEditor.load([1, 2]) { _ in photo }
        XCTAssertEqual(loaded.0.count, 2); XCTAssertNil(loaded.1)
        let tooLarge = await RouteMediaEditor.load([1]) { _ in throw BackupError.invalid("Choose a photo or video smaller than 25 MB.") }
        XCTAssertEqual(tooLarge.1, "Choose a photo or video smaller than 25 MB.")
        let unreadable = await RouteMediaEditor.load([1]) { _ in nil }
        XCTAssertEqual(unreadable.1, "This item couldn’t be opened. Try another photo or video.")
        let system = await RouteMediaEditor.load([1]) { _ in throw CocoaError(.fileReadCorruptFile) }
        XCTAssertTrue(system.0.isEmpty)
        XCTAssertEqual(system.1, "This photo or video couldn’t be added. Try another one, or save it to Files and choose it from there.")
    }

    func testOversizedRouteAttachmentIsRejected() {
        let draft = RouteMediaDraft(kind: .photo, filename: "large.png", contentType: "public.png", data: Data(count: RouteMediaDraft.maximumBytes + 1))
        XCTAssertThrowsError(try draft.validate())
    }
}
