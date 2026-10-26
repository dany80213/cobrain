import AppKit
import SwiftUI

/// File › Home, as in WordCraft: a greeting, Blank plus a row of templates, then Recent.
struct HomePage: View {
    @ObservedObject var model: DocumentModel
    @Environment(\.openWindow) private var openWindow
    @State private var recent: [URL] = NSDocumentController.shared.recentDocumentURLs

    private static let templates: [(label: String, id: String)] = [
        ("Blank document", "blank"), ("Studio handbook (sample)", "sample"), ("Letter", "letter"), ("Résumé", "resume"), ("Report", "report")]

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(greeting).font(.system(size: 26, weight: .semibold))
                HStack(alignment: .top, spacing: 18) {
                    ForEach(Self.templates.prefix(4), id: \.id) { t in
                        TemplateTile(label: t.label, template: t.id) { model.newDocument(template: t.id); model.showBackstage = false }
                    }
                    WhiteboardTile { openWindow(id: "whiteboard"); model.showBackstage = false }
                }
                Text("Recent").font(.system(size: 16, weight: .semibold)).padding(.top, 14)
                if recent.isEmpty {
                    Text("Documents you open will show up here.").foregroundStyle(.secondary)
                }
                ForEach(recent.prefix(12), id: \.self) { url in
                    Button { model.openReplacingCurrent(url); if model.fileURL == url { model.showBackstage = false } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text").font(.system(size: 18)).foregroundStyle(Color.accentColor).frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(url.lastPathComponent).font(.system(size: 13, weight: .medium))
                                Text(url.path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 5).padding(.horizontal, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).frame(maxWidth: 700)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { recent = NSDocumentController.shared.recentDocumentURLs }
    }
}

/// A template thumbnail (the engine's own render of page 1) with its caption.
struct TemplateTile: View {
    let label: String
    let template: String
    let action: () -> Void
    @State private var image: CGImage?
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Color.white
                    if let image { Image(decorative: image, scale: 2).resizable().scaledToFill() }
                }
                .frame(width: 150, height: 194).clipped()
                .overlay(Rectangle().stroke(hover ? Color.accentColor : Color.gray.opacity(0.5), lineWidth: hover ? 2 : 1))
                Text(label).font(.system(size: 12.5)).padding(.top, 4).frame(width: 150, alignment: .leading)
            }
        }
        .buttonStyle(.plain).onHover { hover = $0 }
        .task {
            guard image == nil, let e = Engine() else { return }
            if template != "blank" { _ = e.run("file.new", ["template": template]) }
            if let p = e.pageSize(0) { image = e.renderPage(0, scale: 300 / p.width) }
        }
    }
}

/// "New whiteboard" tile next to the document templates.
struct WhiteboardTile: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Color.white
                    Canvas { ctx, size in
                        var dots = Path()
                        for x in stride(from: 8.0, to: size.width, by: 14) { for y in stride(from: 8.0, to: size.height, by: 14) { dots.addEllipse(in: CGRect(x: x, y: y, width: 1.5, height: 1.5)) } }
                        ctx.fill(dots, with: .color(.gray.opacity(0.4)))
                        ctx.fill(Path(roundedRect: CGRect(x: 18, y: 28, width: 54, height: 40), cornerRadius: 8), with: .color(Color(red: 0.49, green: 0.42, blue: 0.94)))
                        ctx.fill(Path(ellipseIn: CGRect(x: 80, y: 80, width: 50, height: 50)), with: .color(Color(red: 1, green: 0.67, blue: 0)))
                        ctx.fill(Path(CGRect(x: 24, y: 112, width: 44, height: 44)), with: .color(Color(red: 1, green: 0.9, blue: 0.42)))
                        var a = Path(); a.move(to: CGPoint(x: 74, y: 52)); a.addLine(to: CGPoint(x: 112, y: 84))
                        ctx.stroke(a, with: .color(.black.opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                }
                .frame(width: 150, height: 194).clipped()
                .overlay(Rectangle().stroke(hover ? Color.accentColor : Color.gray.opacity(0.5), lineWidth: hover ? 2 : 1))
                Text("Whiteboard").font(.system(size: 12.5)).padding(.top, 4).frame(width: 150, alignment: .leading)
            }
        }
        .buttonStyle(.plain).onHover { hover = $0 }
    }
}
