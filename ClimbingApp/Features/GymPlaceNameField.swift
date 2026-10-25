import MapKit
import Observation
import SwiftUI

struct GymPlaceSuggestion: Identifiable {
    let name: String
    let address: String
    var id: String { name + "\n" + address }
}

@MainActor
@Observable
final class GymPlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var suggestions: [GymPlaceSuggestion] = []
    private(set) var loading = false
    private(set) var message: String?
    @ObservationIgnored private var completer: MKLocalSearchCompleter?

    func clear() {
        completer?.delegate = nil
        completer?.cancel()
        completer = nil
        suggestions = []; loading = false; message = nil
    }

    func search(_ query: String) {
        clear()
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 else { return }
        let completer = MKLocalSearchCompleter()
        self.completer = completer
        completer.resultTypes = .pointOfInterest
        completer.delegate = self
        loading = true
        completer.queryFragment = query
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor [weak self] in
            guard let self, self.completer === completer else { return }
            var seen = Set<String>()
            self.suggestions = completer.results.map { GymPlaceSuggestion(name: $0.title, address: $0.subtitle) }
                .filter { seen.insert($0.id).inserted }.prefix(6).map { $0 }
            self.loading = false
            self.message = self.suggestions.isEmpty ? "No matching places. Add a city to your search, or enter the gym manually." : nil
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.completer === completer else { return }
            self.suggestions = []; self.loading = false
            self.message = "Place search is unavailable. You can still enter a gym name and address manually."
        }
    }
}

struct GymPlaceNameField: View {
    @Binding var name: String
    @Binding var address: String
    @State private var search = GymPlaceSearch()
    @State private var selectedName: String?
    @State private var selectedAddress: String?
    @FocusState private var focused: Bool
    private var query: String { focused && name != selectedName ? name.trimmingCharacters(in: .whitespacesAndNewlines) : "" }

    var body: some View {
        TextField("Gym name", text: $name)
            .textInputAutocapitalization(.words).autocorrectionDisabled()
            .focused($focused).accessibilityIdentifier("gymName")
            .submitLabel(.done).onSubmit { focused = false }
            .onChange(of: name) { _, newName in
                if let selectedName, newName != selectedName {
                    if address == selectedAddress { address = "" }
                    self.selectedName = nil; selectedAddress = nil
                }
            }
            .onChange(of: query) { _, _ in search.clear() }
            .task(id: query) {
                let query = query
                guard query.count >= 3 else { return }
                do { try await Task.sleep(for: .milliseconds(300)); try Task.checkCancellation() }
                catch { return }
                search.search(query)
            }
        if focused && query.count < 3 {
            Text("Type a gym name and city to search Apple Maps, or enter a gym manually.").font(.caption).foregroundStyle(.secondary)
        }
        if search.loading { SwiftUI.ProgressView("Finding gyms…").accessibilityIdentifier("gymPlaceLoading") }
        ForEach(search.suggestions) { place in
            Button {
                selectedName = place.name; selectedAddress = place.address
                name = place.name; address = place.address
                focused = false
                search.clear()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "mappin.circle").font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.name).font(.body).foregroundStyle(.primary)
                        if !place.address.isEmpty { Text(place.address).font(.caption).foregroundStyle(.secondary) }
                    }
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.borderless).accessibilityIdentifier("gymPlaceSuggestion")
        }
        if !search.suggestions.isEmpty { Text("Suggestions from Apple Maps").font(.caption).foregroundStyle(.secondary) }
        if let message = search.message { Text(message).font(.caption).foregroundStyle(.secondary) }
    }
}
