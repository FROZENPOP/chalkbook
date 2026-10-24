import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ClimbingStore {
    // SwiftData contexts do not own their container. Keep it alive for the store's lifetime.
    let container: ModelContainer
    let context: ModelContext
    var errorMessage: String?
    var dataRevision = 0

    init(context: ModelContext) {
        self.container = context.container
        self.context = context
    }

    @discardableResult
    func save(_ mutation: () throws -> Void) -> Bool {
        do {
            try mutation()
            try context.save()
            errorMessage = nil
            return true
        } catch {
            context.rollback()
            errorMessage = "Your change could not be saved. Please try again. \(error.localizedDescription)"
            return false
        }
    }

    func start(date: Date, location: String, notes: String, gym: SavedGym? = nil) -> ClimbingSession? {
        do {
            let sessions = try context.fetch(FetchDescriptor<ClimbingSession>())
            if let active = sessions.first(where: { !$0.isComplete }) { return active }
        } catch {
            errorMessage = "Could not check your active session. \(error.localizedDescription)"
            return nil
        }
        let session = ClimbingSession(date: date, location: location.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes)
        session.gymID = gym?.id
        if let gym { session.location = gym.name }
        return save { context.insert(session) } ? session : nil
    }

    func finish(_ session: ClimbingSession) {
        save {
            session.isComplete = true
            session.endedAt = .now
        }
    }

    func record(sent: Bool, on climb: ClimbEntry) {
        guard climb.session?.isComplete == false else { return }
        save {
            let attempt = ClimbAttempt(sequence: (climb.attempts.map(\.sequence).max() ?? 0) + 1, sent: sent)
            context.insert(attempt)
            climb.attempts.append(attempt)
        }
    }

    func undo(on climb: ClimbEntry) {
        guard let attempt = climb.orderedAttempts.last else { return }
        save {
            climb.attempts.removeAll { $0.id == attempt.id }
            context.delete(attempt)
        }
    }

    @discardableResult
    func delete(_ session: ClimbingSession) -> Bool { save { context.delete(session) } }

    @discardableResult
    func delete(_ climb: ClimbEntry) -> Bool {
        save {
            climb.session?.climbs.removeAll { $0.id == climb.id }
            context.delete(climb)
        }
    }

    @discardableResult
    func deleteAll() -> Bool {
        let success = save {
            for session in try context.fetch(FetchDescriptor<ClimbingSession>()) { context.delete(session) }
            for gym in try context.fetch(FetchDescriptor<SavedGym>()) { context.delete(gym) }
        }
        if success { dataRevision += 1 }
        return success
    }
}
