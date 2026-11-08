import Foundation
import Observation

struct RemovalHTTPError: LocalizedError {
    let status: Int
    var missingContent = false
    /// The Postgres error code and message the server sent, when it sent one.
    var code: String? = nil
    var serverMessage: String? = nil
    var errorDescription: String? {
        if let serverMessage, let known = Self.reasons[serverMessage] { return known }
        switch code {
        case "23514":
            // The check constraint's name says which rule failed.
            let rule = serverMessage ?? ""
            if rule.contains("_plain") { return "This has hidden or formatting characters. Retype it without them." }
            if rule.contains("not_staff") { return "Display names can’t include “Chalkbook”." }
            if rule.contains("not_reserved") { return "That username is reserved. Choose another one." }
            if rule.contains("_visible") { return "Add some visible text and try again." }
            if rule.contains("avatar") { return "This profile photo couldn’t be used. Choose another photo." }
            return "Part of this is too long. Shorten it and try again."
        case "23505": return "This is already saved. Refresh and try again."
        // A post points at the climber's Friends profile, so without one it has nothing to attach to.
        case "23503" where serverMessage?.contains("shared_sessions_owner_id_fkey") == true: return "Set up your Friends profile in the Friends tab, then try again."
        default: break
        }
        switch status {
        case 401: return "Your Friends sign-in has expired. Sign out and sign in again, then retry."
        case 403: return "Friends didn’t allow this for your account. Sign out and sign in again, then retry."
        case 404, 410: return "This is no longer available. It may have been deleted or made private."
        case 409: return "This conflicts with something already saved. Refresh and try again."
        case 413: return "This is too large to send. Use fewer or smaller photos and try again."
        case 429: return "Too many requests in a short time. Wait a minute and try again."
        case 500...: return "The Friends service is having trouble right now. Try again in a few minutes. No successful save has been confirmed."
        default: return SocialError.server.localizedDescription
        }
    }

    // The reasons the Friends database gives when it refuses a request (raise exception in supabase/migrations).
    private static let reasons = [
        "Sign in required": "Your Friends sign-in has expired. Sign out and sign in again, then retry.",
        "Invalid photo selection": "Choose up to 3 photos and try again.",
        "Invalid photo fields": "One of these photos couldn’t be read. Choose it again or pick another photo.",
        "Invalid photo data": "One of these photos couldn’t be read. Choose it again or pick another photo.",
        "Unavailable": "This is no longer available. It may have been deleted or made private.",
        "Entry unavailable": "This post is no longer available. It may have been deleted or made private.",
        "Content unavailable": "This post is no longer available. It may have been deleted or made private.",
        "Comment unavailable": "This comment is no longer available. It may have been deleted.",
        "Climber unavailable": "This climber is no longer available.",
        "Too many reports today": "You’ve sent 20 reports today, the daily limit. You can report again tomorrow.",
        "Too many comments, try again in a minute": "You’re commenting too quickly. Wait a minute and try again.",
        "Shared session limit reached": "You’ve shared 2,000 sessions, the limit. Delete an older shared session to share this one.",
        "Gym limit reached": "You’ve added 200 gyms, the limit.",
        "Wall limit reached": "You’ve added 2,000 walls, the limit.",
        "Route limit reached": "You’ve added 20,000 routes, the limit.",
        "Unknown action": "Chalkbook sent a request the Friends service didn’t accept. Update the app and try again.",
        "Setting required": "Chalkbook sent a request the Friends service didn’t accept. Update the app and try again.",
        "Invalid session day": "This session’s date couldn’t be shared. Check the date and try again.",
    ]
}

struct PendingRemoval: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case sessionSnapshot, socialProfile }
    let id: UUID
    // Older/offline installations may not yet know their Supabase UUID. Bind only after verified sign-in.
    var ownerID: UUID?
    var contentID: UUID
    let kind: Kind
    let createdAt: Date
    var attemptCount = 0
    var lastError: String?
    var nextAttemptAt = Date.distantPast
    var needsAuthorization = false
}

/// Small protected JSON sidecar, like ProfileStore; outside journal backups and SwiftData migrations.
/// The provider storage key scopes unresolved intents; a verified Supabase UUID scopes execution.
@MainActor @Observable final class RemovalOutbox {
    private struct Archive: Codable {
        var version = 1
        let accountKey: String
        var ownerID: UUID?
        var entries: [PendingRemoval] = []
    }
    let accountKey: String
    private let file: URL
    private var archive: Archive
    private(set) var storageError: String?
    private(set) var draining = false
    var entries: [PendingRemoval] { archive.entries }
    var ownerID: UUID? { archive.ownerID }
    var lastError: String? { entries.first(where: { $0.lastError != nil })?.lastError }
    private let validKey: Bool

