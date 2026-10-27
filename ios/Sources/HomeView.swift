import SwiftUI
import UniformTypeIdentifiers

let documentTemplates: [(label: String, id: String)] = [("Blank document", "blank"), ("Studio handbook", "sample"), ("Letter", "letter"), ("Résumé", "resume"), ("Report", "report")]

/// Cobrain Home on iPad: your subjects as notebooks on a shelf, then new files and recent ones.
struct HomeView: View {
    @ObservedObject var library: Library
    @Binding var path: [Route]
    @State private var importing = false
    @State private var editing: SubjectSheet?
    @State private var toDelete: Subject?
    @State private var failed: String?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 20, alignment: .top)]
    private let shelfColumns = [GridItem(.adaptive(minimum: 170, maximum: 200), spacing: 12, alignment: .top)]

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(greeting).font(.system(size: 32, weight: .semibold))
                section("Subjects") {
                    LazyVGrid(columns: shelfColumns, alignment: .leading, spacing: 26) {
                        ForEach(library.subjects) { s in
                            Button { path.append(.subject(s.url)) } label: { NotebookCover(name: s.name, style: s.style, count: s.count, width: 150).shelf() }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { editing = SubjectSheet(subject: s) } label: { Label("Customize…", systemImage: "paintbrush") }
                                    Button(role: .destructive) { toDelete = s } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                        Button { editing = SubjectSheet(subject: nil) } label: { NewNotebookTile(width: 150).shelf() }.buttonStyle(.plain)
                    }
                }
                section("New") {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(documentTemplates, id: \.id) { t in
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
                        ForEach(library.items.prefix(24)) { item in FileTile(item: item, library: library, path: $path) }
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
        .sheet(item: $editing) { sheet in
            SubjectEditor(isNew: sheet.subject == nil, name: sheet.subject?.name ?? "", style: sheet.subject?.style ?? SubjectStyle.guess(for: "")) { name, style in
                if let s = sheet.subject { library.updateSubject(s, name: name, style: style) } else { library.createSubject(name: name, style: style) }
                editing = nil
            } onCancel: { editing = nil }
            .presentationDetents([.large])
        }
        .confirmationDialog("Delete “\(toDelete?.name ?? "")”?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Delete Subject and Its Files", role: .destructive) { if let s = toDelete { library.deleteSubject(s) }; toDelete = nil }
        } message: { Text("All the documents and whiteboards inside are deleted too.") }
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

struct SubjectSheet: Identifiable {
    let id = UUID()
    let subject: Subject?
}


/// A recent file: thumbnail tile with rename / move / share / delete.
struct FileTile: View {
    let item: LibraryItem
    @ObservedObject var library: Library
    @Binding var path: [Route]
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        Tile(title: item.name, subtitle: item.subject ?? item.modified.formatted(date: .abbreviated, time: .shortened), image: Thumbnails.shared.image(for: item),
             symbol: item.kind == .board ? "scribble.variable" : "doc.text") {
            path.append(item.kind == .board ? .board(item.url) : .word(item.url))
        }
        .contextMenu {
            Button { renaming = true; newName = item.name } label: { Label("Rename", systemImage: "pencil") }
            Menu {
                ForEach(library.subjects) { s in Button { library.move(item, to: s) } label: { Label(s.name, systemImage: s.style.symbol) } }
                if item.subject != nil { Button { library.move(item, to: nil) } label: { Label("No subject", systemImage: "tray") } }
            } label: { Label("Move to Subject", systemImage: "books.vertical") }
            ShareLink(item: item.url) { Label("Share", systemImage: "square.and.arrow.up") }
            Button(role: .destructive) { library.delete(item) } label: { Label("Delete", systemImage: "trash") }
        }
        .alert("Rename", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Rename") { library.rename(item, to: newName) }
            Button("Cancel", role: .cancel) {}
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

/// One subject: its notebook, and the documents and whiteboards inside.
struct SubjectScreen: View {
    let url: URL
    @ObservedObject var library: Library
    @Binding var path: [Route]
    @State private var editing: SubjectSheet?
    @State private var importing = false
    @State private var failed: String?
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 20, alignment: .top)]

    private var subject: Subject? { library.subjects.first { $0.url.standardizedFileURL == url.standardizedFileURL } }

    var body: some View {
        ScrollView {
            if let s = subject {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .bottom, spacing: 22) {
                        NotebookCover(name: s.name, style: s.style, count: nil, width: 120)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(s.name).font(.system(size: 30, weight: .semibold))
                            Text(s.count == 1 ? "1 file" : "\(s.count) files").foregroundStyle(.secondary)
                            HStack {
                                Menu {
                                    ForEach(documentTemplates, id: \.id) { t in
                                        Button(t.label) { if let u = library.newDocument(template: t.id, in: s.url) { path.append(.word(u)) } }
                                    }
                                } label: { Label("New Document", systemImage: "doc.badge.plus") }
                                Button { if let u = library.newBoard(in: s.url) { path.append(.board(u)) } } label: { Label("New Whiteboard", systemImage: "scribble.variable") }
                                Button { importing = true } label: { Label("Import…", systemImage: "square.and.arrow.down") }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    let files = library.items(in: s)
                    if files.isEmpty {
                        Text("This notebook is empty. Create a document or a whiteboard for \(s.name).").foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(files) { item in FileTile(item: item, library: library, path: $path) }
                    }
                }
                .padding(28).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("This subject no longer exists.").foregroundStyle(.secondary).padding(40)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(subject?.name ?? "Subject")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let s = subject { Button { editing = SubjectSheet(subject: s) } label: { Label("Customize", systemImage: "paintbrush") } }
            }
        }
        .sheet(item: $editing) { sheet in
            SubjectEditor(isNew: false, name: sheet.subject?.name ?? "", style: sheet.subject?.style ?? SubjectStyle()) { name, style in
                if let s = sheet.subject {
                    library.updateSubject(s, name: name, style: style)
                    // A renamed subject has a new folder: follow it.
                    if name != s.name, !path.isEmpty { path[path.count - 1] = .subject(library.folder.appendingPathComponent(name)) }
                }
                editing = nil
            } onCancel: { editing = nil }
            .presentationDetents([.large])
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.cobrainBoard, .rtf, .plainText, .html, .data], allowsMultipleSelection: false) { r in
            guard case .success(let urls) = r, let picked = urls.first, let s = subject else { return }
            if let u = library.importFile(picked, into: s.url) { path.append(FileKind(url: u) == .board ? .board(u) : .word(u)) } else { failed = "Cobrain can’t open “\(picked.lastPathComponent)”." }
        }
        .alert("Cobrain", isPresented: Binding(get: { failed != nil }, set: { if !$0 { failed = nil } })) { Button("OK") {} } message: { Text(failed ?? "") }
        .onAppear { library.reload() }
    }
}
