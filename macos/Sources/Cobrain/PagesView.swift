import AppKit
import SwiftUI

/// Draws the engine's pages and turns clicks and keystrokes into engine commands.
final class PagesNSView: NSView {
    var model: DocumentModel
    private var cache: [Int: (rev: Int, scale: CGFloat, image: CGImage)] = [:]
    private var pageRects: [CGRect] = []
    private let gap: CGFloat = 16

    init(model: DocumentModel) {
        self.model = model
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func reload() {
        relayout()
        needsDisplay = true
    }

    private func relayout() {
        let z = model.zoom
        var y = gap
        var maxW: CGFloat = 0
        pageRects = []
        for i in 0..<model.engine.pageCount {
            guard let p = model.engine.pageSize(i) else { continue }
            pageRects.append(CGRect(x: 0, y: y, width: p.width * z, height: p.height * z))
            y += p.height * z + gap
            maxW = max(maxW, p.width * z)
        }
        let width = max(maxW + 2 * gap, enclosingScrollView?.contentSize.width ?? 0)
        for i in pageRects.indices { pageRects[i].origin.x = (width - pageRects[i].width) / 2 }
        setFrameSize(NSSize(width: width, height: y))
    }

    override func draw(_ dirty: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        dirty.fill()
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let scale = (window?.backingScaleFactor ?? 2) * model.zoom
        for (i, rect) in pageRects.enumerated() where rect.intersects(dirty) {
            var entry = cache[i]
            if entry == nil || entry!.rev != model.revision || entry!.scale != scale {
                if let img = model.engine.renderPage(i, scale: scale) {
                    entry = (model.revision, scale, img)
                    cache[i] = entry
                }
            }
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: NSColor.black.withAlphaComponent(0.3).cgColor)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(rect)
            ctx.restoreGState()
            if let img = entry?.image {
                // CGContext in a flipped view draws images upside down; flip locally.
                ctx.saveGState()
                ctx.translateBy(x: rect.minX, y: rect.maxY)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(img, in: CGRect(origin: .zero, size: rect.size))
                ctx.restoreGState()
            }
        }
        if let c = model.engine.caret, pageRects.indices.contains(c.page), caretOn {
            let r = pageRects[c.page]
            let z = model.zoom
            NSColor.black.setFill()
            NSRect(x: r.minX + c.x * z, y: r.minY + c.top * z, width: 1, height: c.height * z).fill()
        }
    }

    // MARK: caret blink

    private var caretOn = true
    private var blink: Timer?

    override func viewDidMoveToWindow() {
        blink?.invalidate()
        guard window != nil else { return }
        blink = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            guard let self, self.window?.firstResponder === self else { return }
            self.caretOn.toggle()
            self.needsDisplay = true
        }
    }

    // MARK: input

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        guard let i = pageRects.firstIndex(where: { $0.contains(p) }) else { return }
        let r = pageRects[i]
        caretOn = true
        model.click(page: i, x: (p.x - r.minX) / model.zoom, y: (p.y - r.minY) / model.zoom)
    }

    override func keyDown(with event: NSEvent) {
        caretOn = true
        interpretKeyEvents([event])
    }

    override func insertText(_ insertString: Any) {
        let s = (insertString as? NSAttributedString)?.string ?? (insertString as? String) ?? ""
        if !s.isEmpty { model.run("text.insert", ["text": s]) }
    }

    override func doCommand(by selector: Selector) {
        let name = NSStringFromSelector(selector)
        let extend = name.hasSuffix("AndModifySelection:")
        let base = name.replacingOccurrences(of: "AndModifySelection:", with: "").replacingOccurrences(of: ":", with: "")
        let caret: [String: String] = [
            "moveLeft": "caret.left", "moveRight": "caret.right", "moveUp": "caret.up", "moveDown": "caret.down",
            "moveWordLeft": "caret.wordLeft", "moveWordRight": "caret.wordRight",
            "moveToBeginningOfLine": "caret.home", "moveToEndOfLine": "caret.end",
            "moveToBeginningOfDocument": "caret.docStart", "moveToEndOfDocument": "caret.docEnd",
            "pageUp": "caret.pageUp", "pageDown": "caret.pageDown",
        ]
        if let id = caret[base] {
            model.run(id, extend ? ["extend": true] : [:])
            return
        }
        switch base {
        case "insertNewline": model.run("text.newParagraph")
        case "insertLineBreak", "insertNewlineIgnoringFieldEditor": model.run("text.lineBreak")
        case "insertTab": model.run("text.tab")
        case "insertBacktab": model.run("text.backTab")
        case "deleteBackward": model.run("text.backspace")
        case "deleteForward": model.run("text.delete")
        case "deleteWordBackward": model.run("text.deleteWordBack")
        case "deleteWordForward": model.run("text.deleteWordForward")
        default: NSSound.beep()
        }
    }
}

struct PagesView: NSViewRepresentable {
    @ObservedObject var model: DocumentModel

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .underPageBackgroundColor
        let view = PagesNSView(model: model)
        scroll.documentView = view
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? PagesNSView else { return }
        view.model = model
        _ = model.revision  // redraw dependency
        view.reload()
    }
}