    init(accountKey: String, directory: URL? = nil) {
        self.accountKey = accountKey
        validKey = accountKey.count == 64 && accountKey.allSatisfy { "0123456789abcdef".contains($0) }
        file = (directory ?? URL.applicationSupportDirectory.appending(path: "RemovalOutboxes"))
            .appending(path: validKey ? accountKey : "guest").appending(path: "removals.json")
        archive = Archive(accountKey: accountKey)
        if validKey { reload() }
    }

    func reload() {
        guard validKey else { return }
        do {
            guard FileManager.default.fileExists(atPath: file.path) else { storageError = nil; return }
            let data = try Data(contentsOf: file)
            guard data.count <= 10_000_000 else { throw SocialError.server }
            let loaded = try JSONDecoder().decode(Archive.self, from: data)
            guard loaded.version == 1, loaded.accountKey == accountKey,
                  Set(loaded.entries.map(\.id)).count == loaded.entries.count,
                  loaded.entries.allSatisfy({ $0.attemptCount >= 0 && ($0.ownerID == nil || $0.ownerID == loaded.ownerID) }) else { throw SocialError.server }
            archive = loaded; storageError = nil
        } catch { storageError = "Pending removals couldn’t be opened. The saved file was kept. Retry before deleting or unsharing." }
    }

