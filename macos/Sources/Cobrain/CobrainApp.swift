import AppKit
import SwiftUI

/// `Cobrain --snapshot out.png [file]`: render the main window to a PNG and exit (no screen access needed).
@MainActor func snapshotIfRequested() {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--snapshot"), args.indices.contains(i + 1) else { return }
    _ = NSApplication.shared
    if let path = ProcessInfo.processInfo.environment["COBRAIN_BOARD"] {
        let board = BoardModel()
        board.viewSize = CGSize(width: 1048, height: 700)
        board.open(URL(fileURLWithPath: path))
        board.selection = Set(board.elements.prefix(1).map(\.id))
        let host = NSHostingView(rootView: BoardRoot(preview: board).frame(width: 1100, height: 760))
        host.frame = NSRect(x: 0, y: 0, width: 1100, height: 760)
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
    let model = DocumentModel()
    if args.indices.contains(i + 2) { model.open(URL(fileURLWithPath: args[i + 2])) }
    if ProcessInfo.processInfo.environment["COBRAIN_BACKSTAGE"] != nil { model.showBackstage = true }
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

/// One window = one document model.
struct WindowRoot: View {
    @StateObject private var model = DocumentModel()
    let url: URL?

    var body: some View {
        ContentView(model: model)
            .frame(minWidth: 640, minHeight: 480)
            .focusedSceneObject(model)
            .background(WindowAccessor { model.attach(to: $0) })
            .onOpenURL { model.openReplacingCurrent($0) }
            .onAppear { if let url { model.open(url) } else if !model.opened { model.showBackstage = true } }
    }
}

/// Hands the hosting `NSWindow` to `found` once the view is in it.
struct WindowAccessor: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let w = view.window { found(w) } }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { if let w = view.window { found(w) } }
    }
}

/// Quitting asks about every document with unsaved edits, like closing each window would.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for doc in DocumentModel.openDocuments where !doc.confirmDiscardingChanges() { return .terminateCancel }
        for board in BoardModel.openBoards where !board.confirmDiscardingChanges() { return .terminateCancel }
        return .terminateNow
    }
}

@main
struct CobrainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        snapshotIfRequested()
        Updater.shared.start()
    }

    var body: some Scene {
        WindowGroup(id: "document") { WindowRoot(url: nil) }
        .commands { CobrainCommands() }
        WindowGroup("Whiteboard", id: "whiteboard", for: BoardRef.self) { $ref in BoardRoot(url: ref?.url) }
    }
}

struct CobrainCommands: Commands {
    @FocusedObject private var model: DocumentModel?
    @FocusedObject private var board: BoardModel?
    @Environment(\.openWindow) private var openWindow
    @AppStorage("checkForUpdatesAutomatically") private var autoUpdate = true

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { Updater.shared.check(userInitiated: true) }
            Toggle("Check for Updates Automatically", isOn: $autoUpdate)
        }
        CommandGroup(replacing: .newItem) {
            Button("New") { openWindow(id: "document") }.keyboardShortcut("n")
            Button("New Whiteboard") { openWindow(id: "whiteboard") }.keyboardShortcut("n", modifiers: [.command, .option])
            Button("Open…") { if let board { board.open() } else { model?.open() } }.keyboardShortcut("o")
            Button("Print…") { model?.printDocument() }.keyboardShortcut("p")
            Button("Export as PDF…") { model?.exportPDF() }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { if let board { board.save() } else { model?.save() } }.keyboardShortcut("s")
            Button("Save As…") { if let board { board.saveAs() } else { model?.saveAs() } }.keyboardShortcut("s", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { if let board { board.undo() } else { model?.run("edit.undo") } }.keyboardShortcut("z")
            Button("Redo") { if let board { board.redo() } else { model?.run("edit.redo") } }.keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(after: .pasteboard) {
            Button("Duplicate") { board?.duplicateSelection() }.keyboardShortcut("d").disabled(board == nil)
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
