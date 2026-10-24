import Foundation
import SwiftData

extension ClimbingStore {
    func defaultGym() throws -> SavedGym? {
        let gyms = try context.fetch(FetchDescriptor<SavedGym>(sortBy: [SortDescriptor(\.name)]))
        return gyms.first(where: \.isDefault) ?? gyms.first
    }

    func saveGym(existing: SavedGym?, name: String, scale: GradeScale, customName: String,
                 grades: [String], isDefault: Bool, colorGuide: String = "") -> SavedGym? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let customName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100, scale != .custom || !customName.isEmpty else {
            errorMessage = "Enter a gym name and, for a custom scale, a scale name."
            return nil
        }
        let gym = existing ?? SavedGym(name: name)
        let success = save {
            let others = try context.fetch(FetchDescriptor<SavedGym>())
            guard !others.contains(where: { $0.id != gym.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw BackupError.invalid("This gym is already saved. Choose it from your gyms list.")
            }
            if existing == nil { context.insert(gym) }
            let makeDefault = isDefault || others.filter { $0.id != gym.id }.isEmpty
            if makeDefault { for other in others { other.isDefault = false } }
            gym.name = name
            gym.colorGuide = colorGuide
            gym.updatedAt = .now
            gym.scaleRaw = scale.rawValue
            gym.customScaleName = scale == .custom ? customName : ""
            gym.customGrades = scale == .custom ? grades : []
            gym.isDefault = makeDefault
            if !makeDefault && !others.contains(where: { $0.id != gym.id && $0.isDefault }) {
                others.filter { $0.id != gym.id }.sorted { $0.name < $1.name }.first?.isDefault = true
            }
        }
        return success ? gym : nil
    }

    func makeDefault(_ gym: SavedGym) {
        save {
            for existing in try context.fetch(FetchDescriptor<SavedGym>()) { existing.isDefault = existing.id == gym.id }
        }
    }

    @discardableResult
    func deleteGym(_ gym: SavedGym) -> Bool {
        save {
            for session in try context.fetch(FetchDescriptor<ClimbingSession>()) where session.gymID == gym.id { session.gymID = nil }
            for climb in try context.fetch(FetchDescriptor<ClimbEntry>()) where climb.gymID == gym.id { climb.gymID = nil }
            context.delete(gym)
            let others = try context.fetch(FetchDescriptor<SavedGym>()).filter { $0.id != gym.id }
            if !others.contains(where: \.isDefault) { others.sorted { $0.name < $1.name }.first?.isDefault = true }
        }
    }
}
