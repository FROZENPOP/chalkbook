import Foundation
import SwiftData

extension ClimbingStore {
    func select(_ climb: ClimbEntry, in session: ClimbingSession) -> Bool {
        save {
            if !session.allClimbs.contains(where: { $0.id == climb.id }) { session.linkedClimbs.append(climb) }
            session.selectedClimbID = climb.id
            session.updatedAt = .now
        }
    }

    func undoLatest(in session: ClimbingSession) {
        guard let attempt = session.recordedAttempts.max(by: { $0.recordedAt < $1.recordedAt }) else { return }
        // Undo is an explicit reversal of logging, not deletion of historical evidence.
        save { attempt.climb?.attempts.removeAll { $0.id == attempt.id }; context.delete(attempt) }
    }

    func removeAttempt(_ attempt: ClimbAttempt) -> Bool {
        save {
            attempt.climb?.historyIncomplete = true
            attempt.climb?.attempts.removeAll { $0.id == attempt.id }
            context.delete(attempt)
        }
    }

    func updateAttempt(_ attempt: ClimbAttempt, sent: Bool, day: String, sequence: Int, precision: String) -> Bool {
        if let id = attempt.effectiveSessionID, let session = try? context.fetch(FetchDescriptor<ClimbingSession>()).first(where: { $0.id == id }),
           let conflict = JournalRules.totals(detailedAttempts: session.recordedAttempts.count, detailedSends: session.recordedAttempts.filter(\.sent).count + (sent ? 1 : 0) - (attempt.sent ? 1 : 0), batches: session.aggregates.map(\.batch)).conflicts.first {
            errorMessage = conflict; return false
        }
        return save {
            guard SessionDay.date(for: day) != nil, sequence > 0 else { throw BackupError.invalid("Choose a valid date and order.") }
            if attempt.climb?.attempts.contains(where: { $0.id != attempt.id && $0.sequence == sequence }) == true {
                throw BackupError.invalid("That attempt order is already in use on this climb. Choose another order.")
            }
            attempt.sent = sent; attempt.daySnapshot = day; attempt.sequence = sequence
            attempt.timePrecision = precision; attempt.updatedAt = .now
        }
    }

    func createRecap(date: Date, gym: SavedGym?, location: String, notes: String, minutes: Int?) -> ClimbingSession? {
        let session = ClimbingSession(date: date, location: gym?.name ?? location, notes: notes)
        session.gymID = gym?.id; session.isComplete = true
        session.durationKnown = minutes != nil
        session.endedAt = date.addingTimeInterval(Double(minutes ?? 0) * 60)
        return save { context.insert(session) } ? session : nil
    }

    func saveAggregate(_ existing: AggregateEntry?, session: ClimbingSession, coverage: ActivityCoverage, attempts: Int?, sends: Int?, label: String) -> Bool {
        if let conflict = JournalRules.totals(detailedAttempts: session.recordedAttempts.count, detailedSends: session.recordedAttempts.filter(\.sent).count, batches: session.aggregates.filter { $0.id != existing?.id }.map(\.batch) + [ActivityBatch(coverage: coverage, attempts: attempts, sends: sends)]).conflicts.first {
            errorMessage = conflict; return false
        }
        return save {
            let entry = existing ?? AggregateEntry(coverage: coverage.rawValue, attempts: attempts, sends: sends)
            if existing == nil { context.insert(entry); session.aggregates.append(entry) }
            entry.coverage = coverage.rawValue; entry.attempts = attempts; entry.sends = sends
            entry.label = label; entry.updatedAt = .now; session.updatedAt = .now
        }
    }

    func setProject(_ climb: ClimbEntry, status: String) -> Bool {
        save { climb.projectRaw = status; climb.updatedAt = .now }
    }
}
