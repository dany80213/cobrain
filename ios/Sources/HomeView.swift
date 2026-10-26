import SwiftUI
import UniformTypeIdentifiers

/// Cobrain Home on iPad: start something new (document templates, whiteboard) or pick up a recent file.
struct HomeView: View {
    @ObservedObject var library: Library
    @Binding var path: [Route]
    @State private var importing = false
    @State private var renaming: LibraryItem?
    @State private var newName = ""
    @State private var failed: String?

    private static let templates: [(label: String, id: String)] = [("Blank document", "blank"), ("Studio handbook", "sample"), ("Letter", "letter"), ("Résumé", "resume"), ("Report", "report")]
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 20, alignment: .top)]

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text(greeting).font(.system(size: 32, weight: .semibold))
                section("New") {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(Self.templates, id: \.id) { t in
                            Tile(title: t.label, subtitle: nil, image: Thumbnails.shared.template(t.id)) {
                                if let u = library.newDocument(template: t.id) { path.append(.word(u)) } else { failed = "Could not create the document" }
                            }
                        }
                        Tile(title: "Whiteboard", subtitle: nil, image: nil, symbol: "scribble.variable") {
                            if let u = library.newBoard() { path.append(.board(u)) } else { failed = "Could not create the whiteboard" }
                        }
                    }
                }
                section("Recent") {
                    if library.items.isEmpty {
                        Text("Documents and whiteboards you create or open will show up here.").foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(library.items) { item in
                            Tile(title: item.name, subtitle: item.modified.formatted(date: .abbreviated, time: .shortened), image: Thumbnails.shared.image(for: item),
                                 symbol: item.kind == .board ? "scribble.variable" : "doc.text") {
                                path.append(item.kind == .board ? .board(item.url) : .word(item.url))
                            }
                            .contextMenu {
                                Button { renaming = item; newName = item.name } label: { Label("Rename", systemImage: "pencil") }
                                ShareLink(item: item.url) { Label("Share", systemImage: "square.and.arrow.up") }
                                Button(role: .destructive) { library.delete(item) } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
            .padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Cobrain")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { importing = true } label: { Label("Open…", systemImage: "folder") } }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.cobrainBoard, .rtf, .plainText, .html, .data], allowsMultipleSelection: false) { r in
            guard case .success(let urls) = r, let url = urls.first else { return }
            if let u = library.importFile(url) { path.append(FileKind(url: u) == .board ? .board(u) : .word(u)) } else { failed = "Cobrain can’t open “\(url.lastPathComponent)”." }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let r = renaming { library.rename(r, to: newName) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("Cobrain", isPresented: Binding(get: { failed != nil }, set: { if !$0 { failed = nil } })) { Button("OK") {} } message: { Text(failed ?? "") }
        .onAppear { library.reload() }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 20, weight: .semibold))
            content()
        }
    }
}

struct Tile: View {
    let title: String
    let subtitle: String?
    let image: UIImage?
    var symbol: String = "doc"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Color.white
                    if let image { Image(uiImage: image).resizable().scaledToFill() }
                    else { Image(systemName: symbol).font(.system(size: 38)).foregroundStyle(.secondary) }
                }
                .frame(height: 194).frame(maxWidth: .infinity).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.35)))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1).foregroundStyle(.primary)
                if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
        .buttonStyle(.plain)
    }
}
