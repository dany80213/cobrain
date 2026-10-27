import SwiftUI
#if canImport(UIKit)
import UIKit
typealias PlatformFont = UIFont
#else
import AppKit
typealias PlatformFont = NSFont
#endif

// Whiteboard document (Canva-style): an infinite canvas of shapes, lines, pen strokes, text and sticky notes.
// Saved as `.cobrainboard` (JSON). Unlike word documents this has no engine counterpart: it lives in Swift.

struct BoardColor: Codable, Equatable {
    var r: Double, g: Double, b: Double, a: Double
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    static let clear = BoardColor(r: 0, g: 0, b: 0, a: 0)
    static func hex(_ v: UInt32, a: Double = 1) -> BoardColor {
        BoardColor(r: Double((v >> 16) & 255) / 255, g: Double((v >> 8) & 255) / 255, b: Double(v & 255) / 255, a: a)
    }
    init(r: Double, g: Double, b: Double, a: Double) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(_ c: Color) {
        let n = c.resolve(in: EnvironmentValues())
        self.init(r: Double(n.red), g: Double(n.green), b: Double(n.blue), a: Double(n.opacity))
    }
}

enum BoardKind: String, Codable {
    case rect, roundRect, ellipse, triangle, diamond, star, line, arrow, pen, text, sticky
}

enum BoardTool: String, CaseIterable, Identifiable {
    case select, hand, eraser, rect, roundRect, ellipse, triangle, diamond, star, line, arrow, pen, text, sticky
    var id: String { rawValue }
    var label: String {
        switch self {
        case .select: "Select"; case .hand: "Pan"; case .eraser: "Eraser"; case .rect: "Rectangle"; case .roundRect: "Rounded rectangle"; case .ellipse: "Ellipse"
        case .triangle: "Triangle"; case .diamond: "Diamond"; case .star: "Star"; case .line: "Line"; case .arrow: "Arrow"
        case .pen: "Pen"; case .text: "Text"; case .sticky: "Sticky note"
        }
    }
    var symbol: String {
        switch self {
        case .select: "cursorarrow"; case .hand: "hand.raised"; case .eraser: "eraser"; case .rect: "rectangle"; case .roundRect: "square"; case .ellipse: "circle"
        case .triangle: "triangle"; case .diamond: "diamond"; case .star: "star"; case .line: "line.diagonal"; case .arrow: "arrow.up.right"
        case .pen: "pencil.tip"; case .text: "textformat"; case .sticky: "note.text"
        }
    }
    var kind: BoardKind? { BoardKind(rawValue: rawValue) }
}

