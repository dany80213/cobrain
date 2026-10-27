import SwiftUI

/// A whiteboard file open on iPad: loads it, saves it by itself after every change.
struct BoardScreen: View {
    let url: URL
    @ObservedObject var library: Library
    @StateObject private var board = BoardModel()
    @Environment(\.scenePhase) private var phase
    @State private var saveWork: DispatchWorkItem?
    @State private var loaded = false
    @State private var savingTemplate = false

    var body: some View {
        BoardPadView(board: board)
            .navigationTitle(url.deletingPathExtension().lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let d = try? Data(contentsOf: url) { try? board.load(d) }
                board.fitContent()
                board.fileURL = url
                // The Pencil should draw as soon as the board opens, not select.
                board.tool = .pen
            }
            .onChange(of: board.dirty) { _, d in if d { scheduleSave() } }
            .onChange(of: board.elements) { _, _ in scheduleSave() }
            .onChange(of: phase) { _, p in if p != .active { saveNow(final: true) } }
            .onDisappear { saveNow(final: true); library.reload() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu { Button { savingTemplate = true } label: { Label("Save as Template…", systemImage: "square.and.arrow.down.on.square") } } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $savingTemplate) {
                let store = TemplateStore(root: library.folder)
                SaveTemplateForm(subject: store.subject(of: url), name: url.deletingPathExtension().lastPathComponent) { name, all in
                    saveNow(final: true)
                    store.save(copyOf: url, name: name, scope: all ? nil : store.subject(of: url))
                    savingTemplate = false
                } onCancel: { savingTemplate = false }
            }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { saveNow() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: w)
    }

    /// `final`: the screen is going away, so finish any text being typed first.
    private func saveNow(final: Bool = false) {
        saveWork?.cancel()
        if final { board.endEditingForSave() } else if board.editing != nil { return }
        guard board.dirty, let data = try? board.encoded() else { return }
        if (try? data.write(to: url, options: .atomic)) != nil { board.dirty = false }
    }
}
