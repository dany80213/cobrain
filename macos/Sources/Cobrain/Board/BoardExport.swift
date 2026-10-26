import SwiftUI

extension BoardModel {
    /// The whole board as a PNG (2×), cropped to its content with a margin.
    @MainActor func renderPNG(scale: CGFloat = 2) -> Data? {
        guard let first = elements.first else { return nil }
        let box = elements.dropFirst().reduce(first.frame) { $0.union($1.frame) }.insetBy(dx: -40, dy: -40)
        let items = elements
        let view = Canvas { ctx, _ in
            ctx.translateBy(x: -box.minX, y: -box.minY)
            for e in items { BoardDrawing.draw(e, in: &ctx) }
        }
        .frame(width: box.width, height: box.height).background(Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        #if canImport(UIKit)
        return renderer.uiImage?.pngData()
        #else
        guard let tiff = renderer.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
        #endif
    }
}
