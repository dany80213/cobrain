import AppKit
import PDFKit
import SwiftUI

/// Observable document state shared by the window, the menus and the page view.
final class DocumentModel: ObservableObject {
    @Published private(set) var engine: Engine
    /// Bumped after every engine change so the page view redraws.
    @Published private(set) var revision = 0
    @Published var fileURL: URL?
    @Published var zoom: CGFloat = 1.0
    @Published var lastError: String?
    @Published var dialog: DialogKind?
    @Published var showBackstage = false
    @Published var autosave = false
    private var autosaveWork: DispatchWorkItem?
    @Published private(set) var scrollToCaret = 0
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
    @Published var projectsVisible = !ProjectStore.shared.projects.isEmpty
    /// Modification date of `fileURL` when we last read or wrote it: a newer one means someone else
    /// (a classmate on a shared iCloud project) saved the file.
    private var diskDate: Date?
    private var diskWatch: Timer?

    init() {
        engine = Engine(sample: true)!
        refresh()
        diskWatch = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.reloadIfChangedOnDisk() }
    }

    private func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func changedOnDisk(_ url: URL) -> Bool {
        guard let known = diskDate, let now = modificationDate(url) else { return false }
        return now.timeIntervalSince(known) > 0.5
    }

    /// Someone else saved the open file: show their version, unless there are edits here
    /// (then saving asks what to do, see `write(to:)`).
    private func reloadIfChangedOnDisk() {
        guard let url = fileURL, changedOnDisk(url), !engine.isDirty, let e = Engine(path: url.path) else { return }
        engine = e
        diskDate = modificationDate(url)
        refresh()
        revision += 1
    }

    /// Opens `url` in this window, first saving the current document when it belongs to the open
    /// project, or asking when it is somewhere else or untitled. Does nothing if the user cancels.
    func openReplacingCurrent(_ url: URL) {
        guard url != fileURL else { return }
        if engine.isDirty {
            if let current = fileURL, let project = ProjectStore.shared.current, current.path.hasPrefix(project.path + "/") {
                write(to: current)
                if engine.isDirty { return }
            } else {
                let alert = NSAlert()
                alert.messageText = "Save changes to “\(title)”?"
                alert.informativeText = "Your changes are lost if you don’t save them."
                alert.addButton(withTitle: "Save")
                alert.addButton(withTitle: "Don’t Save")
                alert.addButton(withTitle: "Cancel")
                switch alert.runModal() {
                case .alertFirstButtonReturn:
                    save()
                    if engine.isDirty { return }
                case .alertSecondButtonReturn: break
                default: return
                }
            }
        }
        open(url)
    }

    /// Re-read the state the chrome shows (formatting at the caret, styles, headings).
    func refresh() {
        if case .success(let f) = engine.run("format.state"), let d = f as? [String: Any] { format = d }
        if styles.isEmpty { styles = engine.galleryStyles() }
        headings = engine.outline()
        if themeColors.isEmpty { themeColors = engine.themeColors() }
        contextualTabs = engine.contextualTabs()
        disabled = engine.disabledCommands()
        toggles = engine.toggleStates()
        if case .success(let i) = engine.run("file.info"), let d = i as? [String: Any] { wordCount = d["words"] as? Int ?? 0 }
        if let c = engine.caret { caretPage = c.page }
        if let p = engine.pageSize(0) { pageWidth = p.width }
    }

    private var previewCache: [String: CGImage] = [:]

    func stylePreview(_ id: String) -> CGImage? {
        let key = "\(id)#\(revision)"
        if let c = previewCache[key] { return c }
        let img = engine.stylePreview(id, width: 220, height: 30, scale: 2)
        if let img { previewCache = previewCache.filter { $0.key.hasSuffix("#\(revision)") }; previewCache[key] = img }
        return img
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
        handleUIRequests()
        refresh()
        revision += 1
        scheduleAutosave()
    }

    /// AutoSave: write the file two seconds after the last change (only for a document that has a file).
    private func scheduleAutosave() {
        guard autosave, let url = fileURL else { return }
        autosaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.write(to: url) }
        autosaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func share() {
        guard let url = fileURL else { exportPDF(); return }
        let picker = NSSharingServicePicker(items: [url])
        if let v = NSApp.keyWindow?.contentView { picker.show(relativeTo: .zero, of: v, preferredEdge: .minY) }
    }

    /// The engine asks the UI for things (open a dialog, a file panel, scroll to the caret).
    private func handleUIRequests() {
        for r in engine.takeUIRequests() {
            if r["scrollTo"] != nil { scrollToCaret += 1; continue }
            guard let open = r["open"] as? String else { continue }
            switch open {
            case "font": dialog = .font
            case "paragraph": dialog = .paragraph
            case "pageSetup": dialog = .pageSetup
            case "link": dialog = .link
            case "goto": dialog = .goTo
            case "find": dialog = .findReplace
            case "zoom": dialog = .zoom
            case "saveAs": saveAs()
            case "openFile": self.open()
            case "exportPdf": exportPDF()
            case "commands": dialog = .commandSearch
            default: dialog = .unavailable(open)
            }
        }
    }

    /// Runs a command id coming from a shortcut; file commands that need a panel are handled here.
    func perform(shortcutCommand id: String) {
        switch id {
        case "file.save": save()
        case "file.saveAs": saveAs()
        case "file.open": open()
        case "file.new": newDocument()
        case "file.print": printDocument()
        default: run(id)
        }
    }

    func printDocument() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cobrain-print-\(UUID().uuidString).pdf")
        guard engine.save(to: tmp.path), let pdf = PDFDocument(url: tmp) else { lastError = "Could not prepare the document for printing"; return }
        pdf.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true)?.run()
    }

    func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(to: url)
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

    func click(page: Int, x: CGFloat, y: CGFloat, extend: Bool = false) {
        engine.click(page: page, x: x, y: y, extend: extend)
        refresh()
        revision += 1
    }

    func newDocument() {
        guard let e = Engine() else { return }
        engine = e
        fileURL = nil
        diskDate = nil
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
        diskDate = modificationDate(url)
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

    func write(to url: URL) {
        var url = url
        if url == fileURL, changedOnDisk(url) {
            // Shared project: a classmate saved this file since we opened it. Never overwrite their work silently.
            let alert = NSAlert()
            alert.messageText = "“\(url.lastPathComponent)” was changed by someone else"
            alert.informativeText = "Someone saved a newer version while you were editing. Save yours as a separate copy to keep both."
            alert.addButton(withTitle: "Save as Copy")
            alert.addButton(withTitle: "Replace Their Version")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let stamp = DateFormatter()
                stamp.dateFormat = "yyyy-MM-dd HH.mm"
                let name = "\(url.deletingPathExtension().lastPathComponent) (my copy \(stamp.string(from: Date())))"
                url = url.deletingLastPathComponent().appendingPathComponent(name).appendingPathExtension(url.pathExtension)
                fileURL = url
            case .alertSecondButtonReturn: break
            default: return
            }
        }
        lastError = engine.save(to: url.path) ? nil : "Could not save \(url.lastPathComponent)"
        if url == fileURL { diskDate = modificationDate(url) }
        objectWillChange.send()
    }
}
