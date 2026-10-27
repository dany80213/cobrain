import CoreGraphics
import Foundation
import ImageIO

/// First-page thumbnails of documents and whiteboards for the Home and subject views.
@MainActor enum FileThumbnails {
    private static var cache: [String: CGImage] = [:]

    static func image(for url: URL, width: CGFloat = 340) -> CGImage? {
        let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)#\(mod)#\(width)"
        if let c = cache[key] { return c }
        var img: CGImage?
        if url.pathExtension.lowercased() == "cobrainboard" {
            guard let data = try? Data(contentsOf: url) else { return nil }
            let board = BoardModel()
            try? board.load(data)
            if let png = board.renderPNG(scale: 1), let src = CGImageSourceCreateWithData(png as CFData, nil) { img = CGImageSourceCreateImageAtIndex(src, 0, nil) }
        } else if let e = Engine(path: url.path), let size = e.pageSize(0) {
            img = e.renderPage(0, scale: width / size.width)
        }
        if let img { cache[key] = img }
        return img
    }
}
