import SwiftUI

struct RemovalStatusView: View {
    let outbox: RemovalOutbox
    let retry: () async -> Void
    var body: some View {
        if !outbox.entries.isEmpty || outbox.storageError != nil {
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    if !outbox.entries.isEmpty {
                        Label("\(outbox.entries.count) \(outbox.entries.count == 1 ? "removal" : "removals") waiting to sync", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline).accessibilityIdentifier("pendingRemovalCount")
                        Text("Removed on this device. Friends may still see the shared content until it syncs.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let message = outbox.storageError ?? outbox.lastError {
                        Text(message).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if outbox.draining { SwiftUI.ProgressView("Syncing removals…").accessibilityLabel("Syncing pending removals") }
                    Button("Retry now") { Task { await retry() } }.buttonStyle(.bordered).tint(Color.primary)
                        .frame(minHeight: 44).disabled(outbox.draining)
                        .accessibilityLabel("Retry pending removals now").accessibilityIdentifier("retryRemovals")
                }
            }
        }
    }
}

#if DEBUG
struct RemovalOutboxFixtureView: View {
    @State private var outbox: RemovalOutbox
    private let owner = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let key = String(repeating: "a", count: 64)
    init() {
        // No real account, network, or production queue is accessed by this fixture.
        let directory = URL.temporaryDirectory.appending(path: "RemovalFixture-\(UUID().uuidString)")
        let queue = RemovalOutbox(accountKey: Self.key, directory: directory)
        try? queue.bind(owner: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, accountKey: Self.key)
        try? queue.enqueue(contentID: UUID(), kind: .sessionSnapshot)
        _outbox = State(initialValue: queue)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RemovalStatusView(outbox: outbox) {
                    await outbox.retry(owner: owner, accountKey: Self.key, force: true) { _ in }
                }
                if outbox.entries.isEmpty { Text("Removals synced").accessibilityIdentifier("removalsSynced") }
            }.padding(20)
        }.navigationTitle("Friends").background(ClimbTheme.background)
    }
}
#endif
