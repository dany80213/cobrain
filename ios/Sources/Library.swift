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
    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

final class Library: ObservableObject {
    @Published private(set) var items: [LibraryItem] = []
    let folder: URL

    init() {
        folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        reload()
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        items = urls.compactMap { u in
            guard let k = FileKind(url: u) else { return nil }
            let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return LibraryItem(url: u, kind: k, modified: d)
        }.sorted { $0.modified > $1.modified }
    }

    /// A free file name in the folder: "Untitled.docx", "Untitled 2.docx", …
    func freshURL(_ base: String, ext: String) -> URL {
        var n = 1
        while true {
            let name = n == 1 ? base : "\(base) \(n)"
            let u = folder.appendingPathComponent(name).appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: u.path) { return u }
            n += 1
        }
    }

    /// A new word document from a template, saved at once so it shows up on Home.
    func newDocument(template: String) -> URL? {
        guard let e = Engine() else { return nil }
        if template != "blank" { _ = e.run("file.new", ["template": template]) }
        let u = freshURL("Untitled", ext: "docx")
        guard e.save(to: u.path) else { return nil }
        reload()
        return u
    }

    func newBoard() -> URL? {
        let u = freshURL("Untitled whiteboard", ext: "cobrainboard")
        guard let data = try? BoardModel().encoded(), (try? data.write(to: u)) != nil else { return nil }
        reload()
        return u
    }

    /// Copy a file picked with the Files app into the library.
    func importFile(_ url: URL) -> URL? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard FileKind(url: url) != nil else { return nil }
        if url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL { return url }
        let dest = freshURL(url.deletingPathExtension().lastPathComponent, ext: url.pathExtension)
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
        guard !clean.isEmpty else { return }
        let dest = folder.appendingPathComponent(clean).appendingPathExtension(item.url.pathExtension)
        guard dest != item.url, !FileManager.default.fileExists(atPath: dest.path) else { return }
        try? FileManager.default.moveItem(at: item.url, to: dest)
        reload()
    }
}

/// First-page thumbnails for Home, made on demand and kept.
@MainActor final class Thumbnails {
    static let shared = Thumbnails()
    private var cache: [String: UIImage] = [:]

    func image(for item: LibraryItem) -> UIImage? {
        let key = "\(item.url.path)#\(item.modified.timeIntervalSince1970)"
        if let c = cache[key] { return c }
        let img: UIImage?
        switch item.kind {
        case .word:
            guard let e = Engine(path: item.url.path), let size = e.pageSize(0), let cg = e.renderPage(0, scale: 340 / size.width) else { return nil }
            img = UIImage(cgImage: cg)
        case .board:
            guard let data = try? Data(contentsOf: item.url) else { return nil }
            let board = BoardModel()
            try? board.load(data)
            img = board.renderPNG(scale: 1).flatMap(UIImage.init(data:))
        }
        if let img { cache[key] = img }
        return img
    }

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
