import SwiftUI

/// Word-style ribbon generated from the engine's command catalog (`Tab › Group` locations).
struct RibbonView: View {
    @ObservedObject var model: DocumentModel
    @State private var tab = ProcessInfo.processInfo.environment["COBRAIN_TAB"] ?? "Home"
    @State private var pending: CommandInfo?

    static let baseTabs = ["File", "Home", "Insert", "Draw", "Design", "Layout", "References", "Mailings", "Review", "View", "Developer", "Zotero", "Help"]

    /// File, the standard tabs, then the ones that come up with the selection (Outlining sits next to File).
    private var tabs: [String] {
        var t = Self.baseTabs
        for c in model.contextualTabs {
            if c == "Outlining" { t.insert(c, at: 1) } else if !t.contains(c) { t.append(c) }
        }
        return t
    }

    private var shownTab: String { tabs.contains(tab) ? tab : "Home" }

    private var groups: [(name: String, commands: [CommandInfo])] {
        var order: [String] = []
        var map: [String: [CommandInfo]] = [:]
        for c in model.catalog where c.tab == shownTab {
            let g = c.group.isEmpty ? shownTab : c.group
            if map[g] == nil { order.append(g) }
            map[g, default: []].append(c)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(tabs, id: \.self) { t in
                    Button { tab = t } label: {
                        Text(t).font(.system(size: 12, weight: shownTab == t ? .semibold : .regular))
                            .foregroundStyle(model.contextualTabs.contains(t) ? Color.accentColor : .primary)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(shownTab == t ? Color(nsColor: .controlBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 8).padding(.top, 4)
            Divider()
            Group {
                if shownTab == "Home" {
                    HomeRibbon(model: model) { pending = $0 }
                } else if let spec = SpecNode.tabs[shownTab], !spec.isEmpty {
                    SpecRibbon(groups: spec, model: model) { tab = $0 }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(groups, id: \.name) { g in
                                GroupView(name: g.name, commands: g.commands, model: model) { pending = $0 }
                                Divider().padding(.vertical, 4)
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                }
            }
            .frame(height: 100).clipped()
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
        }
        .sheet(item: $pending) { cmd in ParamSheet(command: cmd, model: model) }
    }
}

private struct GroupView: View {
    let name: String
    let commands: [CommandInfo]
    let model: DocumentModel
    let onNeedsInput: (CommandInfo) -> Void

    var body: some View {
        VStack(spacing: 2) {
            let cols = stride(from: 0, to: commands.count, by: 3).map { Array(commands[$0..<min($0 + 3, commands.count)]) }
            HStack(alignment: .top, spacing: 2) {
                ForEach(cols.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(cols[i]) { c in
                            Button {
                                if c.needsInput { onNeedsInput(c) } else { model.run(c.id) }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: Self.symbol(for: c.id)).frame(width: 14)
                                    Text(c.label).lineLimit(1)
                                }
                                .font(.system(size: 11))
                                .frame(maxWidth: 150, alignment: .leading)
                                .padding(.horizontal, 5).padding(.vertical, 3)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RibbonButtonStyle())
                            .help(c.shortcut.isEmpty ? c.label : "\(c.label) (\(c.shortcut.replacingOccurrences(of: "Mod", with: "⌘")))")
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 2)
    }

    static func symbol(for id: String) -> String {
        let known: [String: String] = [
            "format.bold": "bold", "format.italic": "italic", "format.underline": "underline",
            "format.strikethrough": "strikethrough", "format.subscript": "textformat.subscript",
            "format.superscript": "textformat.superscript", "edit.undo": "arrow.uturn.backward",
            "edit.redo": "arrow.uturn.forward", "file.save": "square.and.arrow.down", "file.open": "folder",
            "file.new": "doc", "file.print": "printer", "file.exportPdf": "doc.richtext",
        ]
        if let s = known[id] { return s }
        if id.hasPrefix("para.align") { return "text.alignleft" }
        if id.hasPrefix("insert.") { return "plus.square" }
        return "circle.grid.2x2"
    }
}

private struct RibbonButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.accentColor.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
    }
}

/// Asks for the required parameters of a command, then runs it.
private struct ParamSheet: View {
    let command: CommandInfo
    let model: DocumentModel
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(command.label).font(.headline)
            ForEach(command.paramFields, id: \.name) { f in
                TextField("\(f.name)\(f.required ? "" : " (optional)") — \(f.type)", text: Binding(
                    get: { values[f.name] ?? "" }, set: { values[f.name] = $0 }))
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Run") {
                    var params: [String: Any] = [:]
                    for f in command.paramFields {
                        guard let v = values[f.name], !v.isEmpty else { continue }
                        if let d = Double(v) { params[f.name] = d } else if v == "true" || v == "false" { params[f.name] = (v == "true") } else { params[f.name] = v }
                    }
                    model.run(command.id, params)
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16).frame(width: 380)
    }
}
