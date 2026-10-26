import AppKit
import SwiftUI

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
        let n = NSColor(c).usingColorSpace(.sRGB) ?? .black
        self.init(r: Double(n.redComponent), g: Double(n.greenComponent), b: Double(n.blueComponent), a: Double(n.alphaComponent))
    }
}

enum BoardKind: String, Codable {
    case rect, roundRect, ellipse, triangle, diamond, star, line, arrow, pen, text, sticky
}

enum BoardTool: String, CaseIterable, Identifiable {
    case select, hand, rect, roundRect, ellipse, triangle, diamond, star, line, arrow, pen, text, sticky
    var id: String { rawValue }
    var label: String {
        switch self {
        case .select: "Select"; case .hand: "Pan"; case .rect: "Rectangle"; case .roundRect: "Rounded rectangle"; case .ellipse: "Ellipse"
        case .triangle: "Triangle"; case .diamond: "Diamond"; case .star: "Star"; case .line: "Line"; case .arrow: "Arrow"
        case .pen: "Pen"; case .text: "Text"; case .sticky: "Sticky note"
        }
    }
    var symbol: String {
        switch self {
        case .select: "cursorarrow"; case .hand: "hand.raised"; case .rect: "rectangle"; case .roundRect: "square"; case .ellipse: "circle"
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

private struct BoardFile: Codable { var version = 1; var elements: [BoardElement] }

enum BoardDrawing {
    static func draw(_ e: BoardElement, in ctx: inout GraphicsContext) {
        let r = e.frame
        switch e.kind {
        case .line, .arrow, .pen:
            let style = StrokeStyle(lineWidth: e.lineWidth, lineCap: .round, lineJoin: .round)
            ctx.stroke(e.path(in: r), with: .color(e.stroke.color), style: style)
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
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var fill: BoardColor = .hex(0x7C6CF0)
    @Published var stroke: BoardColor = .hex(0x2B2B33)
    @Published var lineWidth = 2.0
    @Published var fontSize = 20.0
    var viewSize = CGSize(width: 800, height: 600)

    private var undoStack: [[BoardElement]] = []
    private var redoStack: [[BoardElement]] = []
    private var lastCoalesce: (key: String, at: Date)?

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
    /// Call before a change. Calls with the same `key` within a second share one undo step (colour sliders).
    func snapshot(coalesce key: String? = nil) {
        if let key, let l = lastCoalesce, l.key == key, Date().timeIntervalSince(l.at) < 1 { lastCoalesce = (key, Date()); return }
        lastCoalesce = key.map { ($0, Date()) }
        undoStack.append(elements)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack = []
        dirty = true
        syncUndo()
    }
    private func syncUndo() { canUndo = !undoStack.isEmpty; canRedo = !redoStack.isEmpty }
    func undo() {
        guard let s = undoStack.popLast() else { return }
        redoStack.append(elements); elements = s; afterHistory()
    }
    func redo() {
        guard let s = redoStack.popLast() else { return }
        undoStack.append(elements); elements = s; afterHistory()
    }
    private func afterHistory() {
        let ids = Set(elements.map(\.id))
        selection = selection.intersection(ids)
        if let e = editing, !ids.contains(e) { editing = nil }
        lastCoalesce = nil; dirty = true; syncUndo()
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
        case .text: e.x = p.x; e.y = p.y; e.w = 240; e.h = fontSize * 1.4; e.stroke = stroke
        case .sticky: e.x = p.x - 80; e.y = p.y - 80; e.w = 160; e.h = 160; e.fill = .hex(0xFFE56B)
        default: e.x = p.x; e.y = p.y; e.fill = fill
        }
        return e
    }

    /// Grow a text element to fit what was typed.
    func fitText(_ id: UUID) {
        guard let i = index(id), elements[i].kind == .text else { return }
        let font = NSFont.systemFont(ofSize: elements[i].fontSize)
        let s = elements[i].text.isEmpty ? " " : elements[i].text
        let box = (s as NSString).boundingRect(with: CGSize(width: elements[i].w, height: 10_000), options: [.usesLineFragmentOrigin], attributes: [.font: font])
        elements[i].h = max(elements[i].fontSize * 1.4, ceil(box.height) + 4)
    }

    func endEditing() {
        guard let id = editing else { return }
        editing = nil
        if let e = element(id), e.kind == .text, e.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            elements.removeAll { $0.id == id }; selection.remove(id)
        }
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        snapshot(); editing = nil
        elements.removeAll { selection.contains($0.id) }
        selection = []
    }

    func duplicateSelection() {
        guard !selection.isEmpty else { return }
        snapshot()
        var copies: [BoardElement] = []
        for e in elements where selection.contains(e.id) {
            var c = e; c.id = UUID(); c.move(by: CGSize(width: 24, height: 24)); copies.append(c)
        }
        elements += copies
        selection = Set(copies.map(\.id))
    }

    func selectAll() { selection = Set(elements.map(\.id)) }

    func bringToFront() { arrange(front: true) }
    func sendToBack() { arrange(front: false) }
    private func arrange(front: Bool) {
        guard !selection.isEmpty else { return }
        snapshot()
        let chosen = elements.filter { selection.contains($0.id) }, rest = elements.filter { !selection.contains($0.id) }
        elements = front ? rest + chosen : chosen + rest
    }

    func apply(_ change: (inout BoardElement) -> Void, key: String) {
        guard !selection.isEmpty else { return }
        snapshot(coalesce: key)
        for i in elements.indices where selection.contains(elements[i].id) { change(&elements[i]) }
    }
    func setFill(_ c: BoardColor) { fill = c; apply({ $0.fill = c }, key: "fill") }
    func setStroke(_ c: BoardColor) { stroke = c; apply({ $0.stroke = c }, key: "stroke") }
    func setLineWidth(_ v: Double) { lineWidth = v; apply({ $0.lineWidth = v }, key: "width") }
    func setFontSize(_ v: Double) {
        fontSize = v
        apply({ $0.fontSize = v }, key: "font")
        for id in selection { fitText(id) }
    }

    // MARK: Files
    func save() { if let url = fileURL { write(to: url) } else { saveAs() } }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "cobrainboard")].compactMap { $0 }
        panel.nameFieldStringValue = (fileURL?.lastPathComponent ?? "Untitled.cobrainboard")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(to: url)
    }

