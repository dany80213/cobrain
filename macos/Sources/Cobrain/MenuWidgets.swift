import AppKit
import SwiftUI

/// Custom controls that sit inside ribbon menus (ported from WordCraft's egui widgets).
enum MenuWidget {
    /// `NSMenuItem` hosting a SwiftUI view; picking something closes the menu.
    static func item<V: View>(_ view: V) -> NSMenuItem {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let item = NSMenuItem()
        item.view = host
        return item
    }

    /// The menu being shown, so a pick inside a hosted view can dismiss it.
    static weak var active: NSMenu?
    static func close() { active?.cancelTracking() }
}

struct TableGridView: View {
    let pick: (Int, Int) -> Void
    @State private var hover = (r: 0, c: 0)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hover.r > 0 ? "\(hover.c)×\(hover.r) Table" : "Insert Table").font(.system(size: 12))
            VStack(spacing: 2) {
                ForEach(1...8, id: \.self) { r in
                    HStack(spacing: 2) {
                        ForEach(1...10, id: \.self) { c in
                            let on = r <= hover.r && c <= hover.c
                            Rectangle().fill(on ? Color.accentColor.opacity(0.25) : Color.white)
                                .frame(width: 16, height: 16)
                                .overlay(Rectangle().stroke(on ? Color.accentColor : Color.gray.opacity(0.6), lineWidth: 1))
                                .onHover { if $0 { hover = (r, c) } }
                                .onTapGesture { pick(r, c) }
                        }
                    }
                }
            }
        }
        .padding(10)
    }
}

/// Theme colours with tints, standard colours and More Colors… (`widgets::color_grid`).
struct ColorGridView: View {
    let theme: [String]
    let pick: (String) -> Void
    let more: () -> Void

    private static let standard = ["C00000", "FF0000", "FFC000", "FFFF00", "92D050", "00B050", "00B0F0", "0070C0", "002060", "7030A0"]

    private func tint(_ hex: String, _ k: Double) -> String {
        guard let v = UInt32(hex, radix: 16) else { return hex }
        func f(_ c: UInt32) -> UInt32 {
            let x = Double(c)
            return UInt32(max(0, min(255, k >= 0 ? x + (255 - x) * k : x * (1 + k))))
        }
        return String(format: "%02X%02X%02X", f((v >> 16) & 255), f((v >> 8) & 255), f(v & 255))
    }

    private func swatch(_ hex: String) -> some View {
        Rectangle().fill(Color(hex: hex)).frame(width: 15, height: 15)
            .overlay(Rectangle().stroke(Color.gray.opacity(0.6), lineWidth: 0.5))
            .help("#\(hex)").onTapGesture { pick(hex) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Theme Colors").font(.system(size: 10)).foregroundStyle(.secondary)
            let order = [1, 0, 3, 2, 4, 5, 6, 7, 8, 9]
            ForEach([0.0, 0.8, 0.6, 0.4, -0.25, -0.5], id: \.self) { k in
                HStack(spacing: 3) {
                    ForEach(order, id: \.self) { i in
                        if theme.indices.contains(i) { swatch(tint(theme[i], k)) }
                    }
                }
                .padding(.bottom, k == 0 ? 3 : 0)
            }
            Text("Standard Colors").font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 4)
            HStack(spacing: 3) { ForEach(Self.standard, id: \.self) { swatch($0) } }
            Divider().padding(.vertical, 3)
            Button(action: more) {
                HStack(spacing: 6) {
                    Circle().fill(AngularGradient(gradient: Gradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red]), center: .center))
                        .frame(width: 13, height: 13)
                    Text("More Colors…").font(.system(size: 12))
                    Spacer()
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(10).frame(width: 190)
    }
}

struct SymbolGridView: View {
    let pick: (String) -> Void
    private static let symbols = ["©", "®", "™", "§", "¶", "€", "£", "¥", "°", "±", "≠", "≤", "≥", "÷", "×", "∞", "µ", "α", "β", "π", "Ω", "∑", "√", "→", "←", "✓", "★", "♥", "—", "…"]

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<6, id: \.self) { col in
                        let s = Self.symbols[row * 6 + col]
                        Text(s).font(.system(size: 16)).frame(width: 30, height: 28)
                            .background(Color.gray.opacity(0.08)).onTapGesture { pick(s) }
                    }
                }
            }
        }.padding(10)
    }
}

extension Color {
    init(hex: String) {
        let v = UInt32(hex, radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}

/// Sets a colour from the system colour panel (More Colors…).
final class ColorPanelTarget: NSObject {
    static var current: ColorPanelTarget?
    let apply: (String) -> Void
    init(_ apply: @escaping (String) -> Void) { self.apply = apply }

    @objc func changed(_ sender: NSColorPanel) {
        guard let c = sender.color.usingColorSpace(.sRGB) else { return }
        apply(String(format: "%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255)))
    }

    static func show(apply: @escaping (String) -> Void) {
        let t = ColorPanelTarget(apply)
        current = t
        let panel = NSColorPanel.shared
        panel.setTarget(t)
        panel.setAction(#selector(ColorPanelTarget.changed(_:)))
        panel.makeKeyAndOrderFront(nil)
    }
}
