import AppKit
import SwiftUI

/// One whiteboard window.
struct BoardRoot: View {
    @StateObject private var board: BoardModel

    init() { _board = StateObject(wrappedValue: BoardModel()) }
    /// Snapshot mode: show an existing model.
    init(preview: BoardModel) { _board = StateObject(wrappedValue: preview) }

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

private enum BoardDrag {
    case idle
    case move(orig: [UUID: BoardElement])
    case resize(id: UUID, corner: Int, orig: BoardElement)
    case endpoint(id: UUID, index: Int)
    case create(id: UUID, start: CGPoint)
    case marquee(start: CGPoint)
    case pan(start: CGSize)
}

struct BoardCanvas: View {
    @ObservedObject var board: BoardModel
    @State private var drag: BoardDrag = .idle
    @State private var active = false
    @State private var marquee: CGRect?
    @State private var baseZoom: CGFloat?
    @FocusState private var focused: Bool
    @FocusState private var textFocus: Bool

    private let handle: CGFloat = 9

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in render(&ctx, size) }
                    .background(Color(nsColor: .textBackgroundColor))
                    .gesture(dragGesture)
                    .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { doubleClick(at: $0.location) })
                    .simultaneousGesture(MagnifyGesture().onChanged { v in
                        let base = baseZoom ?? board.zoom
                        baseZoom = base
                        board.zoom(by: base * v.magnification / board.zoom, around: v.startLocation)
                    }.onEnded { _ in baseZoom = nil })
                if let id = board.editing, let e = board.element(id) { editor(e) }
                ScrollPanner { dx, dy, command, loc in
                    if command { board.zoom(by: exp(dy * 0.01), around: loc) } else { board.pan.width += dx / board.zoom; board.pan.height += dy / board.zoom }
                }.allowsHitTesting(false)
            }
            .onAppear { board.viewSize = geo.size }
            .onChange(of: geo.size) { _, s in board.viewSize = s }
        }
        .clipped()
        .focusable().focused($focused).focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.delete) { board.editing == nil ? { board.deleteSelection(); return .handled }() : .ignored }
        .onKeyPress(.deleteForward) { board.editing == nil ? { board.deleteSelection(); return .handled }() : .ignored }
        .onKeyPress(.escape) { board.endEditing(); board.selection = []; board.tool = .select; focused = true; return .handled }
    }

    // MARK: Text editing overlay
    private func editor(_ e: BoardElement) -> some View {
        let z = board.zoom, f = e.frame
        let inset: CGFloat = e.kind == .text ? 0 : (e.kind == .sticky ? 10 : 8)
        return TextField("", text: Binding(
            get: { board.element(e.id)?.text ?? "" },
            set: { v in if let i = board.index(e.id) { board.elements[i].text = v; board.fitText(e.id); board.dirty = true } }
        ), axis: .vertical)
        .textFieldStyle(.plain)
        .multilineTextAlignment(e.kind == .text || e.kind == .sticky ? .leading : .center)
        .font(.system(size: e.fontSize * z))
        .foregroundStyle(e.kind == .sticky ? Color.black : e.stroke.color)
        .focused($textFocus)
        .frame(width: max(20, (f.width - inset * 2) * z), alignment: .topLeading)
        .position(x: (f.minX + board.pan.width + inset) * z + max(20, (f.width - inset * 2) * z) / 2,
                  y: (f.minY + board.pan.height + (e.kind == .text || e.kind == .sticky ? inset : f.height / 2 - e.fontSize / 2)) * z + e.fontSize * z * 0.7)
        .onAppear { textFocus = true }
    }

    // MARK: Rendering
    private func render(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let z = board.zoom
        ctx.scaleBy(x: z, y: z)
        ctx.translateBy(x: board.pan.width, y: board.pan.height)
        let visible = CGRect(x: -board.pan.width, y: -board.pan.height, width: size.width / z, height: size.height / z)
        if z >= 0.4 {
            let step: CGFloat = 24
            var dots = Path()
            var x = (visible.minX / step).rounded(.down) * step
            while x < visible.maxX {
                var y = (visible.minY / step).rounded(.down) * step
                while y < visible.maxY { dots.addEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6)); y += step }
                x += step
            }
            ctx.fill(dots, with: .color(.gray.opacity(0.35)))
        }
        for e in board.elements where e.id != board.editing || e.kind != .text { BoardDrawing.draw(e, in: &ctx) }
        let blue = Color.accentColor
        for id in board.selection {
            guard let e = board.element(id) else { continue }
            let r = e.frame
            if e.isLinear && e.kind != .pen {
                for p in e.points where p.count == 2 { drawHandle(&ctx, CGPoint(x: p[0], y: p[1])) }
            } else {
                ctx.stroke(Path(r), with: .color(blue), style: StrokeStyle(lineWidth: 1.5 / z))
                if board.selection.count == 1 { for c in corners(r) { drawHandle(&ctx, c) } }
            }
        }
        if let m = marquee {
            ctx.fill(Path(m), with: .color(blue.opacity(0.1)))
            ctx.stroke(Path(m), with: .color(blue), style: StrokeStyle(lineWidth: 1 / z, dash: [4 / z, 3 / z]))
        }
    }

    private func drawHandle(_ ctx: inout GraphicsContext, _ p: CGPoint) {
        let s = handle / board.zoom
        let r = CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)
        ctx.fill(Path(ellipseIn: r), with: .color(.white))
        ctx.stroke(Path(ellipseIn: r), with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5 / board.zoom))
    }

    private func corners(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
    }

    // MARK: Gestures
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let start = board.world(v.startLocation), now = board.world(v.location)
                if !active { active = true; begin(start, screen: v.startLocation, shift: NSEvent.modifierFlags.contains(.shift)) }
                update(start: start, now: now, translation: v.translation)
            }
            .onEnded { _ in end(); board.dropEmptySnapshot(); active = false; drag = .idle; marquee = nil }
    }

    private func doubleClick(at loc: CGPoint) {
        guard board.tool == .select else { return }
        let p = board.world(loc)
        if let id = board.hitTest(p), let e = board.element(id), !e.isLinear {
            board.selection = [id]; board.editing = id; textFocus = true
        } else if board.hitTest(p) == nil {
            board.snapshot()
            let e = board.newElement(.text, at: p)
            board.add(e); board.selection = [e.id]; board.editing = e.id
        }
    }

    private func begin(_ p: CGPoint, screen: CGPoint, shift: Bool) {
        focused = true
        if board.editing != nil { board.endEditing() }
        switch board.tool {
        case .hand:
            drag = .pan(start: board.pan)
        case .select:
            let slop = (handle + 3) / board.zoom
            if board.selection.count == 1, let id = board.selection.first, let e = board.element(id) {
                if e.isLinear && e.kind != .pen {
                    for (i, q) in e.points.enumerated() where q.count == 2 && hypot(p.x - q[0], p.y - q[1]) <= slop {
                        board.snapshot(); drag = .endpoint(id: id, index: i); return
                    }
                } else {
                    for (i, c) in corners(e.frame).enumerated() where hypot(p.x - c.x, p.y - c.y) <= slop {
                        board.snapshot(); drag = .resize(id: id, corner: i, orig: e); return
                    }
                }
            }
            if let id = board.hitTest(p) {
                if shift { if board.selection.contains(id) { board.selection.remove(id) } else { board.selection.insert(id) } }
                else if !board.selection.contains(id) { board.selection = [id] }
                board.snapshot()
                drag = .move(orig: Dictionary(uniqueKeysWithValues: board.elements.filter { board.selection.contains($0.id) }.map { ($0.id, $0) }))
            } else {
                if !shift { board.selection = [] }
                drag = .marquee(start: p)
            }
        case .text, .sticky:
            board.snapshot()
            let e = board.newElement(board.tool.kind ?? .text, at: p)
            board.add(e); board.selection = [e.id]; board.editing = e.id; board.tool = .select
            drag = .idle
        default:
            guard let kind = board.tool.kind else { return }
            board.snapshot()
            let e = board.newElement(kind, at: p)
            board.add(e); board.selection = [e.id]
            drag = .create(id: e.id, start: p)
        }
    }

    private func update(start: CGPoint, now: CGPoint, translation: CGSize) {
        switch drag {
        case .idle: break
        case .pan(let s):
            board.pan = CGSize(width: s.width + translation.width / board.zoom, height: s.height + translation.height / board.zoom)
        case .move(let orig):
            let d = CGSize(width: now.x - start.x, height: now.y - start.y)
            for (id, o) in orig { if let i = board.index(id) { var e = o; e.move(by: d); board.elements[i] = e } }
            board.dirty = true
        case .resize(let id, let corner, let o):
            guard let i = board.index(id) else { return }
            let f = o.frame, anchor = corners(f)[3 - corner]
            var e = o
            e.frame = CGRect(x: min(anchor.x, now.x), y: min(anchor.y, now.y), width: max(abs(now.x - anchor.x), 4), height: max(abs(now.y - anchor.y), 4))
            if e.kind == .text { e.h = o.h }
            board.elements[i] = e; board.dirty = true
        case .endpoint(let id, let idx):
            guard let i = board.index(id), board.elements[i].points.indices.contains(idx) else { return }
            board.elements[i].points[idx] = [now.x, now.y]; board.dirty = true
        case .create(let id, let s):
            guard let i = board.index(id) else { return }
            switch board.elements[i].kind {
            case .line, .arrow: board.elements[i].points = [[s.x, s.y], [now.x, now.y]]
            case .pen: board.elements[i].points.append([now.x, now.y])
            default:
                var f = CGRect(x: min(s.x, now.x), y: min(s.y, now.y), width: abs(now.x - s.x), height: abs(now.y - s.y))
                if NSEvent.modifierFlags.contains(.shift) { let m = max(f.width, f.height); f.size = CGSize(width: m, height: m) }
                board.elements[i].frame = f
            }
        case .marquee(let s):
            let r = CGRect(x: min(s.x, now.x), y: min(s.y, now.y), width: abs(now.x - s.x), height: abs(now.y - s.y))
            marquee = r
            board.selection = Set(board.elements.filter { $0.frame.intersects(r) }.map(\.id))
        }
    }

    private func end() {
        if case .create(let id, let s) = drag, let i = board.index(id) {
            let e = board.elements[i]
            let f = e.frame
            if e.kind == .pen {
                if f.width < 2 && f.height < 2 && e.points.count < 2 { board.elements.remove(at: i); board.selection = [] }
            } else if e.isLinear {
                if f.width < 3 && f.height < 3 { board.elements.remove(at: i); board.selection = [] } else { board.tool = .select }
            } else {
                if f.width < 4 || f.height < 4 { board.elements[i].frame = CGRect(x: s.x - 60, y: s.y - 45, width: 120, height: 90) }
                board.tool = .select
            }
        }
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
