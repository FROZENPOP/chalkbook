import Foundation
import Observation

struct FriendSearchQuery: Equatable {
    let term: String
    init?(_ text: String) {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("@") { value.removeFirst() }
        guard (2...60).contains(value.count), !value.unicodeScalars.contains(where:{ CharacterSet.controlCharacters.contains($0) }) else { return nil }
        term = value
    }

    var path: String {
        "/rest/v1/rpc/search_climbers"
    }
    var rpcValues: [String:Any] { ["search_text":term] }
}

/// Independent from feed loading: cancellation and errors never erase journal or feed state.
@MainActor @Observable
final class FriendSearch {
    enum State: Equatable { case idle, loading, results, failed }
    private(set) var state: State = .idle
    private(set) var results: [SocialProfile] = []
    private(set) var errorMessage: String?
    private var revision = 0

    func search(_ text: String, delay: Duration = .milliseconds(300), fetch: (FriendSearchQuery) async throws -> [SocialProfile]) async {
        revision += 1
        let operation = revision
        results = [];errorMessage=nil
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
            else { errorMessage=SocialError.message(for: error);state = .failed }
        }
    }
}
