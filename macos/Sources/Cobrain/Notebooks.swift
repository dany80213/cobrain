import AppKit
import SwiftUI

/// What opens a whiteboard window: a file, or nothing for a new empty board.
struct BoardRef: Codable, Hashable {
    var url: URL?
}

/// The documents and whiteboards inside a subject folder, newest first (folders inside the subject are searched too).
enum SubjectFiles {
    static func list(_ folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [(URL, Date)] = []
        for case let u as URL in walker {
            let ext = u.pathExtension.lowercased()
            guard ProjectStore.documentTypes.contains(ext) || ext == "cobrainboard" else { continue }
            found.append((u, (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast))
        }
        return found.sorted { $0.1 > $1.1 }.map(\.0)
    }
}

/// Home › Subjects: the current project's subjects as notebooks on a shelf.
struct SubjectsShelf: View {
    @ObservedObject var store: ProjectStore = .shared
    @Binding var openSubject: URL?
    @State private var editing: EditTarget?
    @State private var toTrash: URL?
    @State private var newProject = false
    @State private var projectName = ""

    struct EditTarget: Identifiable { let id = UUID(); let url: URL? }

    private var subjects: [ProjectItem] { store.tree.filter(\.isFolder) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Subjects").font(.system(size: 16, weight: .semibold))
                if let project = store.current { Text(project.lastPathComponent).foregroundStyle(.secondary).font(.system(size: 12)) }
            }
            if let project = store.current {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(subjects) { s in
                            Button { openSubject = s.url } label: {
                                NotebookCover(name: s.name, style: SubjectStyle.load(from: s.url), count: SubjectFiles.list(s.url).count, width: 120).shelf()
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Open") { openSubject = s.url }
                                Button("Customize…") { editing = EditTarget(url: s.url) }
                                Button("Show in Finder") { store.reveal(s.url) }
                                Divider()
                                Button("Move to Trash…") { toTrash = s.url }
                            }
                        }
                        Button { editing = EditTarget(url: nil) } label: { NewNotebookTile(width: 120).shelf() }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10).padding(.bottom, 4)
                }
                .sheet(item: $editing) { target in
                    SubjectEditor(isNew: target.url == nil, name: target.url?.lastPathComponent ?? "", style: target.url.map { SubjectStyle.load(from: $0) } ?? SubjectStyle.guess(for: "")) { name, style in
                        save(target.url, name: name, style: style, in: project)
                        editing = nil
                    } onCancel: { editing = nil }
                }
                .confirmationDialog("Move “\(toTrash?.lastPathComponent ?? "")” to the Trash?", isPresented: Binding(get: { toTrash != nil }, set: { if !$0 { toTrash = nil } })) {
                    Button("Move to Trash", role: .destructive) {
                        if let t = toTrash { store.trash(ProjectItem(url: t, isFolder: true, depth: 0)) }
                        toTrash = nil
                    }
                } message: { Text("Everything inside the subject goes to the Trash too.") }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keep your notes by subject: create a project (for example a school year), then add a notebook for each subject.").foregroundStyle(.secondary)
                    Button("New Project…") { projectName = ""; newProject = true }.buttonStyle(.borderedProminent)
                    Button("Add Existing Folder…") { store.addExistingProject() }
                }
                .alert("New Project", isPresented: $newProject) {
                    TextField("e.g. School year 2026", text: $projectName)
                    Button("Cancel", role: .cancel) {}
                    Button("Create") { store.createProject(named: projectName) }
                }
            }
        }
    }

    private func save(_ url: URL?, name: String, style: SubjectStyle, in project: URL) {
        if let url {
            var folder = url
            if name != url.lastPathComponent, let renamed = store.rename(ProjectItem(url: url, isFolder: true, depth: 0), to: name) { folder = renamed }
            style.save(to: folder)
        } else if let folder = store.makeFolder(named: name, in: project) {
            style.save(to: folder)
        }
        store.reload()
    }
}

/// One subject opened: its notebook and every document and whiteboard in it.
struct SubjectDetail: View {
    @ObservedObject var model: DocumentModel
    @ObservedObject var store: ProjectStore = .shared
    let folder: URL
    let close: () -> Void
    @Environment(\.openWindow) private var openWindow
    @State private var refresh = 0

    private var files: [URL] { _ = refresh; return SubjectFiles.list(folder) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button { close() } label: { Label("Subjects", systemImage: "chevron.left") }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
                HStack(alignment: .bottom, spacing: 20) {
                    NotebookCover(name: folder.lastPathComponent, style: SubjectStyle.load(from: folder), count: nil, width: 110)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(folder.lastPathComponent).font(.system(size: 26, weight: .semibold))
                        Text(files.count == 1 ? "1 file" : "\(files.count) files").foregroundStyle(.secondary)
                        HStack {
                            Menu("New Document") {
                                ForEach(DocumentTemplate.allCases) { t in Button(t.title) { newDocument(t) } }
                            }.fixedSize()
                            Button("New Whiteboard") { newBoard() }
                            Button("Show in Finder") { store.reveal(folder) }
                        }
                    }
                }
                if files.isEmpty { Text("This notebook is empty. Create a document or a whiteboard.").foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 170), spacing: 18, alignment: .top)], alignment: .leading, spacing: 18) {
                    ForEach(files, id: \.self) { url in
                        FileTileMac(url: url) { open(url) }
                            .contextMenu {
                                Button("Open") { open(url) }
                                Button("Show in Finder") { store.reveal(url) }
                                Divider()
                                Button("Move to Trash") {
                                    try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                                    store.reload(); refresh += 1
                                }
                            }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func open(_ url: URL) {
        if url.pathExtension.lowercased() == "cobrainboard" {
            openWindow(id: "whiteboard", value: BoardRef(url: url))
            model.showBackstage = false
        } else {
            model.openReplacingCurrent(url)
            if model.fileURL == url { model.showBackstage = false }
        }
    }

    private func newDocument(_ t: DocumentTemplate) {
        if let url = store.makeDocument(named: "Untitled", in: folder, template: t) { model.openReplacingCurrent(url); if model.fileURL == url { model.showBackstage = false } }
        refresh += 1
    }

    private func newBoard() {
        var url = folder.appendingPathComponent("Untitled whiteboard.cobrainboard")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) { url = folder.appendingPathComponent("Untitled whiteboard \(n).cobrainboard"); n += 1 }
        guard let data = try? BoardModel().encoded(), (try? data.write(to: url)) != nil else { return }
        store.reload(); refresh += 1
        openWindow(id: "whiteboard", value: BoardRef(url: url))
        model.showBackstage = false
    }
}

struct FileTileMac: View {
    let url: URL
    let action: () -> Void
    @State private var image: CGImage?
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    Color.white
                    if let image { Image(decorative: image, scale: 2).resizable().scaledToFill() }
                    else { Image(systemName: url.pathExtension.lowercased() == "cobrainboard" ? "scribble.variable" : "doc.text").font(.system(size: 28)).foregroundStyle(.secondary) }
                }
                .frame(width: 130, height: 170).clipped()
                .overlay(Rectangle().stroke(hover ? Color.accentColor : Color.gray.opacity(0.5), lineWidth: hover ? 2 : 1))
                Text(url.deletingPathExtension().lastPathComponent).font(.system(size: 12.5)).lineLimit(1).frame(width: 130, alignment: .leading)
            }
        }
        .buttonStyle(.plain).onHover { hover = $0 }
        .task { image = FileThumbnails.image(for: url) }
    }
}

