import SwiftUI

@main
struct CobrainApp: App {
    @StateObject private var model = DocumentModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 640, minHeight: 480)
                .focusedSceneObject(model)
                .onOpenURL { model.open($0) }
        }
        .commands { CobrainCommands() }
    }
}

struct CobrainCommands: Commands {
    @FocusedObject private var model: DocumentModel?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { model?.newDocument() }.keyboardShortcut("n")
            Button("Open…") { model?.open() }.keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { model?.save() }.keyboardShortcut("s")
            Button("Save As…") { model?.saveAs() }.keyboardShortcut("s", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { model?.run("edit.undo") }.keyboardShortcut("z")
            Button("Redo") { model?.run("edit.redo") }.keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandMenu("Format") {
            Button("Bold") { model?.run("format.bold") }.keyboardShortcut("b")
            Button("Italic") { model?.run("format.italic") }.keyboardShortcut("i")
            Button("Underline") { model?.run("format.underline") }.keyboardShortcut("u")
        }
        CommandGroup(after: .toolbar) {
            Button("Zoom In") { model?.zoom = min(4, (model?.zoom ?? 1) + 0.1) }.keyboardShortcut("+")
            Button("Zoom Out") { model?.zoom = max(0.25, (model?.zoom ?? 1) - 0.1) }.keyboardShortcut("-")
            Button("Actual Size") { model?.zoom = 1 }.keyboardShortcut("0")
        }
    }
}
