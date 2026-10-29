import SwiftUI

struct HoldHighlightView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    let item: RouteMediaDraft
    let save: (String) -> Bool
    @State private var selection: HoldHighlightSettings?
    @State private var tolerance: Double = 0.22
    @State private var image: UIImage?
    @State private var processing = true
    @State private var message: String?
    @State private var retry = 0
    @State private var renderSucceeded = false
    @State private var document: RouteAnnotationDocument?

    private var request: Request { Request(selection: selection, retry: retry, ready: document != nil) }
    private struct Request: Equatable { let selection: HoldHighlightSettings?; let retry: Int; let ready: Bool }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tap one hold to highlight similar colors. Adjust tolerance to include more or fewer shades. Wall markings with the same color may also match.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let image {
                        RouteMarkupImage(image: image, strokes: document?.strokes ?? [])
                            .overlay {
                                GeometryReader { geometry in
                                    if let selection {
                                        Circle().stroke(.white, lineWidth: 3).background(Circle().stroke(.black, lineWidth: 6))
                                            .frame(width: 20, height: 20)
                                            .position(x: selection.x * geometry.size.width, y: selection.y * geometry.size.height)
                                            .allowsHitTesting(false)
                                    }
                                    Color.clear.contentShape(Rectangle())
                                        .onTapGesture { point in
                                            guard let normalized = HoldHighlight.normalizedPoint(point, imageSize: image.size, containerSize: geometry.size) else { return }
                                            selection = HoldHighlightSettings(x: normalized.x, y: normalized.y, tolerance: tolerance)
                                        }
                                }
                            }
                            .accessibilityLabel("Route photo. Tap a hold to select its color.")
                            .accessibilityIdentifier("holdHighlightCanvas")
                            .accessibilityAction(named: "Select center hold") {
                                selection = HoldHighlightSettings(x: 0.5, y: 0.5, tolerance: tolerance)
                            }
                            .accessibilityValue(selection == nil ? "Original photo" : "Hold color selected")
                    }
                    if processing { SwiftUI.ProgressView("Processing photo…").accessibilityIdentifier("highlightProcessing") }
                    if let message {
                        Text(message).foregroundStyle(.red).accessibilityIdentifier("highlightError")
                        Button("Retry processing") { retry += 1 }.frame(minHeight: 44)
                    }
                    Text(selection == nil ? "No color selected" : "Hold color selected").font(.headline).accessibilityIdentifier("highlightSelection")
                    Text("Color tolerance").font(.headline)
                    Slider(value: $tolerance, in: 0...1, step: 0.01)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Color tolerance")
                        .accessibilityValue("\(Int(tolerance * 100)) percent")
                        .accessibilityIdentifier("highlightTolerance")
                        .disabled(selection == nil)
                        .onChange(of: tolerance) { _, value in
                            if selection != nil { selection?.tolerance = value }
                        }
                    Text("\(Int(tolerance * 100))% · Higher values include more colors.").font(.caption).foregroundStyle(.secondary)
                    Button("Reset to original", systemImage: "arrow.counterclockwise") { selection = nil }
                        .frame(minHeight: 44).disabled(selection == nil).accessibilityIdentifier("resetHoldHighlight")
                    Text("The original photo and private markup are preserved. Done saves this view; Cancel keeps your previous settings.").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }
            .background(ClimbTheme.background)
            .navigationTitle(typeSize.isAccessibilitySize ? "Highlight" : "Highlight holds").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        guard var document else { return }
                        document.highlight = selection
                        do {
                            if save(try RouteAnnotations.encode(document)) { dismiss() }
                            else { message = "Your highlight couldn’t be saved. Try Done again. Your selection is still here." }
                        } catch { message = error.localizedDescription }
                    }.disabled(processing || image == nil || document == nil || !renderSucceeded)
                        .accessibilityIdentifier("saveHoldHighlight")
                }
            }
            .task {
                do {
                    let saved = try RouteAnnotations.document(item.annotationJSON)
                    document = saved
                    tolerance = saved.highlight?.tolerance ?? 0.22
                    selection = saved.highlight
                } catch { message = "The saved photo settings couldn’t be opened. They have been kept."; processing = false }
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
    }
}

/// Read-only regeneration for saved previews. Derived pixels are never persisted.
struct HighlightedRoutePhoto: View {
    let data: Data
    let annotationJSON: String
    @State private var image: UIImage?
    @State private var message: String?
    var body: some View {
        Group {
            if let image { RouteMarkupImage(image: image, strokes: (try? RouteAnnotations.decode(annotationJSON)) ?? []) }
            else if let message { Text(message).foregroundStyle(.secondary) }
            else { SwiftUI.ProgressView("Opening photo…") }
        }.task(id: annotationJSON) {
            do {
                let settings = try RouteAnnotations.document(annotationJSON).highlight
                let result = try await HoldHighlight.process(data: data, settings: settings)
                try Task.checkCancellation()
                image = UIImage(cgImage: result); message = nil
            } catch is CancellationError { }
            catch { image = nil; message = error.localizedDescription }
        }
    }
}
