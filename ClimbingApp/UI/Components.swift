import SwiftUI

enum ClimbTheme {
    static let forest = Color(red: 0.12, green: 0.36, blue: 0.29)
    static let amber = Color(red: 0.65, green: 0.31, blue: 0.08)
    static let background = Color(uiColor: .systemGroupedBackground)
}

struct SaveErrorBanner: View {
    @Environment(ClimbingStore.self) private var store

    var body: some View {
        if let message = store.errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Label("Couldn’t save", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                Text(message).font(.subheadline)
                Button("Dismiss") { store.errorMessage = nil }
                    .frame(minHeight: 44)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .accessibilityElement(children: .contain)
        }
    }
}

struct Surface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}

struct Metric: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct SessionRow: View {
    let session: ClimbingSession
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: session.isComplete ? "mountain.2.fill" : "figure.climbing")
                .font(.title2).foregroundStyle(ClimbTheme.forest)
                .frame(width: 48, height: 48)
                .background(ClimbTheme.forest.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(session.title).font(.headline)
                Text(SessionDay.label(for: session.day)).font(.subheadline).foregroundStyle(.secondary)
                if !session.isComplete { Text("In progress").font(.caption.weight(.semibold)).foregroundStyle(ClimbTheme.forest) }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                Text("\(session.completedClimbs)").font(.title3.bold()).monospacedDigit()
                Text("climbs sent").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct EmptyState: View {
    let title: String
    let symbol: String
    let message: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
            .padding(.vertical, 24)
    }
}
