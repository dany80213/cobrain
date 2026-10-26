import SwiftUI
import UIKit

/// A word document open on iPad: the engine session plus the state the chrome shows.
/// Every action is an engine command (`run`); nothing about the document is implemented here.
final class PadDocument: ObservableObject {
    @Published private(set) var engine: Engine
    /// Bumped after every engine change so pages redraw.
    @Published private(set) var revision = 0
    @Published var zoom: CGFloat = 1
    @Published var lastError: String?
    @Published private(set) var format: [String: Any] = [:]
    @Published private(set) var styles: [(id: String, name: String)] = []
    @Published private(set) var disabled: Set<String> = []
    @Published private(set) var toggles: [String: Bool] = [:]
    @Published private(set) var marks: (selection: [[Double]], find: [[Double]]) = ([], [])
    @Published private(set) var caret: Engine.Caret?
    @Published private(set) var wordCount = 0
    @Published private(set) var pageCount = 1
    @Published var keyboardWanted = false
    @Published var findOpen = false
    let url: URL
    private var saveWork: DispatchWorkItem?
    private var dirty = false

    init?(url: URL) {
        guard let e = Engine(path: url.path) else { return nil }
        engine = e
        self.url = url
        refresh()
    }

    func refresh() {
        if case .success(let f) = engine.run("format.state"), let d = f as? [String: Any] { format = d }
        if styles.isEmpty { styles = engine.galleryStyles() }
        disabled = engine.disabledCommands()
        toggles = engine.toggleStates()
        marks = engine.selectionRects()
        caret = engine.caret
        pageCount = engine.pageCount
        if case .success(let i) = engine.run("file.info"), let d = i as? [String: Any] { wordCount = d["words"] as? Int ?? 0 }
    }

    func isOn(_ key: String) -> Bool { (format[key] as? Bool) == true }
    func isEnabled(_ cmd: String) -> Bool { !disabled.contains(cmd) }
    func isPressed(_ cmd: String) -> Bool {
        if let t = toggles[cmd] { return t }
        let keys = ["format.bold": "bold", "format.italic": "italic", "format.underline": "underline", "format.strikethrough": "strike"]
        return keys[cmd].map(isOn) ?? false
    }

    @discardableResult
    func run(_ id: String, _ params: [String: Any] = [:]) -> Bool {
        var ok = true
        switch engine.run(id, params) {
        case .success(let r): lastError = nil; clipboard(id, r)
        case .failure(let e): lastError = e.message; ok = false
        }
        _ = engine.takeUIRequests()
        refresh()
        revision += 1
        if engine.isDirty { dirty = true; scheduleSave() }
        return ok
    }

    func click(page: Int, x: CGFloat, y: CGFloat, extend: Bool = false) {
        engine.click(page: page, x: x, y: y, extend: extend)
        refresh()
        revision += 1
    }

    // MARK: Clipboard
    private func clipboard(_ id: String, _ result: Any) {
        guard id == "edit.copy" || id == "edit.cut", let d = result as? [String: Any] else { return }
        var item: [String: Any] = [:]
        if let html = d["html"] as? String { item["public.html"] = html }
        if let text = d["text"] as? String { item["public.utf8-plain-text"] = text }
        UIPasteboard.general.items = [item]
    }

    func paste() {
        let pb = UIPasteboard.general
        let text = pb.string ?? ""
        if let html = pb.value(forPasteboardType: "public.html") as? String { run("edit.paste", ["html": html, "text": text]) }
        else if !text.isEmpty { run("edit.paste", ["text": text]) }
    }

    // MARK: Saving
    /// Saved by itself two seconds after the last change, and when the screen goes away.
    private func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: w)
    }

    func saveNow() {
        saveWork?.cancel()
        guard dirty else { return }
        if engine.save(to: url.path) { dirty = false; lastError = nil } else { lastError = "Could not save \(url.lastPathComponent)" }
    }

    /// The document as a PDF in the temporary folder, for the share sheet.
    func pdfURL() -> URL? {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(url.deletingPathExtension().lastPathComponent).appendingPathExtension("pdf")
        return engine.save(to: tmp.path) ? tmp : nil
    }
}
