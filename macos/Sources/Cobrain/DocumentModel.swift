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
    private(set) lazy var catalog: [CommandInfo] = engine.commands()

    @Published private(set) var format: [String: Any] = [:]
    @Published private(set) var styles: [(id: String, name: String)] = []
    @Published private(set) var headings: [Engine.Heading] = []
    @Published private(set) var wordCount = 0
    @Published private(set) var themeColors: [String] = []
    @Published private(set) var contextualTabs: [String] = []
    @Published private(set) var disabled: Set<String> = []
    @Published private(set) var toggles: [String: Bool] = [:]
    @Published private(set) var caretPage = 0
    @Published private(set) var pageWidth: CGFloat = 612
    @Published var navigationVisible = true

    init() {
        engine = Engine(sample: true)!
        refresh()
    }

    /// Re-read the state the chrome shows (formatting at the caret, styles, headings).
    func refresh() {
        if case .success(let f) = engine.run("format.state"), let d = f as? [String: Any] { format = d }
        if styles.isEmpty, case .success(let l) = engine.run("styles.list"), let arr = l as? [[String: Any]] {
            styles = arr.filter { ($0["kind"] as? String) == "paragraph" && ($0["quick"] as? Bool) == true }
                .compactMap { d in (d["id"] as? String).flatMap { id in (d["name"] as? String).map { (id, $0) } } }
        }
        headings = engine.outline()
        if themeColors.isEmpty { themeColors = engine.themeColors() }
        contextualTabs = engine.contextualTabs()
        disabled = engine.disabledCommands()
        toggles = engine.toggleStates()
        if case .success(let i) = engine.run("file.info"), let d = i as? [String: Any] { wordCount = d["words"] as? Int ?? 0 }
        if let c = engine.caret { caretPage = c.page }
        if let p = engine.pageSize(0) { pageWidth = p.width }
    }

    func isOn(_ key: String) -> Bool { (format[key] as? Bool) == true }
    func isEnabled(_ cmd: String) -> Bool { cmd.isEmpty || !disabled.contains(cmd) }

    /// Pressed state of a toggle command: formatting at the caret, or a document/view flag.
    func isPressed(_ cmd: String) -> Bool {
        if let t = toggles[cmd] { return t }
        let formatKeys = ["format.bold": "bold", "format.italic": "italic", "format.underline": "underline", "format.strikethrough": "strike",
                          "format.subscript": "subscript", "format.superscript": "superscript", "format.border": "border"]
        return formatKeys[cmd].map(isOn) ?? false
    }


    var title: String { fileURL?.lastPathComponent ?? "Untitled" }

    func run(_ id: String, _ params: [String: Any] = [:]) {
        switch engine.run(id, params) {
        case .success(let r):
            lastError = nil
            handleClipboard(id, r)
        case .failure(let e): lastError = e.message
        }
        refresh()
        revision += 1
    }

    /// Cut/Copy put the engine's clipboard payload on the system pasteboard; Paste feeds it back.
    private func handleClipboard(_ id: String, _ result: Any) {
        guard id == "edit.copy" || id == "edit.cut", let d = result as? [String: Any] else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        if let html = d["html"] as? String { pb.setString(html, forType: .html) }
        if let text = d["text"] as? String { pb.setString(text, forType: .string) }
    }

    func paste() {
        let pb = NSPasteboard.general
        if let html = pb.string(forType: .html) { run("edit.paste", ["html": html, "text": pb.string(forType: .string) ?? ""]) }
        else if let t = pb.string(forType: .string) { run("edit.paste", ["text": t]) }
    }

    func click(page: Int, x: CGFloat, y: CGFloat) {
        engine.click(page: page, x: x, y: y)
        refresh()
        revision += 1
    }

    func newDocument() {
        guard let e = Engine() else { return }
        engine = e
        fileURL = nil
        refresh()
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
        refresh()
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
