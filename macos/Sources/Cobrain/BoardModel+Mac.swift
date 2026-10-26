import AppKit
import SwiftUI

// macOS side of the whiteboard model: window, file panels, PNG export.
extension BoardModel {
    fileprivate static let registry = NSHashTable<BoardModel>.weakObjects()
    static var openBoards: [BoardModel] { registry.allObjects }

    /// Once the SwiftUI window exists: ask before it closes with unsaved edits, show the edited dot.
    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        Self.registry.add(self)
        let guardian = WindowCloseGuard(confirm: { [weak self] in self?.confirmDiscardingChanges() ?? true }, original: window.delegate)
        closeGuard = guardian
        window.delegate = guardian
        window.isDocumentEdited = dirty
        window.representedURL = fileURL
    }

    /// Before the board goes away (window closed, app quit, another file opened): Save / Don't Save / Cancel
    /// when it has edits. False when the user cancelled or saving failed.
    func confirmDiscardingChanges() -> Bool {
        endEditing()
        guard dirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes you made to “\(fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled whiteboard")”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")
        switch runSheet(alert) {
        case .alertFirstButtonReturn: save(); return !dirty
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    // Sheets on the board's window: a free-standing modal opens on another Space when the window is full screen.
    private func runSheet(_ alert: NSAlert) -> NSApplication.ModalResponse {
        guard let window, window.isVisible, window.attachedSheet == nil else { return alert.runModal() }
        window.makeKeyAndOrderFront(nil)
        alert.beginSheetModal(for: window) { NSApp.stopModal(withCode: $0) }
        return NSApp.runModal(for: alert.window)
    }
    private func runSheet(_ panel: NSSavePanel) -> NSApplication.ModalResponse {
        guard let window, window.isVisible, window.attachedSheet == nil else { return panel.runModal() }
        window.makeKeyAndOrderFront(nil)
        panel.beginSheetModal(for: window) { NSApp.stopModal(withCode: $0) }
        return NSApp.runModal(for: panel)
    }

    func save() { if let url = fileURL { write(to: url) } else { saveAs() } }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "cobrainboard")].compactMap { $0 }
        panel.nameFieldStringValue = (fileURL?.lastPathComponent ?? "Untitled.cobrainboard")
        guard runSheet(panel) == .OK, let url = panel.url else { return }
        write(to: url)
    }

    private func write(to url: URL) {
        do {
            try encoded().write(to: url, options: .atomic)
            fileURL = url; dirty = false; window?.representedURL = url
        } catch {
            let a = NSAlert(); a.messageText = "Could not save \(url.lastPathComponent)"; a.informativeText = error.localizedDescription; a.runModal()
        }
    }

    func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "cobrainboard")].compactMap { $0 }
        guard confirmDiscardingChanges(), runSheet(panel) == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL) {
        do {
            try load(Data(contentsOf: url))
            fileURL = url
            fitContent()
        } catch {
            let a = NSAlert(); a.messageText = "Could not open \(url.lastPathComponent)"; a.informativeText = error.localizedDescription; a.runModal()
        }
    }

    @MainActor func exportPNG() {
        guard let first = elements.first else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = (fileURL?.deletingPathExtension().lastPathComponent ?? "Whiteboard") + ".png"
        guard runSheet(panel) == .OK, let url = panel.url else { return }
        _ = first
        if let png = renderPNG() { try? png.write(to: url) }
    }
}
