import SwiftUI
import UIKit

/// The files Cobrain shows on Home: everything in the app's Documents folder (visible in the Files app).
enum FileKind: String {
    case word, board
    init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "cobrainboard": self = .board
        case "docx", "doc", "rtf", "odt", "md", "txt", "html": self = .word
        default: return nil
        }
    }
}

struct LibraryItem: Identifiable, Hashable {
    var url: URL
    var kind: FileKind
    var modified: Date
    /// The subject (notebook) folder it is in, nil for a loose file.
    var subject: String?
    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

struct Subject: Identifiable, Hashable {
    var url: URL
    var style: SubjectStyle
    var count: Int
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// The app's Documents folder is the project: folders in it are subjects (notebooks), files in them are documents and whiteboards.
/// It is the same layout as the Mac app's projects, so a project kept in iCloud Drive looks the same on both.
final class Library: ObservableObject {
    @Published private(set) var subjects: [Subject] = []
    /// Every file, newest first (loose files and files in subjects).
    @Published private(set) var items: [LibraryItem] = []
    let folder: URL

    init() {
        folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        reload()
    }

    private func files(in dir: URL, subject: String?) -> [LibraryItem] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.compactMap { u in
            guard let k = FileKind(url: u) else { return nil }
            let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return LibraryItem(url: u, kind: k, modified: d, subject: subject)
        }
    }

    func reload() {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        var subs: [Subject] = []
        var all = files(in: folder, subject: nil)
        for u in entries where (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && !u.lastPathComponent.hasPrefix(".") {
            let inside = files(in: u, subject: u.lastPathComponent)
            subs.append(Subject(url: u, style: SubjectStyle.load(from: u), count: inside.count))
            all += inside
        }
        subjects = subs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        items = all.sorted { $0.modified > $1.modified }
    }

    func items(in subject: Subject) -> [LibraryItem] { items.filter { $0.url.deletingLastPathComponent().standardizedFileURL == subject.url.standardizedFileURL } }
    var looseItems: [LibraryItem] { items.filter { $0.subject == nil } }

    /// A free file name in `dir`: "Untitled.docx", "Untitled 2.docx", …
    func freshURL(_ base: String, ext: String, in dir: URL? = nil) -> URL {
        var n = 1
        while true {
            let name = n == 1 ? base : "\(base) \(n)"
            let u = (dir ?? folder).appendingPathComponent(name).appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: u.path) { return u }
            n += 1
        }
    }

    /// A new word document from a template, saved at once so it shows up on Home.
    func newDocument(template: String, in dir: URL? = nil) -> URL? {
        guard let e = Engine() else { return nil }
        if template != "blank" { _ = e.run("file.new", ["template": template]) }
        let u = freshURL("Untitled", ext: "docx", in: dir)
        guard e.save(to: u.path) else { return nil }
        reload()
        return u
    }

    func newBoard(in dir: URL? = nil) -> URL? {
        let u = freshURL("Untitled whiteboard", ext: "cobrainboard", in: dir)
        guard let data = try? BoardModel().encoded(), (try? data.write(to: u)) != nil else { return nil }
        reload()
        return u
    }

    /// Copy a file picked with the Files app into the library (or into a subject).
    func importFile(_ url: URL, into dir: URL? = nil) -> URL? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard FileKind(url: url) != nil else { return nil }
        let target = dir ?? folder
        if url.deletingLastPathComponent().standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path) { return url }
        let dest = freshURL(url.deletingPathExtension().lastPathComponent, ext: url.pathExtension, in: target)
        do { try FileManager.default.copyItem(at: url, to: dest) } catch { return nil }
        reload()
        return dest
    }

    func delete(_ item: LibraryItem) {
        try? FileManager.default.removeItem(at: item.url)
        reload()
    }

    func rename(_ item: LibraryItem, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty, !clean.hasPrefix(".") else { return }
        let dest = item.url.deletingLastPathComponent().appendingPathComponent(clean).appendingPathExtension(item.url.pathExtension)
        guard dest != item.url, !FileManager.default.fileExists(atPath: dest.path) else { return }
        try? FileManager.default.moveItem(at: item.url, to: dest)
        reload()
    }

    /// Move a file into a subject, or back out to the loose files (`nil`).
    func move(_ item: LibraryItem, to subject: Subject?) {
        let dir = subject?.url ?? folder
        guard item.url.deletingLastPathComponent().standardizedFileURL != dir.standardizedFileURL else { return }
        let dest = freshURL(item.url.deletingPathExtension().lastPathComponent, ext: item.url.pathExtension, in: dir)
        try? FileManager.default.moveItem(at: item.url, to: dest)
        reload()
    }

    // MARK: Subjects
    @discardableResult
    func createSubject(name: String, style: SubjectStyle) -> URL? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty, !clean.hasPrefix(".") else { return nil }
        var url = folder.appendingPathComponent(clean)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) { url = folder.appendingPathComponent("\(clean) \(n)"); n += 1 }
        guard (try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)) != nil else { return nil }
        style.save(to: url)
        reload()
        return url
    }

    func updateSubject(_ s: Subject, name: String, style: SubjectStyle) {
        var url = s.url
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        if !clean.isEmpty, !clean.hasPrefix("."), clean != s.name {
            let dest = folder.appendingPathComponent(clean)
            if !FileManager.default.fileExists(atPath: dest.path), (try? FileManager.default.moveItem(at: s.url, to: dest)) != nil { url = dest }
        }
        style.save(to: url)
        reload()
    }

    func deleteSubject(_ s: Subject) {
        try? FileManager.default.removeItem(at: s.url)
        reload()
    }
}

/// Thumbnails for the tiles (documents, whiteboards, templates), made on demand and kept.
@MainActor final class Thumbnails {
    static let shared = Thumbnails()
    private var cache: [String: UIImage] = [:]

    func image(for item: LibraryItem) -> UIImage? { FileThumbnails.image(for: item.url).map { UIImage(cgImage: $0) } }

    func template(_ id: String) -> UIImage? {
        if let c = cache["tpl:\(id)"] { return c }
        guard let e = Engine() else { return nil }
        if id != "blank" { _ = e.run("file.new", ["template": id]) }
        guard let size = e.pageSize(0), let cg = e.renderPage(0, scale: 340 / size.width) else { return nil }
        let img = UIImage(cgImage: cg)
        cache["tpl:\(id)"] = img
        return img
    }
}

/// WordCraft's own icons (drawn in code upstream), bundled as PNGs.
enum Icons {
    private static var cache: [String: UIImage] = [:]
    static func image(_ name: String) -> UIImage? {
        if let i = cache[name] { return i }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("icons/\(name).png"), let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache[name] = img
        return img
    }
}

struct RibbonIcon: View {
    let name: String
    var size: CGFloat = 22
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let img = Icons.image(name) {
            // Dark mode: WordCraft draws its icons for a light ribbon; invert lightness, keep hues.
            Image(uiImage: img).resizable().interpolation(.high).frame(width: size, height: size)
                .modifier(DarkIcon(dark: scheme == .dark))
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

struct DarkIcon: ViewModifier {
    let dark: Bool
    func body(content: Content) -> some View {
        if dark { content.colorInvert().hueRotation(.degrees(180)) } else { content }
    }
}
