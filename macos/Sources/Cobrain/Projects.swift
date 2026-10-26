import AppKit
import SwiftUI

/// One entry of a project folder: a subject (top-level folder), a folder inside it, or a document.
struct ProjectItem: Identifiable, Hashable {
    let url: URL
    let isFolder: Bool
    let depth: Int
    /// Not downloaded from iCloud yet (only an `.name.icloud` placeholder is on disk).
    var inCloudOnly = false
    /// `nil` for documents, so the outline shows no disclosure arrow.
    var children: [ProjectItem]?

    var id: URL { url }
    var name: String { isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent }
    var icon: String { isFolder ? (depth == 0 ? "books.vertical" : "folder") : (inCloudOnly ? "icloud.and.arrow.down" : "doc.text") }
}

/// Projects are plain folders on disk: the folders at the top are subjects, deeper folders group
/// documents, files are documents. New projects go to iCloud Drive when it is on, so a project can be
/// shared (Finder's Share › Collaborate, or the pane's Share button) and classmates edit the same files.
final class ProjectStore: ObservableObject {
    static let shared = ProjectStore()
    static let documentTypes: Set<String> = ["docx", "doc", "rtf", "odt", "md", "txt", "html"]

    @Published private(set) var projects: [URL] = []
    @Published var current: URL? { didSet { persist(); reload() } }
    @Published private(set) var tree: [ProjectItem] = []
    @Published var lastError: String?

    private let defaults = UserDefaults.standard
    private var timer: Timer?

    static var iCloudDrive: URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Where new projects are created: `iCloud Drive/Cobrain`, or `Documents/Cobrain` without iCloud.
    static var defaultRoot: URL {
        (iCloudDrive ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")).appendingPathComponent("Cobrain")
    }

    init() {
        // COBRAIN_PROJECT=/path shows that folder (used by --snapshot); the saved list is left alone.
        if let path = ProcessInfo.processInfo.environment["COBRAIN_PROJECT"] {
            projects = [URL(fileURLWithPath: path)]
            current = projects.first
            reload()
            return
        }
        projects = (defaults.stringArray(forKey: "projects") ?? []).map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        let saved = defaults.string(forKey: "currentProject").map { URL(fileURLWithPath: $0) }
        current = saved.flatMap { projects.contains($0) ? $0 : nil } ?? projects.first
        reload()
        // Classmates' changes arrive through iCloud: look at the folder again every few seconds.
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in self?.reload() }
    }

    private func persist() {
        guard ProcessInfo.processInfo.environment["COBRAIN_PROJECT"] == nil else { return }
        defaults.set(projects.map(\.path), forKey: "projects")
        defaults.set(current?.path, forKey: "currentProject")
    }

    func reload() {
        let next = current.map { scan($0, depth: 0) } ?? []
        if next != tree { tree = next }
    }

    private func scan(_ folder: URL, depth: Int) -> [ProjectItem] {
        guard depth < 12 else { return [] }
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        var items: [ProjectItem] = []
        for url in entries {
            var name = url.lastPathComponent
            var cloudOnly = false
            // An iCloud file not downloaded yet is `.Name.docx.icloud`.
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                name = String(name.dropFirst().dropLast(".icloud".count))
                cloudOnly = true
            } else if name.hasPrefix(".") || name.hasPrefix("~$") {
                continue
            }
            let real = folder.appendingPathComponent(name)
            let isDir = !cloudOnly && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDir {
                items.append(ProjectItem(url: real, isFolder: true, depth: depth, children: scan(real, depth: depth + 1)))
            } else if Self.documentTypes.contains(real.pathExtension.lowercased()) {
                items.append(ProjectItem(url: real, isFolder: false, depth: depth, inCloudOnly: cloudOnly))
            }
        }
        return items.sorted {
            $0.isFolder != $1.isFolder ? $0.isFolder : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    // MARK: Projects

    func createProject(named name: String) {
        guard let url = makeFolder(named: name, in: Self.defaultRoot) else { return }
        projects.append(url)
        current = url
    }

    /// Adds a folder that already exists, e.g. a project a classmate shared (it shows up in iCloud Drive).
    func addExistingProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add Project"
        panel.directoryURL = Self.iCloudDrive ?? Self.defaultRoot
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !projects.contains(url) { projects.append(url) }
        current = url
    }

    /// Forgets the project; its folder and files stay where they are.
    func removeFromList(_ url: URL) {
        projects.removeAll { $0 == url }
        if current == url { current = projects.first } else { persist() }
    }

    func isInICloud(_ url: URL) -> Bool {
        guard let cloud = Self.iCloudDrive else { return false }
        return url.standardizedFileURL.path.hasPrefix(cloud.standardizedFileURL.path + "/")
    }

