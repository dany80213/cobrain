import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

enum BoardRenderer {
    /// Draws the board: dot grid, elements in view, selection handles, marquee.
    static func render(_ board: BoardModel, _ ctx: inout GraphicsContext, _ size: CGSize) {
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
        // Only what is on screen: a big board with long ink strokes stays smooth.
        let cull = visible.insetBy(dx: -60, dy: -60)
        for e in board.elements where (e.id != board.editing || e.kind != .text) && e.frame.insetBy(dx: -e.lineWidth, dy: -e.lineWidth).intersects(cull) {
            BoardDrawing.draw(e, in: &ctx)
        }
        let blue = Color.accentColor
        for id in board.selection {
            guard let e = board.element(id) else { continue }
            if e.isLinear && e.kind != .pen {
                for p in e.points where p.count == 2 { handle(&ctx, CGPoint(x: p[0], y: p[1]), z) }
            } else {
                ctx.stroke(Path(e.frame), with: .color(blue), style: StrokeStyle(lineWidth: 1.5 / z))
                if board.selection.count == 1 { for c in BoardInteractor.corners(e.frame) { handle(&ctx, c, z) } }
            }
        }
        if let m = board.marquee {
            ctx.fill(Path(m), with: .color(blue.opacity(0.1)))
            ctx.stroke(Path(m), with: .color(blue), style: StrokeStyle(lineWidth: 1 / z, dash: [4 / z, 3 / z]))
        }
    }

    private static func handle(_ ctx: inout GraphicsContext, _ p: CGPoint, _ z: CGFloat) {
        let s = BoardInteractor.handle / z
        let r = CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)
        ctx.fill(Path(ellipseIn: r), with: .color(.white))
        ctx.stroke(Path(ellipseIn: r), with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5 / z))
    }
}

/// The board itself: drawing, text-editing overlay and the pointer input of the platform.
struct BoardSurface: View {
    @ObservedObject var board: BoardModel
    @FocusState private var textFocus: Bool
    #if os(macOS)
    @State private var active = false
    @State private var baseZoom: CGFloat?
    #endif

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in BoardRenderer.render(board, &ctx, size) }
                    .background(Color.boardBackground)
                input
                if let id = board.editing, let e = board.element(id) { editor(e) }
            }
            .onAppear { board.viewSize = geo.size }
            .onChange(of: geo.size) { _, s in board.viewSize = s }
        }
        .clipped()
    }

    // MARK: Text editing overlay
    private func editor(_ e: BoardElement) -> some View {
        let z = board.zoom, f = e.frame
        let inset: CGFloat = e.kind == .text ? 0 : (e.kind == .sticky ? 10 : 8)
        let width = max(20, (f.width - inset * 2) * z)
        return TextField("", text: Binding(
            get: { board.element(e.id)?.text ?? "" },
            set: { v in if let i = board.index(e.id) { board.elements[i].text = v; board.fitText(e.id) } }
        ), axis: .vertical)
        .textFieldStyle(.plain)
        .multilineTextAlignment(e.kind == .text || e.kind == .sticky ? .leading : .center)
        .font(.system(size: e.fontSize * z))
        .foregroundStyle(e.kind == .sticky ? Color.black : e.stroke.color)
        .focused($textFocus)
        .frame(width: width, alignment: .topLeading)
        .position(x: (f.minX + board.pan.width + inset) * z + width / 2,
                  y: (f.minY + board.pan.height + (e.kind == .text || e.kind == .sticky ? inset : f.height / 2 - e.fontSize / 2)) * z + e.fontSize * z * 0.7)
        .onAppear { textFocus = true }
    }

    // MARK: Input
    @ViewBuilder private var input: some View {
        #if os(macOS)
        Color.clear.contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if !active { active = true; board.interactor.begin(at: v.startLocation, shift: NSEvent.modifierFlags.contains(.shift)); textFocus = board.editing != nil }
                    board.interactor.update(start: v.startLocation, now: v.location, shift: NSEvent.modifierFlags.contains(.shift))
                }
                .onEnded { _ in board.interactor.end(); active = false })
            .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { board.doubleClick(at: board.world($0.location)) })
            .simultaneousGesture(MagnifyGesture().onChanged { v in
                let base = baseZoom ?? board.zoom
                baseZoom = base
                board.zoom(by: base * v.magnification / board.zoom, around: v.startLocation)
            }.onEnded { _ in baseZoom = nil })
        #else
        BoardTouchLayer(board: board)
        #endif
    }
}

extension Color {
    #if canImport(UIKit)
    static let boardBackground = Color(uiColor: .systemBackground)
    #else
    static let boardBackground = Color(nsColor: .textBackgroundColor)
    #endif
}