struct BoardElement: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: BoardKind
    var x = 0.0, y = 0.0, w = 0.0, h = 0.0
    var fill: BoardColor = .clear
    var stroke: BoardColor = .hex(0x2B2B33)
    var lineWidth = 2.0
    var text = ""
    var fontSize = 20.0
    /// Line, arrow and pen: the polyline in board coordinates.
    var points: [[Double]] = []
    /// Pen strokes drawn with Apple Pencil: pressure (0…1) per point, giving a variable line width.
    var pressures: [Double]?

    var isLinear: Bool { kind == .line || kind == .arrow || kind == .pen }

    var frame: CGRect {
        get {
            guard isLinear else { return CGRect(x: x, y: y, width: w, height: h) }
            guard let f = points.first, f.count == 2 else { return .zero }
            var minX = f[0], maxX = f[0], minY = f[1], maxY = f[1]
            for p in points where p.count == 2 { minX = min(minX, p[0]); maxX = max(maxX, p[0]); minY = min(minY, p[1]); maxY = max(maxY, p[1]) }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        set {
            guard isLinear else { x = newValue.minX; y = newValue.minY; w = newValue.width; h = newValue.height; return }
            let old = frame
            points = points.map { p in
                guard p.count == 2 else { return p }
                let fx = old.width > 0 ? (p[0] - old.minX) / old.width : 0
                let fy = old.height > 0 ? (p[1] - old.minY) / old.height : 0
                return [newValue.minX + fx * newValue.width, newValue.minY + fy * newValue.height]
            }
        }
    }

    mutating func move(by d: CGSize) {
        if isLinear { points = points.map { $0.count == 2 ? [$0[0] + d.width, $0[1] + d.height] : $0 } } else { x += d.width; y += d.height }
    }

    func path(in r: CGRect) -> Path {
        switch kind {
        case .rect, .sticky, .text: return Path(r)
        case .roundRect: return Path(roundedRect: r, cornerRadius: min(r.width, r.height) * 0.18)
        case .ellipse: return Path(ellipseIn: r)
        case .triangle:
            var p = Path()
            p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath()
            return p
        case .diamond:
            var p = Path()
            p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.midY)); p.closeSubpath()
            return p
        case .star:
            var p = Path()
            for i in 0..<10 {
                let a = -Double.pi / 2 + Double(i) * Double.pi / 5, k = i % 2 == 0 ? 1.0 : 0.42
                let pt = CGPoint(x: r.midX + cos(a) * k * r.width / 2, y: r.midY + sin(a) * k * r.height / 2)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            return p
        case .pen where points.count > 2:
            // Quadratic curves through the midpoints: smooth ink from raw touch samples.
            let pts = points.compactMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
            var p = Path()
            p.move(to: pts[0])
            for i in 1..<pts.count - 1 { p.addQuadCurve(to: CGPoint(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2), control: pts[i]) }
            p.addLine(to: pts[pts.count - 1])
            return p
        case .line, .arrow, .pen:
            var p = Path()
            for (i, q) in points.enumerated() where q.count == 2 {
                let pt = CGPoint(x: q[0], y: q[1])
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            if points.count == 1, let q = points.first, q.count == 2 { p.addLine(to: CGPoint(x: q[0] + 0.01, y: q[1])) }
            return p
        }
    }

    /// Distance-based hit test for lines and pen strokes, frame-based for everything else.
    func hit(_ p: CGPoint, slop: CGFloat) -> Bool {
        guard isLinear else { return frame.insetBy(dx: -slop, dy: -slop).contains(p) }
        let pts = points.compactMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
        if pts.count == 1 { return hypot(p.x - pts[0].x, p.y - pts[0].y) <= slop + lineWidth }
        for (a, b) in zip(pts, pts.dropFirst()) where Self.distance(p, a, b) <= slop + lineWidth / 2 { return true }
        return false
    }

    private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy
        let t = len2 == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

struct BoardFile: Codable { var version = 1; var elements: [BoardElement] }

enum BoardDrawing {
    static func draw(_ e: BoardElement, in ctx: inout GraphicsContext) {
        let r = e.frame
        switch e.kind {
        case .line, .arrow, .pen:
            let style = StrokeStyle(lineWidth: e.lineWidth, lineCap: .round, lineJoin: .round)
            if e.kind == .pen, let pr = e.pressures, pr.count == e.points.count, e.points.count > 2 {
                strokeVariable(e, pr, in: &ctx)
            } else {
                ctx.stroke(e.path(in: r), with: .color(e.stroke.color), style: style)
            }
            if e.kind == .arrow, e.points.count >= 2, let a = e.points.first, let b = e.points.last, a.count == 2, b.count == 2 {
                let angle = atan2(b[1] - a[1], b[0] - a[0]), len = 10 + e.lineWidth * 3
                var head = Path()
                for s in [-1.0, 1.0] {
                    head.move(to: CGPoint(x: b[0], y: b[1]))
                    head.addLine(to: CGPoint(x: b[0] - len * cos(angle + s * 0.45), y: b[1] - len * sin(angle + s * 0.45)))
                }
                ctx.stroke(head, with: .color(e.stroke.color), style: style)
            }
        case .text:
            drawText(e.text, in: r, size: e.fontSize, color: e.stroke.color, centered: false, ctx: &ctx)
        case .sticky:
            ctx.fill(Path(r.offsetBy(dx: 3, dy: 5)), with: .color(.black.opacity(0.14)))
            ctx.fill(Path(r), with: .color(e.fill.a > 0 ? e.fill.color : Color(red: 1, green: 0.9, blue: 0.45)))
            drawText(e.text, in: r.insetBy(dx: 10, dy: 10), size: e.fontSize, color: .black, centered: false, ctx: &ctx)
        default:
            let path = e.path(in: r)
            if e.fill.a > 0 { ctx.fill(path, with: .color(e.fill.color)) }
            if e.lineWidth > 0, e.stroke.a > 0 { ctx.stroke(path, with: .color(e.stroke.color), style: StrokeStyle(lineWidth: e.lineWidth, lineJoin: .round)) }
            drawText(e.text, in: r.insetBy(dx: 8, dy: 8), size: e.fontSize, color: e.stroke.a > 0 ? e.stroke.color : .black, centered: true, ctx: &ctx)
        }
    }

    /// Pencil ink: one curve per segment, as wide as the pressure at its middle point.
    private static func strokeVariable(_ e: BoardElement, _ pr: [Double], in ctx: inout GraphicsContext) {
        let pts = e.points.compactMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
        guard pts.count == pr.count else { return }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        for i in 1..<pts.count - 1 {
            var seg = Path()
            seg.move(to: mid(pts[i - 1], pts[i]))
            seg.addQuadCurve(to: mid(pts[i], pts[i + 1]), control: pts[i])
            let w = e.lineWidth * (0.35 + 1.3 * pr[i])
            ctx.stroke(seg, with: .color(e.stroke.color), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        }
        var first = Path(); first.move(to: pts[0]); first.addLine(to: mid(pts[0], pts[1]))
        ctx.stroke(first, with: .color(e.stroke.color), style: StrokeStyle(lineWidth: e.lineWidth * (0.35 + 1.3 * pr[0]), lineCap: .round))
        var last = Path(); last.move(to: mid(pts[pts.count - 2], pts[pts.count - 1])); last.addLine(to: pts[pts.count - 1])
        ctx.stroke(last, with: .color(e.stroke.color), style: StrokeStyle(lineWidth: e.lineWidth * (0.35 + 1.3 * pr[pr.count - 1]), lineCap: .round))
    }

    private static func drawText(_ s: String, in r: CGRect, size: Double, color: Color, centered: Bool, ctx: inout GraphicsContext) {
        guard !s.isEmpty, r.width > 4 else { return }
        let resolved = ctx.resolve(Text(s).font(.system(size: size)).foregroundColor(color))
        let m = resolved.measure(in: CGSize(width: r.width, height: .infinity))
        let origin = centered ? CGPoint(x: r.minX + (r.width - m.width) / 2, y: r.minY + (r.height - m.height) / 2) : r.origin
        ctx.draw(resolved, in: CGRect(origin: origin, size: CGSize(width: r.width, height: m.height)))
    }
}

final class BoardModel: ObservableObject {
    @Published var elements: [BoardElement] = []
    @Published var selection: Set<UUID> = []
    @Published var tool: BoardTool = .select
    @Published var zoom: CGFloat = 1
    @Published var pan: CGSize = .zero
    @Published var editing: UUID?
    @Published var fileURL: URL?
    @Published var dirty = false
    @Published var marquee: CGRect?
    @Published var savingTemplate = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var fill: BoardColor = .hex(0x7C6CF0)
    @Published var stroke: BoardColor = .hex(0x2B2B33)
    @Published var lineWidth = 2.0
    @Published var fontSize = 20.0
    /// iPad: with the pen tool, only Apple Pencil draws; a finger scrolls the board.
    @Published var pencilOnly = true
    var viewSize = CGSize(width: 800, height: 600)
    private(set) lazy var interactor = BoardInteractor(board: self)

    /// Undo goes through an `UndoManager`, so on iPad the document's own manager (system undo gestures,
    /// shake to undo, the edited state that drives autosave) sees every change.
    var undoManager = UndoManager() { didSet { observeUndo() } }
    private var undoObservers: [NSObjectProtocol] = []
    private var pending: [BoardElement]?
    private var editBefore: [BoardElement]?
    private var lastCoalesce: (key: String, at: Date)?
    private var previousTool: BoardTool = .select
    #if os(macOS)
    weak var window: NSWindow?
    var closeGuard: WindowCloseGuard?
    #endif

    init() { observeUndo() }

    var title: String { (fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled whiteboard") + (dirty ? " — Edited" : "") }

    // MARK: Coordinates
    func world(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / zoom - pan.width, y: p.y / zoom - pan.height) }
    func zoom(by factor: CGFloat, around anchor: CGPoint? = nil) {
        let a = anchor ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let wp = world(a), z = max(0.1, min(8, zoom * factor))
        zoom = z
        pan = CGSize(width: a.x / z - wp.x, height: a.y / z - wp.y)
    }
    func resetView() { zoom = 1; pan = .zero }
    func fitContent() {
        guard let first = elements.first else { return resetView() }
        let box = elements.dropFirst().reduce(first.frame) { $0.union($1.frame) }.insetBy(dx: -40, dy: -40)
        let z = max(0.1, min(4, min(viewSize.width / max(box.width, 1), viewSize.height / max(box.height, 1))))
        zoom = z
        pan = CGSize(width: (viewSize.width / z - box.width) / 2 - box.minX, height: (viewSize.height / z - box.height) / 2 - box.minY)
    }

    // MARK: Undo
    private func observeUndo() {
        undoObservers.forEach(NotificationCenter.default.removeObserver)
        let names: [Notification.Name] = [.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange, .NSUndoManagerDidCloseUndoGroup, .NSUndoManagerCheckpoint]
        undoObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: undoManager, queue: .main) { [weak self] _ in self?.syncUndo() }
        }
        syncUndo()
    }
    private func syncUndo() {
        if canUndo != undoManager.canUndo { canUndo = undoManager.canUndo }
        if canRedo != undoManager.canRedo { canRedo = undoManager.canRedo }
    }
    private func register(_ old: [BoardElement]) {
        undoManager.registerUndo(withTarget: self) { $0.restore(old) }
        dirty = true
        syncUndo()
    }
    private func restore(_ target: [BoardElement]) {
        let current = elements
        undoManager.registerUndo(withTarget: self) { $0.restore(current) }
        elements = target
        let ids = Set(target.map(\.id))
        selection = selection.intersection(ids)
        if let e = editing, !ids.contains(e) { editing = nil }
        lastCoalesce = nil; dirty = true
    }
    func undo() { endEditing(); undoManager.undo(); syncUndo() }
    func redo() { undoManager.redo(); syncUndo() }

    /// A change made by a drag: `beginChange` when it starts, `commitChange` when it ends; one undo step
    /// if the board really changed, none for a click that did nothing.
    func beginChange() { pending = elements }
    func commitChange() {
        guard let before = pending else { return }
        pending = nil
        if before != elements { register(before) }
    }
    func discardPending() { pending = nil }
    func abortChange() {
        guard let before = pending else { return }
        pending = nil; elements = before
        selection = selection.intersection(Set(before.map(\.id)))
    }
    /// A one-shot change (delete, duplicate, arrange, paste): one undo step if anything changed.
    func edit(_ body: () -> Void) {
        let before = elements
        body()
        if before != elements { register(before) }
    }

    // MARK: Editing
    func hitTest(_ p: CGPoint) -> UUID? {
        let slop = 6 / zoom
        return elements.last { $0.hit(p, slop: slop) }?.id
    }
    func index(_ id: UUID) -> Int? { elements.firstIndex { $0.id == id } }
    func element(_ id: UUID) -> BoardElement? { index(id).map { elements[$0] } }

    func add(_ e: BoardElement) { elements.append(e) }

    func newElement(_ kind: BoardKind, at p: CGPoint) -> BoardElement {
        var e = BoardElement(kind: kind)
        e.stroke = stroke; e.lineWidth = lineWidth; e.fontSize = fontSize
        switch kind {
        case .line, .arrow, .pen: e.points = [[p.x, p.y]]
        case .text: e.x = p.x; e.y = p.y; e.w = 240; e.h = fontSize * 1.4
        case .sticky: e.x = p.x - 80; e.y = p.y - 80; e.w = 160; e.h = 160; e.fill = .hex(0xFFE56B)
        default: e.x = p.x; e.y = p.y; e.fill = fill
        }
        return e
    }

    /// Grow a text element to fit what was typed.
    func fitText(_ id: UUID) {
        guard let i = index(id), elements[i].kind == .text else { return }
        let font = PlatformFont.systemFont(ofSize: elements[i].fontSize)
        let s = elements[i].text.isEmpty ? " " : elements[i].text
        let box = (s as NSString).boundingRect(with: CGSize(width: elements[i].w, height: 10_000), options: [.usesLineFragmentOrigin], attributes: [.font: font], context: nil)
        elements[i].h = max(elements[i].fontSize * 1.4, ceil(box.height) + 4)
    }

    /// Start typing into `id`; what changes until `endEditing` is one undo step.
    func startEditing(_ id: UUID, before: [BoardElement]? = nil) {
        editBefore = before ?? elements
        selection = [id]
        editing = id
    }

    func endEditing() {
        guard let id = editing else { return }
        editing = nil
        if let e = element(id), e.kind == .text, e.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            elements.removeAll { $0.id == id }; selection.remove(id)
        }
        if let before = editBefore, before != elements { register(before) }
        editBefore = nil
    }

    /// Leave text editing (keeping what was typed) before the board is written out.
    func endEditingForSave() { endEditing() }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        endEditing()
        edit { elements.removeAll { selection.contains($0.id) } }
        selection = []
    }

    func duplicateSelection() {
        guard !selection.isEmpty else { return }
        edit {
            var copies: [BoardElement] = []
            for e in elements where selection.contains(e.id) {
                var c = e; c.id = UUID(); c.move(by: CGSize(width: 24, height: 24)); copies.append(c)
            }
            elements += copies
            selection = Set(copies.map(\.id))
        }
    }

    func selectAll() { selection = Set(elements.map(\.id)) }

    func bringToFront() { arrange(front: true) }
    func sendToBack() { arrange(front: false) }
    private func arrange(front: Bool) {
        guard !selection.isEmpty else { return }
        edit {
            let chosen = elements.filter { selection.contains($0.id) }, rest = elements.filter { !selection.contains($0.id) }
            elements = front ? rest + chosen : chosen + rest
        }
    }

    /// Change the selected elements; calls with the same `key` within a second (a colour slider) share one undo step.
    func apply(_ change: (inout BoardElement) -> Void, key: String) {
        guard !selection.isEmpty else { return }
        let before = elements
        for i in elements.indices where selection.contains(elements[i].id) { change(&elements[i]) }
        guard before != elements else { return }
        if let l = lastCoalesce, l.key == key, Date().timeIntervalSince(l.at) < 1 { lastCoalesce = (key, Date()); dirty = true; return }
        lastCoalesce = (key, Date())
        register(before)
    }
    func setFill(_ c: BoardColor) { fill = c; apply({ $0.fill = c }, key: "fill") }
    func setStroke(_ c: BoardColor) { stroke = c; apply({ $0.stroke = c }, key: "stroke") }
    func setLineWidth(_ v: Double) { lineWidth = v; apply({ $0.lineWidth = v }, key: "width") }
    func setFontSize(_ v: Double) {
        fontSize = v
        apply({ $0.fontSize = v }, key: "font")
        for id in selection { fitText(id) }
    }

    /// Apple Pencil double-tap / squeeze: switch to the eraser and back.
    func togglePencilEraser() {
        if tool == .eraser { tool = previousTool } else { previousTool = tool == .select ? .pen : tool; tool = .eraser }
    }

    func doubleClick(at p: CGPoint) {
        guard tool == .select else { return }
        if let id = hitTest(p), let e = element(id), !e.isLinear {
            startEditing(id)
        } else if hitTest(p) == nil {
            let before = elements
            let e = newElement(.text, at: p)
            add(e)
            startEditing(e.id, before: before)
        }
    }

    // MARK: File format
    func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(BoardFile(elements: elements))
    }

    func load(_ data: Data) throws {
        elements = try JSONDecoder().decode(BoardFile.self, from: data).elements
        selection = []; editing = nil; dirty = false
        undoManager.removeAllActions(); syncUndo()
    }
}
