import AppKit
import SwiftUI

/// WordCraft's own icons (drawn in code upstream, exported by `tools/gen_icons.py`).
enum Icons {
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let i = cache[name] { return i }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("icons/\(name).png"),
              let img = NSImage(contentsOf: url) else { return nil }
        cache[name] = img
        return img
    }
}

struct RibbonIcon: View {
    let name: String
    var size: CGFloat = 18

    var body: some View {
        if let img = Icons.image(name) {
            Image(nsImage: img).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

/// A ribbon node generated from `ribbon.rs` (see `tools/gen_ribbon.py`).
struct SpecNode: Decodable, Identifiable {
    var t: String
    var title: String?
    var icon: String?
    var label: String?
    var tip: String?
    var cmd: String?
    var params: String?
    var big: Bool?
    var items: [SpecNode]?
    let id = UUID()

    init(t: String, items: [SpecNode]? = nil) { self.t = t; self.items = items }

    enum CodingKeys: String, CodingKey { case t, title, icon, label, tip, cmd, params, big, items }

    /// A synthetic menu node holding everything in `group` (used when the group is folded).
    static func menu(of group: SpecNode) -> SpecNode {
        var flat: [SpecNode] = []
        func add(_ nodes: [SpecNode]) {
            for n in nodes {
                switch n.t {
                case "stack": add(n.items ?? [])
                case "big", "small":
                    var item = n; item.t = "item"; item.label = n.label ?? n.tip; flat.append(item)
                case "split":
                    var item = n; item.t = "item"; item.label = n.tip; flat.append(item)
                case "menu": flat.append(n)
                default: break
                }
            }
        }
        add(group.items ?? [])
        return SpecNode(t: "menu", items: flat)
    }

    static let tabs: [String: [SpecNode]] = {
        guard let data = RibbonSpecData.json.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: [SpecNode]].self, from: data) else { return [:] }
        return raw
    }()
}

private struct GroupWidths: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) { value.merge(nextValue()) { $1 } }
}

struct SpecRibbon: View {
    let groups: [SpecNode]
    let model: DocumentModel
    let selectTab: (String) -> Void
    /// Natural (fully expanded) width of each group, measured once it has been drawn expanded.
    @State private var natural: [UUID: CGFloat] = [:]
    private let collapsedWidth: CGFloat = 92

    /// Groups that fold into one drop-down, rightmost first, until the row fits (like `ribbon_fit.rs`).
    private func collapsed(for avail: CGFloat) -> Set<UUID> {
        guard groups.allSatisfy({ natural[$0.id] != nil }) else { return [] }
        var folded = Set<UUID>()
        func total() -> CGFloat { groups.reduce(0) { $0 + (folded.contains($1.id) ? collapsedWidth : natural[$1.id] ?? 0) } }
        for g in groups.reversed() where total() > avail { folded.insert(g.id) }
        return folded
    }

    var body: some View {
        GeometryReader { geo in
            let folded = collapsed(for: geo.size.width - 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(groups) { g in
                        Group {
                            if folded.contains(g.id) { collapsedGroup(g) } else { fullGroup(g) }
                        }
                        Divider().padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 4)
            }
            .onPreferenceChange(GroupWidths.self) { natural.merge($0) { $1 } }
        }
    }

    private func fullGroup(_ g: SpecNode) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(g.items ?? []) { node in nodeView(node) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            Text(g.title ?? "").font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(GeometryReader { Color.clear.preference(key: GroupWidths.self, value: [g.id: $0.size.width + 1]) })
    }

    /// A whole group folded into one button that opens its commands as a menu.
    private func collapsedGroup(_ g: SpecNode) -> some View {
        Button { popUp(SpecNode.menu(of: g)) } label: {
            VStack(spacing: 3) {
                Image(systemName: "ellipsis").font(.system(size: 18, weight: .bold)).frame(width: 32, height: 32)
                Text((g.title ?? "") + " ▾").font(.system(size: 12)).fixedSize()
            }
            .frame(width: collapsedWidth - 16).contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.horizontal, 8).padding(.vertical, 5)
    }