    /// Moves a project kept on this Mac into iCloud Drive so it can be shared.
    func moveToICloud(_ url: URL) {
        guard let cloud = Self.iCloudDrive else { lastError = "iCloud Drive is not turned on for this Mac."; return }
        let root = cloud.appendingPathComponent("Cobrain")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let dest = uniqueURL(root.appendingPathComponent(url.lastPathComponent))
            try FileManager.default.moveItem(at: url, to: dest)
            if let i = projects.firstIndex(of: url) { projects[i] = dest }
            current = dest
        } catch { lastError = "Could not move the project: \(error.localizedDescription)" }
    }

    func share(_ url: URL) {
        let picker = NSSharingServicePicker(items: [url])
        guard let view = NSApp.keyWindow?.contentView else { return }
        picker.show(relativeTo: NSRect(x: 130, y: view.bounds.height - 120, width: 1, height: 1), of: view, preferredEdge: .maxY)
    }

    // MARK: Subjects, folders and documents

    @discardableResult
    func makeFolder(named name: String, in parent: URL) -> URL? {
        guard let clean = cleanName(name) else { return nil }
        let url = uniqueURL(parent.appendingPathComponent(clean))
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch { lastError = "Could not create \(clean): \(error.localizedDescription)"; return nil }
        reload()
        return url
    }

    /// A blank Word document in `folder`; returns its URL.
    func makeDocument(named name: String, in folder: URL) -> URL? {
        guard let clean = cleanName(name) else { return nil }
        let base = clean.lowercased().hasSuffix(".docx") ? String(clean.dropLast(5)) : clean
        let url = uniqueURL(folder.appendingPathComponent(base).appendingPathExtension("docx"))
        guard let blank = Engine(), blank.save(to: url.path) else { lastError = "Could not create \(url.lastPathComponent)"; return nil }
        reload()
        return url
    }

    func rename(_ item: ProjectItem, to name: String) -> URL? {
        guard let clean = cleanName(name) else { return nil }
        var dest = item.url.deletingLastPathComponent().appendingPathComponent(clean)
        if !item.isFolder, dest.pathExtension.lowercased() != item.url.pathExtension.lowercased() {
            dest = dest.appendingPathExtension(item.url.pathExtension)
        }
        guard dest != item.url else { return item.url }
        dest = uniqueURL(dest)
        do {
            try FileManager.default.moveItem(at: item.url, to: dest)
        } catch { lastError = "Could not rename \(item.name): \(error.localizedDescription)"; return nil }
        if let i = projects.firstIndex(of: item.url) { projects[i] = dest; current = dest }
        reload()
        return dest
    }

    /// Moves to the Trash (recoverable), never deletes.
    func trash(_ item: ProjectItem) {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        } catch { lastError = "Could not move \(item.name) to the Trash: \(error.localizedDescription)" }
        reload()
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    private func cleanName(_ name: String) -> String? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        guard !clean.isEmpty, !clean.hasPrefix(".") else { lastError = "Please enter a name."; return nil }
        return clean
    }

    /// `Name`, `Name 2`, `Name 3`… whichever is free.
    private func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let parent = url.deletingLastPathComponent()
        for n in 2... {
            var candidate = parent.appendingPathComponent("\(base) \(n)")
            if !ext.isEmpty { candidate = candidate.appendingPathExtension(ext) }
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }
}

/// Left pane: the current project's subjects, folders and documents.
struct ProjectsPane: View {
    @ObservedObject var model: DocumentModel
    @ObservedObject var store: ProjectStore = .shared

