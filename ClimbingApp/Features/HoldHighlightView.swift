import SwiftUI

struct HoldHighlightView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: RouteMediaDraft
    let save: (String) -> Bool
    @State private var selection: HoldHighlightSettings?
    @State private var tolerance: Double = 0.35
    @State private var original: UIImage?
    @State private var includeMore = false
    @State private var showOriginal = false
    @State private var image: UIImage?
    @State private var processing = true
    @State private var message: String?
    @State private var retry = 0
    @State private var loadRetry = 0
    @State private var renderSucceeded = false
    @State private var document: RouteAnnotationDocument?

    private var request: Request { Request(selection: selection, retry: retry, ready: document != nil) }
    private struct Request: Equatable { let selection: HoldHighlightSettings?; let retry: Int; let ready: Bool }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tap a hold in your climb").font(.headline)
                    if includeMore { Text("Tap another hold to include it.").font(.subheadline).foregroundStyle(ClimbTheme.secondaryText) }
                    if let displayed = showOriginal ? original : image {
                        RouteMarkupImage(image: displayed, strokes: document?.strokes ?? [])
                            .overlay {
                                HighlightSelectionOverlay(points: selection?.selections ?? [], imageSize: displayed.size, canSelect: !showOriginal, choose: choose, remove: remove)
                            }
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selection?.selections)
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("Route photo. Tap a hold to select its color.")
                            .accessibilityIdentifier("holdHighlightCanvas")
                            .accessibilityAction(named: "Select center hold") { choose(RoutePoint(x: 0.5, y: 0.5)) }
                            .accessibilityValue(showOriginal ? "Original photo" : "\(selection?.selections.count ?? 0) holds selected")
                    }
                    if processing { SwiftUI.ProgressView("Processing photo…").accessibilityIdentifier("highlightProcessing") }
                    if let message {
                        Text(message).foregroundStyle(ClimbTheme.error).accessibilityIdentifier("highlightError")
                        Button("Retry processing") { if document == nil { loadRetry += 1 } else { retry += 1 } }.frame(minHeight: 44)
                    }
                    Text(selectionLabel)
                        .font(.headline).accessibilityIdentifier("highlightSelection")
                    Picker("Photo comparison", selection: $showOriginal) {
                        Text("Highlighted").tag(false); Text("Original").tag(true)
                    }.pickerStyle(.segmented).accessibilityIdentifier("highlightComparison")
                        .accessibilityHint("Compare views without changing saved selections")
                    Toggle("Show highlight", isOn: Binding(get: { selection?.isEnabled ?? false }, set: { selection?.isEnabled = $0 }))
                        .disabled(selection == nil).accessibilityIdentifier("enableHoldHighlight")
                    Button(includeMore ? "Tap another hold…" : "Include more holds", systemImage: "plus.circle") {
                        includeMore.toggle(); showOriginal = false
                    }.frame(minHeight: 44).disabled(selection == nil || (selection?.selections.count ?? 0) >= 64)
                        .accessibilityIdentifier("includeMoreHolds").accessibilityValue(includeMore ? "Ready to add" : "Off")
                        .accessibilityHint("Your next tap adds a selection instead of replacing it")
                    Text("Color reach").font(.headline)
                    Slider(value: $tolerance, in: 0...1, step: 0.01)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Color reach")
                        .accessibilityValue("\(Int(tolerance * 100)) percent")
                        .accessibilityHint("Higher values include more shades of your selected holds")
                        .accessibilityIdentifier("highlightTolerance")
                        .disabled(selection == nil)
                        .onChange(of: tolerance) { _, value in selection?.tolerance = value }
                    Text("\(Int(tolerance * 100))% · Include fewer or more shades.").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                    Button("Reset to original", systemImage: "arrow.counterclockwise") {
                        selection = nil; includeMore = false; showOriginal = false
                    }.frame(minHeight: 44).disabled(selection == nil).accessibilityIdentifier("resetHoldHighlight")
                    Text("For a cleaner match, tap colored material away from chalk or glare.").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                    Text("The original photo and private markup are preserved. Done saves this view; Cancel keeps your previous settings.").font(.caption).foregroundStyle(ClimbTheme.secondaryText)
                }.padding(20)
            }
            .background(ClimbTheme.background)
            .navigationTitle(typeSize.isAccessibilitySize ? "Highlight" : "Highlight holds").navigationBarTitleDisplayMode(.inline)
            // Photos can scroll beneath the native title; keep its contrast independent of them.
            .toolbarBackground(ClimbTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() }.accessibleToolbarAction() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        guard var document else { return }
                        document.highlight = selection
                        do {
                            if save(try RouteAnnotations.encode(document)) { dismiss() }
                            else { message = "Your highlight couldn’t be saved. Try Done again. Your selection is still here." }
                        } catch { message = error.localizedDescription }
                    }.disabled(processing || image == nil || document == nil || !renderSucceeded)
                        .accessibleToolbarAction().accessibilityIdentifier("saveHoldHighlight")
                }
            }
            .task(id: loadRetry) {
                processing = true; message = nil
                do {
                    let saved = try RouteAnnotations.document(item.annotationJSON)
                    let decoded = try await HoldHighlight.process(data: item.data, settings: nil)
                    try Task.checkCancellation()
                    original = UIImage(cgImage: decoded); image = original
                    tolerance = saved.highlight?.tolerance ?? 0.35
                    selection = saved.highlight
                    document = saved
                } catch is CancellationError { }
                catch { message = "The photo or its saved settings couldn’t be opened. Your original and saved settings have been kept. \(error.localizedDescription)"; processing = false }
            }
            .task(id: request) {
                guard document != nil else { return }
                processing = true; renderSucceeded = false; message = nil
                do {
                    // Coalesce slider changes and cancel obsolete renders.
                    try await Task.sleep(for: .milliseconds(100))
                    let rendered = try await HoldHighlight.process(data: item.data, settings: selection)
                    try Task.checkCancellation()
                    image = UIImage(cgImage: rendered); processing = false; renderSucceeded = true
                } catch is CancellationError { }
                catch { message = error.localizedDescription; processing = false }
            }
        }.tint(.primary)
            .sensoryFeedback(.selection, trigger: selection?.selections.count ?? 0)
    }
    private var selectionLabel: String {
        guard let count = selection?.selections.count else { return "No color selected" }
        return "\(count) hold\(count == 1 ? "" : "s") selected"
    }
    private func choose(_ point: RoutePoint) {
        guard !showOriginal else { return }
        if includeMore, var settings = selection {
            guard settings.selections.count < 64 else { return }
            settings.selections.append(point); settings.isEnabled = true; selection = settings
        } else { selection = HoldHighlightSettings(x: point.x, y: point.y, tolerance: tolerance) }
        includeMore = false
    }
    private func remove(_ index: Int) {
        guard var settings = selection, settings.selections.indices.contains(index) else { return }
        settings.selections.remove(at: index)
        selection = settings.selections.isEmpty ? nil : settings
    }

}

