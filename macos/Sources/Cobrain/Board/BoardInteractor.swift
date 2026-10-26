import SwiftUI

/// Turns pointer input (mouse, finger, Apple Pencil) into board edits. Positions are in view coordinates;
/// the interactor converts them to board coordinates.
final class BoardInteractor {
    private enum Drag {
        case idle
        case move(orig: [UUID: BoardElement])
        case resize(id: UUID, corner: Int, orig: BoardElement)
        case endpoint(id: UUID, index: Int)
        case create(id: UUID, start: CGPoint)
        case marquee(start: CGPoint)
        case pan(start: CGSize)
        case erase
    }

    unowned let board: BoardModel
    private var drag: Drag = .idle
    private var keepsPending = false
    static let handle: CGFloat = 9

    init(board: BoardModel) { self.board = board }

    var isActive: Bool { if case .idle = drag { return false } else { return true } }

    static func corners(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
    }

    /// `pressure` is nil for a mouse or finger. `touchSize` widens the grab area of handles for fingers.
    func begin(at screen: CGPoint, shift: Bool = false, pressure: Double? = nil, grab: CGFloat = 3) {
        let p = board.world(screen)
        if board.editing != nil { board.endEditing() }
        board.beginChange()
        keepsPending = false
        switch board.tool {
        case .hand:
            drag = .pan(start: board.pan)
        case .eraser:
            drag = .erase
            erase(at: p)
        case .select:
            let slop = (Self.handle + grab) / board.zoom
            if board.selection.count == 1, let id = board.selection.first, let e = board.element(id) {
                if e.isLinear && e.kind != .pen {
                    for (i, q) in e.points.enumerated() where q.count == 2 && hypot(p.x - q[0], p.y - q[1]) <= slop {
                        drag = .endpoint(id: id, index: i); return
                    }
                } else {
                    for (i, c) in Self.corners(e.frame).enumerated() where hypot(p.x - c.x, p.y - c.y) <= slop {
                        drag = .resize(id: id, corner: i, orig: e); return
                    }
                }
            }
            if let id = board.hitTest(p) {
                if shift { if board.selection.contains(id) { board.selection.remove(id) } else { board.selection.insert(id) } }
                else if !board.selection.contains(id) { board.selection = [id] }
                drag = .move(orig: Dictionary(uniqueKeysWithValues: board.elements.filter { board.selection.contains($0.id) }.map { ($0.id, $0) }))
            } else {
                if !shift { board.selection = [] }
                drag = .marquee(start: p)
            }
        case .text, .sticky:
            let before = board.elements
            let e = board.newElement(board.tool == .sticky ? .sticky : .text, at: p)
            board.add(e); board.tool = .select
            board.startEditing(e.id, before: before)
            board.abortPending()
            drag = .idle
        default:
            guard let kind = board.tool.kind else { return }
            var e = board.newElement(kind, at: p)
            if kind == .pen, let pressure { e.pressures = [Self.clamp(pressure)] }
            board.add(e)
            board.selection = kind == .pen ? [] : [e.id]
            drag = .create(id: e.id, start: p)
        }
    }

    /// Start a plain scroll of the board (a finger with the pen tool selected).
    func beginPan() { board.beginChange(); drag = .pan(start: board.pan) }

    func update(start: CGPoint, now: CGPoint, pressure: Double? = nil, shift: Bool = false) {
        let s = board.world(start), p = board.world(now)
        switch drag {
        case .idle: break
        case .pan(let origin):
            board.pan = CGSize(width: origin.width + (now.x - start.x) / board.zoom, height: origin.height + (now.y - start.y) / board.zoom)
        case .move(let orig):
            let d = CGSize(width: p.x - s.x, height: p.y - s.y)
            for (id, o) in orig { if let i = board.index(id) { var e = o; e.move(by: d); board.elements[i] = e } }
        case .resize(let id, let corner, let o):
            guard let i = board.index(id) else { return }
            let anchor = Self.corners(o.frame)[3 - corner]
            var e = o
            e.frame = CGRect(x: min(anchor.x, p.x), y: min(anchor.y, p.y), width: max(abs(p.x - anchor.x), 4), height: max(abs(p.y - anchor.y), 4))
            if e.kind == .text { e.h = o.h }
            board.elements[i] = e
        case .endpoint(let id, let idx):
            guard let i = board.index(id), board.elements[i].points.indices.contains(idx) else { return }
            board.elements[i].points[idx] = [p.x, p.y]
        case .create(let id, let origin):
            guard let i = board.index(id) else { return }
            switch board.elements[i].kind {
            case .line, .arrow: board.elements[i].points = [[origin.x, origin.y], [p.x, p.y]]
            case .pen:
                // Skip samples closer than a screen pixel: dense ink points only cost drawing time.
                if let last = board.elements[i].points.last, last.count == 2, hypot(p.x - last[0], p.y - last[1]) * board.zoom < 1 { return }
                board.elements[i].points.append([p.x, p.y])
                if board.elements[i].pressures != nil { board.elements[i].pressures?.append(Self.clamp(pressure ?? 0.5)) }
            default:
                var f = CGRect(x: min(origin.x, p.x), y: min(origin.y, p.y), width: abs(p.x - origin.x), height: abs(p.y - origin.y))
                if shift { let m = max(f.width, f.height); f.size = CGSize(width: m, height: m) }
                board.elements[i].frame = f
            }
        case .marquee(let origin):
            let r = CGRect(x: min(origin.x, p.x), y: min(origin.y, p.y), width: abs(p.x - origin.x), height: abs(p.y - origin.y))
            board.marquee = r
            board.selection = Set(board.elements.filter { $0.frame.intersects(r) }.map(\.id))
        case .erase:
            erase(at: p)
        }
    }

    func end() {
        if case .create(let id, let s) = drag, let i = board.index(id) {
            let e = board.elements[i], f = e.frame
            if e.kind == .pen {
                if f.width < 2 && f.height < 2 && e.points.count < 2 { board.elements.remove(at: i); board.selection = [] }
                // Ink stays selected only while it is being drawn: the next stroke should not drag it along.
                board.selection = []
            } else if e.isLinear {
                if f.width < 3 && f.height < 3 { board.elements.remove(at: i); board.selection = [] } else { board.tool = .select }
            } else {
                if f.width < 4 || f.height < 4 { board.elements[i].frame = CGRect(x: s.x - 60, y: s.y - 45, width: 120, height: 90) }
                board.tool = .select
            }
        }
        board.marquee = nil
        drag = .idle
        board.commitChange()
    }

    /// A second finger came down (pinch / two-finger scroll): undo what the first one started.
    func cancel() {
        board.marquee = nil
        drag = .idle
        board.abortChange()
    }

    private func erase(at p: CGPoint) {
        let r = 10 / board.zoom
        let hit = board.elements.filter { $0.isLinear && $0.hit(p, slop: r) }.map(\.id)
        guard !hit.isEmpty else { return }
        board.elements.removeAll { hit.contains($0.id) }
        board.selection.subtract(hit)
    }

    private static func clamp(_ v: Double) -> Double { max(0.05, min(1, v)) }
}

extension BoardModel {
    /// Drop the drag bookkeeping without touching the board (text creation has its own undo step).
    func abortPending() { discardPending() }
}
