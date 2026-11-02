import SwiftUI
import Observation

struct FriendsFeedContent<Row: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let feed: FriendsFeed
    let refreshing: Bool
    let next: () async -> Void
    let findFriends: () -> Void
    @ViewBuilder var row: (SharedSession) -> Row
    var body: some View {
        // The containing screen supplies the lazy stack. Nesting another lazy stack caches
        // stale row heights when Dynamic Type changes and can clip the recap's text.
        Group {
            if feed.entries.isEmpty && feed.hasLoaded && !feed.loading && feed.errorMessage == nil && !refreshing {
                FriendsEmptyCard(symbol:"figure.climbing",title:"A little encouragement goes a long way.",message:"Shared sessions appear here.") {
                    Button("Add friends",systemImage:"person.badge.plus",action:findFriends).buttonStyle(.borderedProminent)
                }
            }
            ForEach(feed.entries) { entry in
                row(entry).onAppear {
                    if feed.errorMessage == nil && feed.entries.suffix(3).contains(where:{ $0.id == entry.id }) {
                        Task { await next() }
                    }
                }
            }
            if feed.loading {
                SwiftUI.ProgressView(feed.entries.isEmpty ? "Loading activity…" : "Loading more activity…")
                    .font(.subheadline).frame(maxWidth:.infinity,minHeight:44)
                    .accessibilityLabel("Loading friends feed").accessibilityIdentifier("friendsFeedLoading")
            } else if let error=feed.errorMessage {
                VStack(alignment:.leading,spacing:8) {
                    Text(error).font(.subheadline).foregroundStyle(ClimbTheme.secondaryText)
                    Button("Retry loading activity") { Task { await next() } }.buttonStyle(.bordered).tint(Color.primary).frame(minHeight:44)
                        .accessibilityLabel("Retry loading friends feed").accessibilityIdentifier("retryFriendsFeed")
                }
            } else if feed.hasLoaded && !feed.hasMore && !feed.entries.isEmpty {
                Label("You’re all caught up",systemImage:"checkmark.circle").font(.subheadline).foregroundStyle(ClimbTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth:.infinity,minHeight:44).accessibilityElement(children:.combine).accessibilityLabel("End of friends feed").accessibilityIdentifier("friendsFeedEnd")
                    // Refresh this stateless lazy row when text size changes so its measured
                    // height and font update together, without rebuilding feed entries.
                    .id(textSize)
            } else if feed.hasLoaded && feed.hasMore {
                // Accessible/manual fallback; scrolling near the end also loads automatically.
                Button("Load more activity") { Task { await next() } }.buttonStyle(.bordered).tint(Color.primary).frame(minHeight:44)
                    .accessibilityLabel("Load more friends feed activity").disabled(refreshing)
            }
        }
    }
}

#if DEBUG
@MainActor @Observable private final class FeedFixtureReader: FriendsFeedReading {
    private(set) var requests=0
    private var failed=false
    private let owner=UUID(uuidString:"00000000-0000-0000-0000-000000000002")!
    func page(after:FriendsFeedCursor?,limit:Int) async throws -> FriendsFeedPage {
        requests += 1
        if ProcessInfo.processInfo.arguments.contains("--test-empty-feed") { return .init(entries:[]) }
        if after != nil && ProcessInfo.processInfo.arguments.contains("--test-feed-error") && !failed { failed=true;throw SocialError.server }
        let rows=(1...(AccessibilityAuditFixtures.enabled ? 1 : 23)).map { number in
            var entry=SharedSession(session:ClimbingSession(),owner:owner)
            entry.id=UUID(uuidString:String(format:"00000000-0000-0000-0000-%012d",1000-number))!
            entry.session_day="2026-10-30";entry.caption="Fixture recap \(number)";entry.attempts=number;entry.sends=1
            return entry
        }
        return .init(entries:Array(rows.filter { after == nil || $0.id.uuidString < after!.id.uuidString }.prefix(limit)))
    }
}
struct FriendsFeedFixtureView: View {
    @State private var feed=FriendsFeed()
    @State private var reader=FeedFixtureReader()
    var body: some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:16) {
                Text("Page requests: \(reader.requests)").font(.caption)
                FriendsFeedContent(feed:feed,refreshing:false,next:{ await feed.loadNext(reader) },findFriends:{}) { entry in
                    Surface { SharedSessionPreview(entry:entry) }
                }
            }.padding(20)
        }.navigationTitle("Friends").background(ClimbTheme.background)
            .task { await feed.refresh(reader) }
            .refreshable { await feed.refresh(reader) }
    }
}
#endif
