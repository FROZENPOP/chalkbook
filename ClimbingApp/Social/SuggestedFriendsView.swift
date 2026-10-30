import SwiftUI

struct SuggestedFriendsSection: View {
    let state: FriendSuggestions
    let service: any FriendSuggestionServing
    let excluded: Set<UUID>
    let blocked: Set<UUID>
    let viewer: UUID
    @Environment(\.dynamicTypeSize) private var textSize
    private var actionsLayout: AnyLayout {
        textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:8)) : AnyLayout(HStackLayout(spacing:12))
    }
    private var visible: [FriendSuggestion] {
        state.items.filter { !blocked.contains($0.id) && (!excluded.contains($0.id) || state.sent.contains($0.id)) }
    }
    var body: some View {
        if !visible.isEmpty {
            VStack(alignment:.leading,spacing:12) {
                Text("Suggested friends").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                ForEach(visible) { person in
                    Surface {
                        VStack(alignment:.leading,spacing:12) {
                            HStack(alignment:.top,spacing:12) {
                                FriendInitials(name:person.display_name).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                                VStack(alignment:.leading,spacing:4) {
                                    Text(person.display_name).font(.headline)
                                    Text(person.mutualSummary).font(.subheadline).foregroundStyle(.secondary)
                                }.frame(maxWidth:.infinity,alignment:.leading)
                            }.accessibilityElement(children:.combine)
                                .accessibilityLabel("\(person.display_name), \(person.mutualSummary)")
                            actionsLayout {
                                Button { Task { await state.act(person.id,dismiss:false,service:service) } } label: {
                                    Label(state.sent.contains(person.id) ? "Sent" : "Add",systemImage:state.sent.contains(person.id) ? "checkmark" : "person.badge.plus")
                                }.buttonStyle(.borderedProminent).frame(minHeight:44)
                                    .accessibilityLabel(state.sent.contains(person.id) ? "Request sent to \(person.display_name)" : "Add \(person.display_name)")
                                    .accessibilityIdentifier("suggestionAdd-\(person.id.uuidString)")
                                Button("Not now") { Task { await state.act(person.id,dismiss:true,service:service) } }
                                    .frame(minHeight:44).accessibilityLabel("Not now, hide \(person.display_name)")
                                    .accessibilityIdentifier("suggestionDismiss-\(person.id.uuidString)")
                                if state.working.contains(person.id) { SwiftUI.ProgressView().accessibilityLabel("Saving friend suggestion") }
                            }.disabled(state.working.contains(person.id) || state.sent.contains(person.id))
                            if let message=state.rowErrors[person.id] {
                                Text(message).font(.subheadline).foregroundStyle(.red)
                                Button("Retry") { Task { await state.act(person.id,dismiss:state.retryDismiss.contains(person.id),service:service) } }
                                    .frame(minHeight:44).disabled(state.working.contains(person.id))
                                    .accessibilityLabel("Retry for \(person.display_name)")
                            }
                        }
                    }
                }
                if state.hasMore {
                    Button("More suggestions") { Task { await state.load(service,owner:viewer,excluding:excluded.union(blocked),more:true) } }
                        .frame(minHeight:44).disabled(state.loading)
                }
            }
        }
        if let error=state.errorMessage {
            VStack(alignment:.leading,spacing:8) {
                Text(error).font(.subheadline).foregroundStyle(.secondary)
                Button("Retry friend suggestions") { Task { await state.load(service,owner:viewer,excluding:excluded.union(blocked)) } }.frame(minHeight:44)
            }
        }
    }
}

#if DEBUG
/// Only reachable with both UI-test arguments. No auth, backend or real people are used.
@MainActor private final class SuggestionFixtureService: FriendSuggestionServing {
    static let viewer=UUID(uuidString:"00000000-0000-0000-0000-000000000001")!
    private var rows=[FriendSuggestion(id:UUID(uuidString:"00000000-0000-0000-0000-000000000003")!,display_name:"Alex Boulder",avatar_base64:nil,mutual_count:2,mutual_names:["Sam","Jo"]),
                      FriendSuggestion(id:UUID(uuidString:"00000000-0000-0000-0000-000000000004")!,display_name:"Casey Slab",avatar_base64:nil,mutual_count:1,mutual_names:["Sam"])]
    private var failed=false
    func fetch(limit:Int,offset:Int) async throws -> [FriendSuggestion] {
        if ProcessInfo.processInfo.arguments.contains("--test-empty-suggestions") { return [] }
        return Array(rows.dropFirst(offset).prefix(limit))
    }
    func dismiss(_ id:UUID) async throws { rows.removeAll { $0.id == id } }
    func add(_ id:UUID) async throws {
        if ProcessInfo.processInfo.arguments.contains("--test-suggestion-error") && !failed { failed=true;throw SocialError.server }
        rows.removeAll { $0.id == id }
    }
    func discovery() async throws -> Bool { true }
    func setDiscovery(_ enabled:Bool) async throws {}
}
struct SuggestedFriendsFixtureView: View {
    @State private var state=FriendSuggestions()
    @State private var service=SuggestionFixtureService()
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text("Your climbing circle").font(.title2.bold())
                SuggestedFriendsSection(state:state,service:service,excluded:[],blocked:[],viewer:SuggestionFixtureService.viewer)
                Text("Activity").font(.headline)
            }.padding(20)
        }.navigationTitle("Friends").background(ClimbTheme.background)
            .task { await state.load(service,owner:SuggestionFixtureService.viewer) }
    }
}
#endif
