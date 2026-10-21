import AppKit
import SwiftUI

/// Observable document state shared by the window, the menus and the page view.
final class DocumentModel: ObservableObject {
    @Published private(set) var engine: Engine
    /// Bumped after every engine change so the page view redraws.
    @Published private(set) var revision = 0
    @Published var fileURL: URL?
    @Published var zoom: CGFloat = 1.0
    @Published var lastError: String?

    init() {
        engine = Engine()!
    }

    var title: String { fileURL?.lastPathComponent ?? "Untitled" }

    func run(_ id: String, _ params: [String: Any] = [:]) {
        switch engine.run(id, params) {
        case .success: lastError = nil
        case .failure(let e): lastError = e.message
        }
        revision += 1
    }

    func click(page: Int, x: CGFloat, y: CGFloat) {
        engine.click(page: page, x: x, y: y)
        revision += 1
    }

    func newDocument() {
        guard let e = Engine() else { return }
        engine = e
        fileURL = nil
        revision += 1
    }

    func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["docx", "doc", "rtf", "odt", "md", "txt", "html"].compactMap { .init(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL) {
        guard let e = Engine(path: url.path) else {
            lastError = "Could not open \(url.lastPathComponent)"
            return
        }
        engine = e
        fileURL = url
        lastError = nil
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        revision += 1
    }

    func save() {
        if let url = fileURL { write(to: url) } else { saveAs() }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = ["docx", "pdf", "rtf", "odt", "md", "txt", "html"].compactMap { .init(filenameExtension: $0) }
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Untitled.docx"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(to: url)
        if url.pathExtension.lowercased() != "pdf" { fileURL = url }
    }

    private func write(to url: URL) {
        lastError = engine.save(to: url.path) ? nil : "Could not save \(url.lastPathComponent)"
        objectWillChange.send()
    }
}
