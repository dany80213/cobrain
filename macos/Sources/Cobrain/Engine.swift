import CCobrain
import CoreGraphics
import Foundation

/// Swift wrapper around one engine session (`CobrainDoc`).
final class Engine {
    private var handle: OpaquePointer?

    struct Page { var width: CGFloat; var height: CGFloat }
    struct Caret { var page: Int; var x: CGFloat; var top: CGFloat; var height: CGFloat }

    static var version: String {
        guard let s = cobrain_engine_version() else { return "?" }
        defer { cobrain_free_string(s) }
        return String(cString: s)
    }

    init?() {
        guard let h = cobrain_new_blank() else { return nil }
        handle = h
    }

    init?(path: String) {
        guard let h = cobrain_open(path) else { return nil }
        handle = h
    }

    deinit { cobrain_free(handle) }

    func save(to path: String) -> Bool { cobrain_save(handle, path) == 0 }

    var pageCount: Int { Int(cobrain_page_count(handle)) }

    func pageSize(_ index: Int) -> Page? {
        var w: Float = 0, h: Float = 0
        guard cobrain_page_size(handle, UInt32(index), &w, &h) == 0 else { return nil }
        return Page(width: CGFloat(w), height: CGFloat(h))
    }

    /// Straight RGBA8 raster of a page; `scale` is pixels per point.
    func renderPage(_ index: Int, scale: CGFloat) -> CGImage? {
        var w: UInt32 = 0, h: UInt32 = 0
        guard let ptr = cobrain_render_page(handle, UInt32(index), Float(scale), &w, &h) else { return nil }
        let len = Int(w) * Int(h) * 4
        defer { cobrain_free_buffer(ptr, len) }
        let data = Data(bytes: ptr, count: len)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: Int(w), height: Int(h), bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: Int(w) * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    func click(page: Int, x: CGFloat, y: CGFloat) {
        _ = cobrain_click(handle, UInt32(page), Float(x), Float(y))
    }

    var caret: Caret? {
        var page: UInt32 = 0
        var x: Float = 0, top: Float = 0, height: Float = 0
        guard cobrain_caret(handle, &page, &x, &top, &height) == 0 else { return nil }
        return Caret(page: Int(page), x: CGFloat(x), top: CGFloat(top), height: CGFloat(height))
    }

    /// Run an engine command by id. Returns the `ok` payload, or nil (and the error text) on failure.
    @discardableResult
    func run(_ id: String, _ params: [String: Any] = [:]) -> Result<Any, EngineError> {
        let json = (try? JSONSerialization.data(withJSONObject: params)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        guard let out = cobrain_run(handle, id, json) else { return .failure(EngineError(message: "engine unavailable")) }
        defer { cobrain_free_string(out) }
        let obj = try? JSONSerialization.jsonObject(with: Data(String(cString: out).utf8)) as? [String: Any]
        if let err = obj?["error"] as? String { return .failure(EngineError(message: err)) }
        return .success(obj?["ok"] ?? NSNull())
    }
}

struct EngineError: Error, LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
