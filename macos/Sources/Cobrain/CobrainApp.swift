import AppKit
import SwiftUI

/// `Cobrain --snapshot out.png [file]`: render the main window to a PNG and exit (no screen access needed).
@MainActor func snapshotIfRequested() {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--snapshot"), args.indices.contains(i + 1) else { return }
    _ = NSApplication.shared
    let model = DocumentModel()
    if args.indices.contains(i + 2) { model.open(URL(fileURLWithPath: args[i + 2])) }
    // COBRAIN_CMDS='[["select.text",{"text":"Equipment"}]]' runs engine commands before the snapshot.
    if let raw = ProcessInfo.processInfo.environment["COBRAIN_CMDS"], let data = raw.data(using: .utf8),
       let cmds = try? JSONSerialization.jsonObject(with: data) as? [[Any]] {
        for c in cmds { if let id = c.first as? String { model.run(id, c.count > 1 ? (c[1] as? [String: Any]) ?? [:] : [:]) } }
    }
    let W = CGFloat(Double(ProcessInfo.processInfo.environment["COBRAIN_WIDTH"] ?? "") ?? 1100)
    let host: NSHostingView<AnyView>
    if let d = ProcessInfo.processInfo.environment["COBRAIN_DIALOG"] {
        let kind: DialogKind = ["font": .font, "paragraph": .paragraph, "pageSetup": .pageSetup, "find": .findReplace, "symbol": .symbol,
                                "insertTable": .insertTable, "link": .link][d] ?? .zoom
        host = NSHostingView(rootView: AnyView(DialogView(kind: kind, model: model).background(Color(nsColor: .windowBackgroundColor)).frame(width: W, height: 760, alignment: .topLeading)))
    } else if ProcessInfo.processInfo.environment["COBRAIN_WIDGET"] != nil {
        host = NSHostingView(rootView: AnyView(HStack(alignment: .top, spacing: 12) {
            TableGridView { _, _ in }
            ColorGridView(theme: model.themeColors, pick: { _ in }, more: {})
            SymbolGridView { _ in }
        }.padding().background(Color.white).frame(width: 1100, height: 760, alignment: .topLeading)))
    } else {
        host = NSHostingView(rootView: AnyView(ContentView(model: model).frame(width: W, height: 760)))
    }
    host.frame = NSRect(x: 0, y: 0, width: W, height: 760)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    host.layoutSubtreeIfNeeded()
    if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
    }
    exit(0)
}

@main
struct CobrainApp: App {
    init() { snapshotIfRequested() }

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
