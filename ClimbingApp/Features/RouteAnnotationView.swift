import SwiftUI
import ImageIO

enum RouteAnnotationImage {
    static func load(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData,nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1600,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { return nil }
        return UIImage(cgImage:image)
    }
}

struct RouteMarkupImage: View {
    let image: UIImage
    let strokes: [RouteStroke]
    var body: some View {
        Image(uiImage:image).resizable().scaledToFit()
            .overlay {
                Canvas { context,size in
                    for stroke in strokes {
                        guard let first = stroke.points.first else { continue }
                        var path = Path(); path.move(to:CGPoint(x:first.x*size.width,y:first.y*size.height))
                        for point in stroke.points.dropFirst() { path.addLine(to:CGPoint(x:point.x*size.width,y:point.y*size.height)) }
                        if stroke.points.count == 1 { path.addLine(to:CGPoint(x:first.x*size.width+1,y:first.y*size.height+1)) }
                        context.stroke(path,with:.color(stroke.color == "white" ? .white : stroke.color == "blue" ? .blue : .orange),style:StrokeStyle(lineWidth:5,lineCap:.round,lineJoin:.round))
                    }
                }.allowsHitTesting(false)
            }
            .aspectRatio(image.size.width/image.size.height,contentMode:.fit)
            .accessibilityLabel("Route photo with \(strokes.count) private annotations")
    }
}

struct RouteAnnotationView: View {
    @Environment(ClimbingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let media: RouteMedia
    @State private var image: UIImage?
    @State private var strokes: [RouteStroke] = []
    @State private var current: [RoutePoint] = []
    @State private var color = "orange"
    @State private var failed = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Text("Circle a hold or draw a path with your finger. Markup stays private and the original photo is preserved.").font(.subheadline).foregroundStyle(.secondary)
                    Picker("Pen color",selection:$color) { Text("Orange").tag("orange");Text("Blue").tag("blue");Text("White").tag("white") }.pickerStyle(.segmented)
                    if let image {
                        RouteMarkupImage(image:image,strokes:strokes + (current.isEmpty ? [] : [RouteStroke(color:color,points:current)]))
                            .overlay {
                                GeometryReader { geometry in
                                    Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0)
                                        .onChanged { value in
                                            guard current.count < 2000,strokes.count < 200 else { return }
                                            current.append(RoutePoint(x:min(1,max(0,value.location.x/geometry.size.width)),y:min(1,max(0,value.location.y/geometry.size.height))))
                                        }.onEnded { _ in
                                            if !current.isEmpty { strokes.append(RouteStroke(color:color,points:current));current=[] }
                                        })
                                }
                            }.clipShape(RoundedRectangle(cornerRadius:12)).accessibilityIdentifier("routeMarkupCanvas")
                    } else { Text("Route photo unavailable.") }
                    HStack {
                        Button("Undo stroke",systemImage:"arrow.uturn.backward") { _ = strokes.popLast() }.disabled(strokes.isEmpty)
                        Spacer()
                        Button("Clear markup",role:.destructive) { strokes=[] }.disabled(strokes.isEmpty)
                    }.frame(minHeight:44)
                    if failed { Text("This markup couldn’t be opened. Its saved data has been kept.").foregroundStyle(.red) }
                }.padding(20)
            }.background(ClimbTheme.background).navigationTitle("Private route markup").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement:.confirmationAction) { Button("Save") {
                        do {
                            let json = try RouteAnnotations.encode(strokes)
                            if store.save({ media.annotationJSON=json;media.updatedAt = .now }) { dismiss() }
                        } catch { store.errorMessage=error.localizedDescription }
                    }.disabled(image == nil || failed).accessibilityIdentifier("saveRouteMarkup") }
                }
                .task {
                    image=RouteAnnotationImage.load(media.data)
                    do { strokes=try RouteAnnotations.decode(media.annotationJSON) } catch { failed=true }
                }
        }.safeAreaInset(edge:.top) { SaveErrorBanner() }
    }
}

struct ProjectNotebookSummary: View {
    let climb: ClimbEntry
    var body: some View {
        if let pinned = climb.pinnedNote {
            VStack(alignment:.leading,spacing:8) { Label("Next move",systemImage:"pin.fill").font(.subheadline.bold());Text(pinned.text).lineLimit(4) }
                .padding(14).frame(maxWidth:.infinity,alignment:.leading).background(ClimbTheme.forest.opacity(0.08),in:RoundedRectangle(cornerRadius:14))
        }
        ForEach(climb.recentNotebook,id:\.id) { note in
            VStack(alignment:.leading,spacing:4) { Text(note.text).font(.subheadline).lineLimit(3);Text(note.updatedAt,format:.dateTime.month().day()).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