    private func write(to url: URL) {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(BoardFile(elements: elements)).write(to: url, options: .atomic)
            fileURL = url; dirty = false
        } catch {
            let a = NSAlert(); a.messageText = "Could not save \(url.lastPathComponent)"; a.informativeText = error.localizedDescription; a.runModal()
        }
    }

    func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "cobrainboard")].compactMap { $0 }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL) {
        do {
            let f = try JSONDecoder().decode(BoardFile.self, from: Data(contentsOf: url))
            elements = f.elements; selection = []; editing = nil; fileURL = url; dirty = false
            undoStack = []; redoStack = []; syncUndo(); fitContent()
        } catch {
            let a = NSAlert(); a.messageText = "Could not open \(url.lastPathComponent)"; a.informativeText = error.localizedDescription; a.runModal()
        }
    }

    @MainActor func exportPNG() {
        guard let first = elements.first else { return }
        let box = elements.dropFirst().reduce(first.frame) { $0.union($1.frame) }.insetBy(dx: -40, dy: -40)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = (fileURL?.deletingPathExtension().lastPathComponent ?? "Whiteboard") + ".png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let items = elements
        let view = Canvas { ctx, _ in
            ctx.translateBy(x: -box.minX, y: -box.minY)
            for e in items { BoardDrawing.draw(e, in: &ctx) }
        }
        .frame(width: box.width, height: box.height).background(Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let img = renderer.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }
}
