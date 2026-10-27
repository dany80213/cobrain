import AppKit
import SwiftUI

/// One whiteboard window.
struct BoardRoot: View {
    @StateObject private var board: BoardModel

    private let url: URL?

    init(url: URL? = nil) { _board = StateObject(wrappedValue: BoardModel()); self.url = url }
    /// Snapshot mode: show an existing model.
    init(preview: BoardModel) { _board = StateObject(wrappedValue: preview); url = nil }

    var body: some View {
        VStack(spacing: 0) {
            BoardTopBar(board: board)
            Divider()
            HStack(spacing: 0) {
                BoardToolPalette(board: board)
                Divider()
                BoardCanvas(board: board)
            }
        }
        .frame(minWidth: 860, minHeight: 540)
        .background(WindowAccessor { board.attach(to: $0) })
        .navigationTitle(board.title)
        .focusedSceneObject(board)
        .onAppear { if let url, board.fileURL == nil { board.open(url) } }
    }
}

struct BoardToolPalette: View {
    @ObservedObject var board: BoardModel

    var body: some View {
        VStack(spacing: 4) {
            ForEach(BoardTool.allCases) { t in
                Button { board.endEditing(); board.tool = t } label: {
                    Image(systemName: t.symbol).font(.system(size: 15)).frame(width: 34, height: 34)
                        .background(board.tool == t ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(t.label)
                if t == .hand || t == .star || t == .arrow { Divider().frame(width: 24) }
            }
            Spacer()
        }
        .padding(8).frame(width: 52).background(Color(nsColor: .windowBackgroundColor))
    }
}

struct BoardTopBar: View {
    @ObservedObject var board: BoardModel

    private let swatches: [UInt32] = [0x7C6CF0, 0x4C9AFF, 0x36B37E, 0xFFAB00, 0xFF5630, 0xF06CAB, 0x2B2B33, 0xFFFFFF]

    private func colorBinding(_ get: @escaping () -> BoardColor, _ set: @escaping (BoardColor) -> Void) -> Binding<Color> {
        Binding(get: { get().color }, set: { set(BoardColor($0)) })
    }

    private var shown: BoardElement? { board.selection.first.flatMap { board.element($0) } }

    var body: some View {
        HStack(spacing: 10) {
            Button { board.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!board.canUndo).help("Undo")
            Button { board.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!board.canRedo).help("Redo")
            Divider().frame(height: 20)
            Text("Fill").font(.caption).foregroundStyle(.secondary)
            ColorPicker("Fill", selection: colorBinding({ shown?.fill ?? board.fill }, board.setFill), supportsOpacity: true).labelsHidden()
            HStack(spacing: 3) {
                ForEach(swatches, id: \.self) { v in
                    Button { board.setFill(.hex(v)) } label: {
                        Circle().fill(BoardColor.hex(v).color).frame(width: 15, height: 15).overlay(Circle().stroke(Color.gray.opacity(0.5), lineWidth: 0.5))
                    }.buttonStyle(.plain)
                }
                Button { board.setFill(.clear) } label: { Image(systemName: "nosign").font(.system(size: 13)) }.buttonStyle(.plain).help("No fill")
            }
            Text("Line").font(.caption).foregroundStyle(.secondary)
            ColorPicker("Line", selection: colorBinding({ shown?.stroke ?? board.stroke }, board.setStroke), supportsOpacity: true).labelsHidden()
            Slider(value: Binding(get: { shown?.lineWidth ?? board.lineWidth }, set: board.setLineWidth), in: 0...16, step: 1).frame(width: 80)
                .help("Line width")
            Stepper(value: Binding(get: { shown?.fontSize ?? board.fontSize }, set: board.setFontSize), in: 8...96, step: 2) {
                Image(systemName: "textformat.size")
            }.help("Text size")
            Divider().frame(height: 20)
            Button { board.bringToFront() } label: { Image(systemName: "square.3.layers.3d.top.filled") }.help("Bring to front")
            Button { board.sendToBack() } label: { Image(systemName: "square.3.layers.3d.bottom.filled") }.help("Send to back")
            Button { board.duplicateSelection() } label: { Image(systemName: "plus.square.on.square") }.help("Duplicate (⌘D)")
            Button { board.deleteSelection() } label: { Image(systemName: "trash") }.help("Delete")
            Spacer()
            Button { board.zoom(by: 1 / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }.help("Zoom out")
            Text("\(Int((board.zoom * 100).rounded()))%").font(.system(size: 12).monospacedDigit()).frame(width: 44)
            Button { board.zoom(by: 1.25) } label: { Image(systemName: "plus.magnifyingglass") }.help("Zoom in")
            Button { board.fitContent() } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }.help("Fit to content")
            Divider().frame(height: 20)
            Button { board.open() } label: { Image(systemName: "folder") }.help("Open…")
            Button { board.save() } label: { Image(systemName: "square.and.arrow.down") }.help("Save")
            Button { board.exportPNG() } label: { Image(systemName: "photo") }.help("Export PNG…")
        }
        .buttonStyle(.borderless).padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct BoardCanvas: View {
    @ObservedObject var board: BoardModel
    @FocusState private var focused: Bool

    var body: some View {
        BoardSurface(board: board)
            .overlay {
                ScrollPanner { dx, dy, command, loc in
                    if command { board.zoom(by: exp(dy * 0.01), around: loc) } else { board.pan.width += dx / board.zoom; board.pan.height += dy / board.zoom }
                }.allowsHitTesting(false)
            }
            .focusable().focused($focused).focusEffectDisabled()
            .onAppear { focused = true }
            .onTapGesture { focused = true }
            .onKeyPress(.delete) { board.editing == nil ? { board.deleteSelection(); return .handled }() : .ignored }
            .onKeyPress(.deleteForward) { board.editing == nil ? { board.deleteSelection(); return .handled }() : .ignored }
            .onKeyPress(.escape) { board.endEditing(); board.selection = []; board.tool = .select; focused = true; return .handled }
    }
}

/// Reports trackpad / mouse-wheel scrolling over the canvas (pan; ⌘ + scroll zooms).
struct ScrollPanner: NSViewRepresentable {
    let onScroll: (CGFloat, CGFloat, Bool, CGPoint) -> Void

    func makeNSView(context: Context) -> Probe { let v = Probe(); v.onScroll = onScroll; return v }
    func updateNSView(_ v: Probe, context: Context) { v.onScroll = onScroll }

    final class Probe: NSView {
        var onScroll: ((CGFloat, CGFloat, Bool, CGPoint) -> Void)?
        private var monitor: Any?
        override var isFlipped: Bool { true }
        override func viewDidMoveToWindow() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
                guard let self, e.window === self.window else { return e }
                let p = self.convert(e.locationInWindow, from: nil)
                guard self.bounds.contains(p) else { return e }
                self.onScroll?(e.scrollingDeltaX, e.scrollingDeltaY, e.modifierFlags.contains(.command), p)
                return nil
            }
        }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}
