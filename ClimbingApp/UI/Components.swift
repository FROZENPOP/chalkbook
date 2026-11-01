import SwiftUI

enum ClimbTheme {
    // Amber on black, matching the app icon; the light variant is darkened to keep text contrast on white.
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.98, green: 0.69, blue: 0.36, alpha: 1) : UIColor(red: 0.65, green: 0.31, blue: 0.08, alpha: 1)
    })
    static let secondaryText = Color(uiColor: UIColor { traits in
        UIColor(white: traits.userInterfaceStyle == .dark ? 0.78 : 0.34, alpha: 1)
    })
    static let error = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 1, green: 0.55, blue: 0.56, alpha: 1) : UIColor(red: 0.65, green: 0.08, blue: 0.1, alpha: 1)
    })
    static let background = Color(uiColor: .systemGroupedBackground)
}

/// The two chevrons from the app icon (scripts/app_icon.swift), cropped to their own bounds and drawn in the foreground style.
struct AscentMark: View {
    var body: some View {
        Canvas { context, size in
            let scale = size.width / 590
            for (y, opacity) in [(455.0, 0.45), (255.0, 1.0)] {
                var chevron = Path()
                chevron.move(to: CGPoint(x: 55 * scale, y: y * scale))
                chevron.addLine(to: CGPoint(x: 295 * scale, y: (y - 200) * scale))
                chevron.addLine(to: CGPoint(x: 535 * scale, y: y * scale))
                context.opacity = opacity
                context.stroke(chevron, with: .foreground, style: StrokeStyle(lineWidth: 110 * scale, lineCap: .round, lineJoin: .round))
            }
        }
        .aspectRatio(590 / 510, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The app icon itself, with its fixed colors, for places that present the brand.
struct AscentIcon: View {
    let size: CGFloat
    var body: some View {
        AscentMark()
            .foregroundStyle(Color(red: 0.98, green: 0.69, blue: 0.36))
            .frame(width: size * 590 / 1024)
            .offset(y: -size * 48 / 1024)
            .frame(width: size, height: size)
            .background(Color(red: 0.043, green: 0.051, blue: 0.047), in: .rect(cornerRadius: size * 0.225))
            .overlay { RoundedRectangle(cornerRadius: size * 0.225).stroke(.white.opacity(0.1)) }
    }
}

extension Int {
    /// "1 attempt", "2 attempts".
    func counted(_ noun: String) -> String { "\(self) \(noun)\(self == 1 ? "" : "s")" }
}

struct SaveErrorBanner: View {
    @Environment(ClimbingStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if let message = store.errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Label("Couldn’t save", systemImage: "exclamationmark.triangle.fill").font(.headline)
                    Spacer(minLength: 8)
                    Button { store.errorMessage = nil } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }.accessibilityLabel("Dismiss save error")
                }
                if typeSize.isAccessibilitySize {
                    DisclosureGroup("Details and retry") {
                        ScrollView { details(message) }.frame(maxHeight: 180)
                    }
                } else { details(message) }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .accessibilityElement(children: .contain)
        }
    }
    private func details(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Text("Your input is kept. Retry Save or the logging action after resolving the issue.")
                .font(.caption).foregroundStyle(ClimbTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
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
            Text(label).font(.caption).foregroundStyle(ClimbTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct SessionRow: View {
    let session: ClimbingSession
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: session.isComplete ? "mountain.2.fill" : "figure.climbing").accessibilityHidden(true)
                .font(.title2).foregroundStyle(ClimbTheme.accent)
                .frame(width: 48, height: 48)
                .background(ClimbTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(session.title).font(.headline)
                Text(SessionDay.label(for: session.day)).font(.subheadline).foregroundStyle(ClimbTheme.secondaryText)
                if !session.isComplete { Text("In progress").font(.caption.weight(.semibold)).foregroundStyle(ClimbTheme.accent) }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                Text("\(session.completedClimbs)").font(.title3.bold()).monospacedDigit()
                Text("climbs sent").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
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
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(ClimbTheme.secondaryText).accessibilityHidden(true)
            Text(title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            Text(message).font(.body).foregroundStyle(ClimbTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct JournalMetrics: View {
    @Environment(\.dynamicTypeSize) private var size
    let first: String
    let firstLabel: String
    let second: String
    let secondLabel: String
    let third: String
    let thirdLabel: String
    var body: some View {
        let layout = size.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout { Metric(value: first, label: firstLabel); Metric(value: second, label: secondLabel); Metric(value: third, label: thirdLabel) }
    }
}

/// Keep the hit region inside the button label, rather than just enlarging its outer view.
private struct AccessibleToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.labelStyle(.iconOnly).foregroundStyle(.primary)
            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    func accessibleToolbarAction() -> some View {
        self.buttonStyle(AccessibleToolbarButtonStyle()).tint(.primary)
    }
}