    /// A pending "type a name" question.
    private struct NamePrompt: Identifiable {
        let id = UUID()
        let title: String
        let placeholder: String
        var initial = ""
        let action: (String) -> Void
    }
    @State private var prompt: NamePrompt?
    @State private var promptText = ""
    @State private var toTrash: ProjectItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Projects").font(.title3.weight(.semibold))
                Spacer()
                Button { model.projectsVisible = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Hide Projects")
            }
            projectPicker
            if let project = store.current {
                sharingRow(project)
                Divider()
                if store.tree.isEmpty {
                    Text("Add a subject (e.g. Math, History), then create documents in it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                List {
                    OutlineGroup(store.tree, children: \.children) { row($0) }
                }
                .listStyle(.sidebar)
                .contextMenu { Button("New Subject…") { askNewSubject(in: project) } }
                Button { askNewSubject(in: project) } label: { Label("New Subject", systemImage: "plus") }
                    .buttonStyle(.borderless)
            } else {
                Text("A project keeps your subjects, folders and documents together, and can be shared with classmates.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("New Project…") { askNewProject() }.buttonStyle(.borderedProminent)
                Button("Add Existing Folder…") { store.addExistingProject() }
                Spacer()
            }
            if let err = store.lastError {
                Text(err).font(.caption).foregroundStyle(.red).onTapGesture { store.lastError = nil }
            }
        }
        .padding(12)
        .frame(width: 260)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
            TextField(prompt?.placeholder ?? "", text: $promptText)
            Button("Cancel", role: .cancel) { prompt = nil }
            Button("OK") { if let p = prompt { p.action(promptText) }; prompt = nil }
        }
        .confirmationDialog("Move “\(toTrash?.name ?? "")” to the Trash?", isPresented: Binding(get: { toTrash != nil }, set: { if !$0 { toTrash = nil } })) {
            Button("Move to Trash", role: .destructive) { if let t = toTrash { store.trash(t) }; toTrash = nil }
        } message: {
            Text(toTrash?.isFolder == true ? "Everything inside it goes to the Trash too. In a shared project this removes it for everyone." : "In a shared project this removes it for everyone.")
        }
    }

    private var projectPicker: some View {
        Menu {
            ForEach(store.projects, id: \.self) { url in
                Button { store.current = url } label: {
                    if url == store.current { Label(url.lastPathComponent, systemImage: "checkmark") } else { Text(url.lastPathComponent) }
                }
            }
            if !store.projects.isEmpty { Divider() }
            Button("New Project…") { askNewProject() }
            Button("Add Existing Folder…") { store.addExistingProject() }
            if let c = store.current {
                Divider()
                Button("Rename Project…") { askRename(ProjectItem(url: c, isFolder: true, depth: -1)) }
                Button("Show in Finder") { store.reveal(c) }
                Button("Remove from List") { store.removeFromList(c) }
            }
        } label: {
            Label(store.current?.lastPathComponent ?? "No project", systemImage: "folder.badge.person.crop")
        }
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder private func sharingRow(_ project: URL) -> some View {
        if store.isInICloud(project) {
            HStack {
                Label("iCloud Drive", systemImage: "icloud").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { store.share(project) } label: { Label("Share", systemImage: "person.crop.circle.badge.plus") }
                    .controlSize(.small).help("Invite classmates to work on this project")
            }
        } else {
            HStack {
                Label("On this Mac only", systemImage: "desktopcomputer").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if ProjectStore.iCloudDrive != nil {
                    Button("Move to iCloud") { store.moveToICloud(project) }.controlSize(.small)
                        .help("Move the project to iCloud Drive so you can share it")
                }
            }
        }
    }

    private func row(_ item: ProjectItem) -> some View {
        let open = item.url == model.fileURL
        return Label {
            Text(item.name).foregroundStyle(open ? Color.accentColor : Color.primary)
        } icon: {
            Image(systemName: item.icon).foregroundStyle(item.isFolder ? Color.accentColor : Color.secondary)
        }
            .fontWeight(item.depth == 0 && item.isFolder ? .semibold : (open ? .semibold : .regular))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { if !item.isFolder { openDocument(item) } }
            .contextMenu {
                if item.isFolder {
                    Button("New Document…") { askNewDocument(in: item.url) }
                    Button("New Folder…") { askNewFolder(in: item.url) }
                    Divider()
                } else {
                    Button("Open") { openDocument(item) }
                }
                Button("Rename…") { askRename(item) }
                Button("Show in Finder") { store.reveal(item.url) }
                Divider()
                Button("Move to Trash…") { toTrash = item }
            }
    }

    private func openDocument(_ item: ProjectItem) {
        if item.inCloudOnly {
            let placeholder = item.url.deletingLastPathComponent().appendingPathComponent(".\(item.url.lastPathComponent).icloud")
            try? FileManager.default.startDownloadingUbiquitousItem(at: placeholder)
            store.lastError = "Downloading “\(item.name)” from iCloud… try again in a moment."
            return
        }
        model.openReplacingCurrent(item.url)
    }

    private func ask(_ title: String, _ placeholder: String, initial: String = "", _ action: @escaping (String) -> Void) {
        promptText = initial
        prompt = NamePrompt(title: title, placeholder: placeholder, initial: initial, action: action)
    }

    private func askNewProject() { ask("New Project", "e.g. University 2026") { store.createProject(named: $0) } }
    private func askNewSubject(in project: URL) { ask("New Subject", "e.g. Mathematics") { store.makeFolder(named: $0, in: project) } }
    private func askNewFolder(in folder: URL) { ask("New Folder", "e.g. Lecture Notes") { store.makeFolder(named: $0, in: folder) } }

    private func askNewDocument(in folder: URL) {
        ask("New Document", "e.g. Lesson 1") { name in
            if let url = store.makeDocument(named: name, in: folder) { model.openReplacingCurrent(url) }
        }
    }

    private func askRename(_ item: ProjectItem) {
        ask("Rename", item.name, initial: item.name) { name in
            guard let dest = store.rename(item, to: name), let open = model.fileURL else { return }
            // Keep the open document pointing at its file when it or a folder above it was renamed.
            if open == item.url {
                model.fileURL = dest
            } else if open.path.hasPrefix(item.url.path + "/") {
                model.fileURL = URL(fileURLWithPath: dest.path + open.path.dropFirst(item.url.path.count))
            }
        }
    }
}