private struct HighlightSelectionOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let points: [RoutePoint]
    let imageSize: CGSize
    let canSelect: Bool
    let choose: (RoutePoint) -> Void
    let remove: (Int) -> Void
    var body: some View {
        GeometryReader { geometry in
            Color.clear.contentShape(Rectangle()).onTapGesture { point in
                guard canSelect, let normalized = HoldHighlight.normalizedPoint(point, imageSize: imageSize, containerSize: geometry.size) else { return }
                choose(RoutePoint(x: normalized.x, y: normalized.y))
            }
            ForEach(points.indices, id: \.self) { index in
                marker(index)
                    .position(x: CGFloat(points[index].x) * geometry.size.width, y: CGFloat(points[index].y) * geometry.size.height)
                    .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
            }
        }
    }
    private func marker(_ index: Int) -> some View {
        Button { remove(index) } label: {
            Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: 26, height: 26).background(.black.opacity(0.8), in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2)).frame(width: 44, height: 44)
        }.buttonStyle(.plain)
            .accessibilityLabel("Remove selected hold \(index + 1)")
            .accessibilityHint("Removes this selection from the highlight")
            .accessibilityIdentifier("highlightMarker\(index + 1)")
    }
}

/// Read-only regeneration for saved previews. Derived pixels are never persisted.
struct HighlightedRoutePhoto: View {
    let data: Data
    let annotationJSON: String
    var showOriginal = false
    @State private var image: UIImage?
    @State private var message: String?
    var body: some View {
        Group {
            if let image { RouteMarkupImage(image: image, strokes: (try? RouteAnnotations.decode(annotationJSON)) ?? []) }
            else if let message { Text(message).foregroundStyle(ClimbTheme.secondaryText) }
            else { SwiftUI.ProgressView("Opening photo…") }
        }.task(id: "\(showOriginal):\(annotationJSON)") {
            do {
                var settings = showOriginal ? nil : try RouteAnnotations.document(annotationJSON).highlight
                settings?.isEnabled = true
                let result = try await HoldHighlight.process(data: data, settings: settings)
                try Task.checkCancellation()
                image = UIImage(cgImage: result); message = nil
            } catch is CancellationError { }
            catch { image = nil; message = error.localizedDescription }
        }
    }
}