    private func save(_ next: Archive) throws {
        guard validKey, storageError == nil else { throw SocialError.signIn }
        do {
            // Account-root replacement can leave an old request finishing while a new store has
            // enqueued work. Apply this mutation to the latest file instead of overwriting it.
            // All read/merge/write operations are synchronous on MainActor (no intervening await).
            var merged = next
            if FileManager.default.fileExists(atPath: file.path) {
                let data = try Data(contentsOf: file)
                guard data.count <= 10_000_000 else { throw SocialError.server }
                var latest = try JSONDecoder().decode(Archive.self, from: data)
                guard latest.version == 1, latest.accountKey == accountKey,
                      latest.ownerID == nil || next.ownerID == nil || latest.ownerID == next.ownerID else { throw SocialError.signIn }
                latest.ownerID = next.ownerID ?? latest.ownerID
                let old = Dictionary(archive.entries.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
                let nextIDs = Set(next.entries.map(\.id))
                latest.entries.removeAll { old[$0.id] != nil && !nextIDs.contains($0.id) }
                for entry in next.entries where old[entry.id] != entry {
                    if let i = latest.entries.firstIndex(where: { $0.id == entry.id }) { latest.entries[i] = entry }
                    else if old[entry.id] == nil { latest.entries.append(entry) }
                    // A concurrent confirmation already removed an old entry: never resurrect it.
                }
                if let owner = latest.ownerID {
                    for i in latest.entries.indices where latest.entries[i].ownerID == nil {
                        latest.entries[i].ownerID = owner
                        if latest.entries[i].kind == .socialProfile { latest.entries[i].contentID = owner }
                    }
                }
                merged = latest
            }
            let data = try JSONEncoder().encode(merged)
            guard data.count <= 10_000_000 else { throw SocialError.server }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            archive = merged
        } catch {
            storageError = "Pending removals couldn’t be saved. Previously saved removal intents were kept. Check available storage and retry."
            throw error
        }
    }

    func bind(owner: UUID, accountKey: String) throws {
        guard self.accountKey == accountKey, archive.ownerID == nil || archive.ownerID == owner else { throw SocialError.signIn }
        guard archive.ownerID != owner || entries.contains(where: { $0.ownerID == nil }) else { return }
        var next = archive; next.ownerID = owner
        for i in next.entries.indices {
            next.entries[i].ownerID = owner
            if next.entries[i].kind == .socialProfile { next.entries[i].contentID = owner }
        }
        try save(next)
    }

    /// The server account is gone, so its removals are moot, and its old user ID must not
    /// block the next sign-in, which gets a new one.
    func clearAfterAccountDeletion() {
        try? FileManager.default.removeItem(at: file)
        archive = Archive(accountKey: accountKey); storageError = nil
    }

    func enqueue(contentID: UUID, kind: PendingRemoval.Kind, now: Date = .now) throws {
        guard !entries.contains(where: { ($0.contentID == contentID || kind == .socialProfile) && $0.kind == kind }) else { return }
        var next = archive
        next.entries.append(.init(id: UUID(), ownerID: ownerID, contentID: contentID, kind: kind, createdAt: now))
        try save(next) // Never acknowledge a local delete until its intent is durable.
    }

    func hides(_ entry: SharedSession) -> Bool {
        entries.contains { removal in
            (removal.ownerID == nil || removal.ownerID == entry.owner_id) &&
            (removal.kind == .socialProfile || removal.contentID == entry.source_session_id)
        }
    }
    var removingProfile: Bool { entries.contains { $0.kind == .socialProfile } }
    func contains(sessionID: UUID) -> Bool { removingProfile || entries.contains { $0.kind == .sessionSnapshot && $0.contentID == sessionID } }

    func hasDue(force: Bool = false, now: Date = .now) -> Bool {
        guard force || !entries.contains(where: { $0.needsAuthorization }) else { return false }
        return entries.contains { force || $0.nextAttemptAt <= now }
    }

    /// A token refresh can fail before the verified owner is known on an upgraded installation.
    /// Record that failure without running any content RPC or guessing an owner UUID.
    func connectionFailed(accountKey: String?, error: Error, now: Date = .now) {
        guard accountKey == self.accountKey, storageError == nil, var first = entries.first else { return }
        first.attemptCount = min(first.attemptCount + 1, 1_000_000)
        let status = (error as? RemovalHTTPError)?.status
        first.needsAuthorization = status == 401 || status == 403
        if case SocialError.signIn = error { first.needsAuthorization = true }
        first.lastError = first.needsAuthorization ? "Access needs attention. Sign in again or review access, then retry." : "Couldn’t connect. The removal is saved and will retry later."
        first.nextAttemptAt = now.addingTimeInterval(first.needsAuthorization ? 3600 : min(21_600, 30 * pow(2, Double(min(first.attemptCount - 1, 10)))))
        var next = archive; next.entries[0] = first
        do { try save(next) } catch { /* Visible storageError retains the last durable intent. */ }
    }

    /// At most 10 attempts per trigger. Network failures back off 30s…6h; authorization pauses
    /// automatic attempts until explicit Retry now. Manual retry bypasses the date, never identity.
    func retry(owner: UUID?, accountKey: String?, force: Bool = false, now: Date = .now,
               send: (PendingRemoval) async throws -> Void) async {
        guard !draining, storageError == nil, hasDue(force: force, now: now), let owner, accountKey == self.accountKey, owner == ownerID else { return }
        draining = true; defer { draining = false }
        let candidates = entries.filter { $0.ownerID == owner && (force || (!$0.needsAuthorization && $0.nextAttemptAt <= now)) }.prefix(10)
        for candidate in candidates {
            guard var current = entries.first(where: { $0.id == candidate.id }) else { continue }
            current.attemptCount = min(current.attemptCount + 1, 1_000_000)
            current.nextAttemptAt = now.addingTimeInterval(min(21_600, 30 * pow(2, Double(min(current.attemptCount - 1, 10)))))
            do {
                var next = archive
                if let i = next.entries.firstIndex(where: { $0.id == current.id }) { next.entries[i] = current }
                try save(next) // Persist backoff before the network call, including crash/termination cases.
                do { try await send(current) }
                catch let error as RemovalHTTPError where error.missingContent { /* Already absent is success. Missing RPCs never set this flag. */ }
                var completed = archive
                completed.entries.removeAll { $0.id == current.id || (current.kind == .socialProfile && $0.ownerID == owner) }
                try save(completed)
            } catch {
                guard storageError == nil else { break }
                let status = (error as? RemovalHTTPError)?.status
                let signedOut: Bool
                if case SocialError.signIn = error { signedOut = true } else { signedOut = false }
                current.needsAuthorization = status == 401 || status == 403 || signedOut
                current.lastError = current.needsAuthorization
                    ? "Access needs attention. Sign in again or review access, then retry."
                    : "Couldn’t reach the server. The removal is saved and will retry later."
                if current.needsAuthorization { current.nextAttemptAt = now.addingTimeInterval(3600) }
                var failed = archive
                if let i = failed.entries.firstIndex(where: { $0.id == current.id }) { failed.entries[i] = current }
                do { try save(failed) } catch { break }
                break // An outage/permission error should not generate one request per queued item.
            }
        }
    }
}