    private func run(_ n: SpecNode) {
        guard let cmd = n.cmd, !cmd.isEmpty else { return }
        let params = (n.params?.data(using: .utf8)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        if cmd == "ui.tab", let tab = params["tab"] as? String { selectTab(tab); return }
        if cmd == "ui.dialog" {
            model.lastError = "“\(params["name"] as? String ?? n.label ?? cmd)” dialog is not available yet"
            return
        }
        model.run(cmd, params)
    }

    private func nodeView(_ n: SpecNode) -> AnyView {
        AnyView(nodeBody(n))
    }

    @ViewBuilder private func nodeBody(_ n: SpecNode) -> some View {
        switch n.t {
        case "big": bigButton(n, arrow: false)
        case "small": smallButton(n)
        case "stack":
            VStack(alignment: .leading, spacing: 1) { ForEach(n.items ?? []) { nodeView($0) } }
        case "split": splitButton(n)
        case "menu":
            Button { popUp(n) } label: {
                if n.big == true { bigLabel(n, arrow: true) } else { smallLabel(n, arrow: true) }
            }.buttonStyle(.plain).help(n.tip ?? n.label ?? "")
        default: EmptyView()
        }
    }

    /// Shows the menu as a native NSMenu under the mouse.
    private func popUp(_ n: SpecNode) {
        let menu = NSMenu()
        build(menu, n.items ?? [])
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func build(_ menu: NSMenu, _ items: [SpecNode]) {
        for it in items {
            switch it.t {
            case "sep": menu.addItem(.separator())
            case "item":
                let mi = NSMenuItem(title: it.label ?? "", action: #selector(MenuTarget.fire), keyEquivalent: "")
                let target = MenuTarget { run(it) }
                mi.target = target
                mi.representedObject = target
                mi.isEnabled = model.isEnabled(it.cmd ?? "")
                if model.isPressed(it.cmd ?? "") { mi.state = .on }
                if let n = it.icon, let img = Icons.image(n) { img.size = NSSize(width: 16, height: 16); mi.image = img }
                menu.addItem(mi)
            case "menu":
                let mi = NSMenuItem(title: it.label ?? "", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                build(sub, it.items ?? [])
                mi.submenu = sub
                menu.addItem(mi)
            default: break
            }
        }
    }

    private func bigLabel(_ n: SpecNode, arrow: Bool) -> some View {
        VStack(spacing: 3) {
            RibbonIcon(name: n.icon ?? "", size: 32)
            Text((n.label ?? "") + (arrow ? " ▾" : ""))
                .font(.system(size: 12)).multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 46).fixedSize().padding(.horizontal, 4).contentShape(Rectangle())
    }

    private func smallLabel(_ n: SpecNode, arrow: Bool) -> some View {
        HStack(spacing: 5) {
            RibbonIcon(name: n.icon ?? "", size: 18)
            if let l = n.label { Text(l + (arrow ? " ▾" : "")).font(.system(size: 12)).fixedSize() }
            else if arrow { Text("▾").font(.system(size: 9)) }
        }
        .padding(.horizontal, 4).padding(.vertical, 2).contentShape(Rectangle())
    }

    /// Icon button that runs the command, with a small arrow that opens its menu.
    private func splitButton(_ n: SpecNode) -> some View {
        HStack(spacing: 0) {
            Button { run(n) } label: { RibbonIcon(name: n.icon ?? "", size: 18).frame(width: 24, height: 22).contentShape(Rectangle()) }
                .buttonStyle(.plain).help(n.tip ?? "")
                .disabled(!model.isEnabled(n.cmd ?? "")).opacity(model.isEnabled(n.cmd ?? "") ? 1 : 0.4)
            Button { popUp(n) } label: { Text("▾").font(.system(size: 8)).frame(width: 11, height: 22).contentShape(Rectangle()) }
                .buttonStyle(.plain)
        }
    }

    private func bigButton(_ n: SpecNode, arrow: Bool) -> some View {
        Button { run(n) } label: { bigLabel(n, arrow: arrow) }.buttonStyle(.plain).help(n.label ?? "")
            .disabled(!model.isEnabled(n.cmd ?? "")).opacity(model.isEnabled(n.cmd ?? "") ? 1 : 0.4)
            .background(model.isPressed(n.cmd ?? "") ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 4))
    }

    private func smallButton(_ n: SpecNode) -> some View {
        Button { run(n) } label: { smallLabel(n, arrow: false) }.buttonStyle(.plain).help(n.tip ?? n.label ?? "")
            .disabled(!model.isEnabled(n.cmd ?? "")).opacity(model.isEnabled(n.cmd ?? "") ? 1 : 0.4)
            .background(model.isPressed(n.cmd ?? "") ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 4))
    }
}

final class MenuTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}