#if canImport(UIKit)
/// iPad input: Apple Pencil draws with pressure, a finger selects and moves, two fingers scroll and zoom,
/// the Pencil double-tap / squeeze switches to the eraser. A palm resting on the screen while the Pencil is
/// down is ignored.
struct BoardTouchLayer: UIViewRepresentable {
    let board: BoardModel

    func makeCoordinator() -> Coordinator { Coordinator(board) }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isMultipleTouchEnabled = true
        let c = context.coordinator
        let stroke = StrokeRecognizer(coordinator: c)
        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinched(_:)))
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.panned(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        let double = UITapGestureRecognizer(target: c, action: #selector(Coordinator.doubleTapped(_:)))
        double.numberOfTapsRequired = 2
        for g in [pinch, pan, double] as [UIGestureRecognizer] { g.delegate = c; g.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)] }
        stroke.delegate = c
        [stroke, pinch, pan, double].forEach(v.addGestureRecognizer)
        let pencil = UIPencilInteraction()
        pencil.delegate = c
        v.addInteraction(pencil)
        c.view = v
        return v
    }

    func updateUIView(_ v: UIView, context: Context) { context.coordinator.board = board }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
        var board: BoardModel
        weak var view: UIView?
        var pencilDown = false
        private var start = CGPoint.zero
        private var lastPinch: CGFloat = 1

        init(_ board: BoardModel) { self.board = board }

        // Stroke recognizer callbacks
        private func pressure(_ t: UITouch) -> Double? {
            guard t.type == .pencil else { return nil }
            return t.maximumPossibleForce > 0 ? Double(t.force / t.maximumPossibleForce) : 0.5
        }

        func began(_ t: UITouch) {
            guard let view else { return }
            start = t.location(in: view)
            pencilDown = t.type == .pencil
            if board.tool == .pen && t.type != .pencil && board.pencilOnly {
                board.interactor.beginPan()
            } else {
                board.interactor.begin(at: start, pressure: pressure(t), grab: t.type == .pencil ? 3 : 14)
            }
        }

        func moved(_ touches: [UITouch]) {
            guard let view else { return }
            for t in touches { board.interactor.update(start: start, now: t.location(in: view), pressure: pressure(t)) }
        }

        func ended(cancelled: Bool) {
            if cancelled { board.interactor.cancel() } else { board.interactor.end() }
            pencilDown = false
        }

        // Two fingers
        @objc func pinched(_ g: UIPinchGestureRecognizer) {
            guard let view else { return }
            if g.state == .began { lastPinch = 1 }
            board.zoom(by: g.scale / lastPinch, around: g.location(in: view))
            lastPinch = g.scale
        }

        @objc func panned(_ g: UIPanGestureRecognizer) {
            guard let view else { return }
            let t = g.translation(in: view)
            board.pan.width += t.x / board.zoom
            board.pan.height += t.y / board.zoom
            g.setTranslation(.zero, in: view)
        }

        @objc func doubleTapped(_ g: UITapGestureRecognizer) {
            guard let view else { return }
            board.doubleClick(at: board.world(g.location(in: view)))
        }

        func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool {
            !(a is StrokeRecognizer) && !(b is StrokeRecognizer)
        }

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) { board.togglePencilEraser() }

        @available(iOS 17.5, *)
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
            if squeeze.phase == .ended { board.togglePencilEraser() }
        }
    }

    /// One touch at a time, with every coalesced Pencil sample; a second finger cancels it.
    final class StrokeRecognizer: UIGestureRecognizer {
        private weak var coordinator: Coordinator?
        private var tracked: UITouch?

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(target: nil, action: nil)
            allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue), NSNumber(value: UITouch.TouchType.pencil.rawValue)]
            cancelsTouchesInView = false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let t = touches.first else { return }
            if let tracked {
                // A second finger: this is a pinch or a two-finger scroll, not a stroke.
                if t.type == .direct, tracked.type == .direct { coordinator?.ended(cancelled: true); self.tracked = nil; state = .cancelled }
                else if t.type == .direct { ignore(t, for: event) }
                return
            }
            if coordinator?.pencilDown == true, t.type == .direct { ignore(t, for: event); return }
            tracked = t
            state = .began
            coordinator?.began(t)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let tracked, touches.contains(tracked) else { return }
            coordinator?.moved(event.coalescedTouches(for: tracked) ?? [tracked])
            state = .changed
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let tracked, touches.contains(tracked) else { return }
            coordinator?.ended(cancelled: false)
            self.tracked = nil
            state = .ended
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let tracked, touches.contains(tracked) else { return }
            coordinator?.ended(cancelled: true)
            self.tracked = nil
            state = .cancelled
        }

        override func reset() { tracked = nil }
    }
}
#endif
