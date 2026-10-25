import Foundation
import Observation

struct FriendSearchQuery: Equatable {
    let username: String
    init?(_ text: String) {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("@") { value.removeFirst() }
        guard value.range(of: "^[a-z0-9_]{2,24}$", options: .regularExpression) != nil else { return nil }
        username = value
    }

    var path: String {
        var components = URLComponents()
        components.path = "/rest/v1/climber_profiles"
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,username,display_name,is_private"),
            URLQueryItem(name: "username", value: "ilike.\(username.replacingOccurrences(of: "_", with: "\\_"))*"),
            URLQueryItem(name: "order", value: "username"), URLQueryItem(name: "limit", value: "30")
        ]
        return components.string!
    }
}

/// Independent from feed loading: cancellation and errors never erase journal or feed state.
@MainActor @Observable
final class FriendSearch {
    enum State: Equatable { case idle, loading, results, failed }
    private(set) var state: State = .idle
    private(set) var results: [SocialProfile] = []
    private var revision = 0

    func search(_ text: String, delay: Duration = .milliseconds(300), fetch: (FriendSearchQuery) async throws -> [SocialProfile]) async {
        revision += 1
        let operation = revision
        results = []
        guard let query = FriendSearchQuery(text) else { state = .idle; return }
        state = .loading
        do {
            try await Task.sleep(for: delay)
            try Task.checkCancellation()
            let matches = try await fetch(query)
            try Task.checkCancellation()
            guard operation == revision else { return }
            results = matches; state = .results
        } catch {
            guard operation == revision, !Task.isCancelled else { return }
            if error is CancellationError { state = .idle }
            else { state = .failed }
        }
    }
}
