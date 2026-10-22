import SwiftUI

/// Dialogs Cobrain can show. The engine asks for most of them (`ui_requests`), the ribbon opens
/// the rest with `ui.dialog`.
enum DialogKind: Identifiable, Equatable {
    case font, paragraph, pageSetup, insertTable, link, bookmark, goTo, findReplace, zoom, wordCount, symbol
    case watermark, lineNumbers, hyphenation, field, commandSearch
    case unavailable(String)

    var id: String { if case .unavailable(let n) = self { return "unavailable-\(n)" }; return "\(self)" }

    static func named(_ name: String, label: String) -> DialogKind {
        switch name {
        case "insertTable": return .insertTable
        case "link": return .link
        case "bookmark": return .bookmark
        case "goto": return .goTo
        case "replace": return .findReplace
        case "zoom": return .zoom
        case "wordCount": return .wordCount
        case "symbol": return .symbol
        case "watermark": return .watermark
        case "lineNumbers": return .lineNumbers
        case "hyphenation": return .hyphenation
        case "field": return .field
        case "commands": return .commandSearch
        default: return .unavailable(label.replacingOccurrences(of: "…", with: ""))
        }
    }
}

struct DialogView: View {
    let kind: DialogKind
    @ObservedObject var model: DocumentModel

    var body: some View {
        switch kind {
        case .font: FontDialog(model: model)
        case .paragraph: ParagraphDialog(model: model)
        case .pageSetup: PageSetupDialog(model: model)
        case .insertTable: InsertTableDialog(model: model)
        case .link: SimpleDialog(model: model, title: "Insert Hyperlink", fields: [("Address", "url"), ("Text to display", "text")], command: "insert.link")
        case .bookmark: SimpleDialog(model: model, title: "Bookmark", fields: [("Bookmark name", "name")], command: "insert.bookmark")
        case .goTo: SimpleDialog(model: model, title: "Go To", fields: [("Page number", "#page")], command: "edit.goto", ok: "Go To")
        case .field: SimpleDialog(model: model, title: "Field", fields: [("Field code", "instr")], command: "insert.field")
        case .watermark: SimpleDialog(model: model, title: "Watermark", fields: [("Text", "text")], command: "design.watermark")
        case .findReplace: FindReplaceDialog(model: model)
        case .zoom: ZoomDialog(model: model)
        case .wordCount: WordCountDialog(model: model)
        case .symbol: SymbolDialog(model: model)
        case .lineNumbers: ChoiceDialog(model: model, title: "Line Numbers", command: "layout.lineNumbers", key: "value",
                                        choices: [("None", "none"), ("Continuous", "continuous"), ("Restart each page", "restartPage"), ("Restart each section", "restartSection")])
        case .hyphenation: ChoiceDialog(model: model, title: "Hyphenation", command: "layout.hyphenation", key: "value",
                                        choices: [("Automatic", "true"), ("None", "false")])
        case .commandSearch: CommandSearchDialog(model: model)
        case .unavailable(let name): UnavailableDialog(model: model, name: name)
        }
    }
}

/// Title, content, Cancel / OK.
struct DialogFrame<Content: View>: View {
    let title: String
    var ok = "OK"
    var width: CGFloat = 440
    let model: DocumentModel
    let onOK: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            content
            HStack {
                Spacer()
                Button("Cancel") { model.dialog = nil }.keyboardShortcut(.cancelAction)
                Button(ok) { onOK(); model.dialog = nil }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(18).frame(width: width)
    }
}

private func inches(_ pt: Double) -> Double { (pt / 72 * 100).rounded() / 100 }

/// A numeric field in inches that edits a value stored in points.
private struct PtField: View {
    let label: String
    @Binding var pt: Double
    var body: some View {
        HStack {
            Text(label).frame(width: 110, alignment: .leading)
            TextField("", value: Binding(get: { inches(pt) }, set: { pt = $0 * 72 }), format: .number).frame(width: 70).textFieldStyle(.roundedBorder)
            Text("in").foregroundStyle(.secondary)
        }
    }
}

// MARK: Font

struct FontDialog: View {
    @ObservedObject var model: DocumentModel
    @State private var name = ""
    @State private var size = ""
    @State private var flags: [String: Bool] = [:]
    @State private var color = Color.black
    @State private var families: [String] = []

    private static let toggles: [(String, String, String)] = [
        ("Bold", "bold", "format.bold"), ("Italic", "italic", "format.italic"), ("Underline", "underline", "format.underline"),
        ("Strikethrough", "strike", "format.strikethrough"), ("Superscript", "superscript", "format.superscript"),
        ("Subscript", "subscript", "format.subscript"), ("Small caps", "smallCaps", "format.smallCaps"),
        ("All caps", "caps", "format.allCaps"), ("Hidden", "hidden", "format.hidden"),
    ]

    var body: some View {
        DialogFrame(title: "Font", model: model, onOK: apply) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Font")
                    TextField("", text: $name).textFieldStyle(.roundedBorder)
                    List(families.filter { name.isEmpty || $0.localizedCaseInsensitiveContains(name) }, id: \.self) { f in
                        Text(f).font(.custom(f, size: 13)).onTapGesture { name = f }
                    }.frame(height: 150)
                }
                VStack(alignment: .leading) {
                    Text("Size")
                    TextField("", text: $size).textFieldStyle(.roundedBorder).frame(width: 80)
                    ColorPicker("Font color", selection: $color)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
                ForEach(Self.toggles, id: \.1) { t in
                    Toggle(t.0, isOn: Binding(get: { flags[t.1] ?? false }, set: { flags[t.1] = $0 }))
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        name = model.format["font"] as? String ?? ""
        if let s = model.format["size"] as? Double { size = s == s.rounded() ? String(Int(s)) : String(s) }
        for t in Self.toggles { flags[t.1] = model.isOn(t.1) }
        if case .success(let r) = model.engine.run("font.list", ["all": true]) {
            families = ((r as? [String]) ?? ((r as? [String: Any])?["families"] as? [String]) ?? []).sorted()
        }
        if families.isEmpty { families = NSFontManager.shared.availableFontFamilies }
    }

    private func apply() {
        if name != (model.format["font"] as? String ?? "") { model.run("format.font", ["name": name]) }
        if let v = Double(size), v != (model.format["size"] as? Double ?? 0) { model.run("format.size", ["size": v]) }
        for t in Self.toggles where (flags[t.1] ?? false) != model.isOn(t.1) {
            // Sub/superscript and the caps variants flip with no value.
            model.run(t.2, ["bold", "italic", "underline", "strike"].contains(t.1) ? ["value": flags[t.1] ?? false] : [:])
        }
        if let c = NSColor(color).usingColorSpace(.sRGB) {
            let hex = String(format: "%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
            if hex != "000000" { model.run("format.color", ["color": hex]) }
        }
    }
}

// MARK: Paragraph

struct ParagraphDialog: View {
    @ObservedObject var model: DocumentModel
    @State private var align = "left"
    @State private var left = 0.0
    @State private var right = 0.0
    @State private var first = 0.0
    @State private var before = 0.0
    @State private var after = 0.0
    @State private var line = "1.0"
    @State private var keepNext = false
    @State private var keepLines = false
    @State private var pageBreak = false
    @State private var widow = true

    var body: some View {
        DialogFrame(title: "Paragraph", model: model, onOK: apply) {
            Picker("Alignment", selection: $align) {
                ForEach(["left", "center", "right", "justify"], id: \.self) { Text($0.capitalized).tag($0) }
            }.pickerStyle(.segmented)
            GroupBox("Indentation") {
                VStack(alignment: .leading) {
                    PtField(label: "Left", pt: $left); PtField(label: "Right", pt: $right); PtField(label: "First line", pt: $first)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Spacing") {
                VStack(alignment: .leading) {
                    PtField(label: "Before", pt: $before); PtField(label: "After", pt: $after)
                    HStack { Text("Line spacing").frame(width: 110, alignment: .leading); TextField("", text: $line).frame(width: 70).textFieldStyle(.roundedBorder) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Toggle("Keep with next", isOn: $keepNext); Toggle("Keep lines together", isOn: $keepLines)
                Toggle("Page break before", isOn: $pageBreak); Toggle("Widow/orphan control", isOn: $widow)
            }.toggleStyle(.checkbox).font(.system(size: 11))
        }
        .onAppear(perform: load)
    }

    private func num(_ v: Any?) -> Double { (v as? Double) ?? Double((v as? Int) ?? 0) }

    private func load() {
        let p = model.engine.paraState()
        align = (p["align"] as? String) ?? "left"
        left = num(p["indent_left"]); right = num(p["indent_right"]); first = num(p["indent_first"])
        before = num(p["space_before"]); after = num(p["space_after"])
        keepNext = p["keep_next"] as? Bool ?? false; keepLines = p["keep_lines"] as? Bool ?? false
        pageBreak = p["page_break_before"] as? Bool ?? false; widow = p["widow_control"] as? Bool ?? true
        if let ls = p["line_spacing"] as? [String: Any], let m = ls["multiple"] as? Double { line = String(m) }
    }

    private func apply() {
        model.run("para.set", ["props": ["align": align, "indentLeft": left, "indentRight": right, "indentFirst": first,
                                         "spaceBefore": before, "spaceAfter": after, "keepNext": keepNext, "keepLines": keepLines,
                                         "pageBreakBefore": pageBreak, "widowControl": widow]])
        if let v = Double(line) { model.run("para.lineSpacing", ["value": v]) }
    }
}

// MARK: Page setup

struct PageSetupDialog: View {
    @ObservedObject var model: DocumentModel
    @State private var top = 72.0
    @State private var bottom = 72.0
    @State private var left = 72.0
    @State private var right = 72.0
    @State private var orientation = "portrait"
    @State private var paper = "Letter"

    var body: some View {
        DialogFrame(title: "Page Setup", model: model, onOK: apply) {
            GroupBox("Margins") {
                VStack(alignment: .leading) {
                    PtField(label: "Top", pt: $top); PtField(label: "Bottom", pt: $bottom)
                    PtField(label: "Left", pt: $left); PtField(label: "Right", pt: $right)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Picker("Orientation", selection: $orientation) { Text("Portrait").tag("portrait"); Text("Landscape").tag("landscape") }.pickerStyle(.segmented)
            Picker("Paper size", selection: $paper) { ForEach(["Letter", "Legal", "A4", "A3", "A5"], id: \.self) { Text($0) } }
        }
    }

    private func apply() {
        model.run("layout.margins", ["top": top, "bottom": bottom, "left": left, "right": right])
        model.run("layout.orientation", ["value": orientation])
        model.run("layout.size", ["name": paper])
    }
}

// MARK: Table, link, bookmark and other one-shot dialogs

struct InsertTableDialog: View {
    @ObservedObject var model: DocumentModel
    @State private var rows = 3
    @State private var cols = 3
    var body: some View {
        DialogFrame(title: "Insert Table", width: 300, model: model, onOK: { model.run("insert.table", ["rows": rows, "cols": cols]) }) {
            Stepper("Number of columns: \(cols)", value: $cols, in: 1...63)
            Stepper("Number of rows: \(rows)", value: $rows, in: 1...32767)
        }
    }
}

/// Text fields mapped to one command's params. A field named `#x` is sent as a number.
struct SimpleDialog: View {
    @ObservedObject var model: DocumentModel
    let title: String
    let fields: [(label: String, key: String)]
    let command: String
    var ok = "OK"
    @State private var values: [String: String] = [:]

    var body: some View {
        DialogFrame(title: title, ok: ok, width: 380, model: model, onOK: {
            var params: [String: Any] = [:]
            for f in fields {
                guard let v = values[f.key], !v.isEmpty else { continue }
                if f.key.hasPrefix("#") { params[String(f.key.dropFirst())] = Double(v) ?? 0 } else { params[f.key] = v }
            }
            model.run(command, params)
        }) {
            ForEach(fields, id: \.key) { f in
                TextField(f.label, text: Binding(get: { values[f.key] ?? "" }, set: { values[f.key] = $0 })).textFieldStyle(.roundedBorder)
            }
        }
    }
}

struct ChoiceDialog: View {
    @ObservedObject var model: DocumentModel
    let title: String
    let command: String
    let key: String
    let choices: [(String, String)]
    @State private var pick = ""

    var body: some View {
        DialogFrame(title: title, width: 320, model: model, onOK: {
            let v: Any = pick == "true" ? (true as Any) : (pick == "false" ? (false as Any) : (pick as Any))
            model.run(command, [key: v])
        }) {
            Picker("", selection: $pick) { ForEach(choices, id: \.1) { Text($0.0).tag($0.1) } }.pickerStyle(.radioGroup).labelsHidden()
        }
        .onAppear { pick = choices.first?.1 ?? "" }
    }
}

// MARK: Find and replace

struct FindReplaceDialog: View {
    @ObservedObject var model: DocumentModel
    @State private var find = ""
    @State private var replace = ""
    @State private var matchCase = false
    @State private var wholeWord = false
    @State private var status = ""

    private var opts: [String: Any] { ["matchCase": matchCase, "wholeWord": wholeWord] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find and Replace").font(.headline)
            TextField("Find what", text: $find).textFieldStyle(.roundedBorder)
            TextField("Replace with", text: $replace).textFieldStyle(.roundedBorder)
            HStack { Toggle("Match case", isOn: $matchCase); Toggle("Find whole words only", isOn: $wholeWord) }.toggleStyle(.checkbox)
            Text(status).font(.caption).foregroundStyle(.secondary).frame(height: 14)
            HStack {
                Button("Find Next") { go("edit.findNext", opts.merging(["text": find]) { $1 }) }.keyboardShortcut(.defaultAction)
                Button("Replace") { go("edit.replace", opts.merging(["text": find, "with": replace]) { $1 }) }
                Button("Replace All") { go("edit.replaceAll", opts.merging(["text": find, "with": replace]) { $1 }) }
                Spacer()
                Button("Close") { model.dialog = nil }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(18).frame(width: 440)
    }

    private func go(_ cmd: String, _ params: [String: Any]) {
        switch model.engine.run(cmd, params) {
        case .success(let r):
            if let d = r as? [String: Any], let n = (d["replaced"] ?? d["count"]) as? Int { status = "\(n) replacement(s)" } else { status = "" }
        case .failure(let e): status = e.message
        }
        model.run("edit.noop")  // refresh state/view
    }
}

struct ZoomDialog: View {
    @ObservedObject var model: DocumentModel
    @State private var percent = 100.0
    var body: some View {
        DialogFrame(title: "Zoom", width: 320, model: model, onOK: { model.zoom = CGFloat(percent / 100) }) {
            HStack { Slider(value: $percent, in: 25...300, step: 5); Text("\(Int(percent))%").frame(width: 50) }
        }.onAppear { percent = Double(model.zoom * 100) }
    }
}

struct WordCountDialog: View {
    @ObservedObject var model: DocumentModel
    @State private var rows: [(String, String)] = []
    var body: some View {
        DialogFrame(title: "Word Count", ok: "Close", width: 300, model: model, onOK: {}) {
            ForEach(rows, id: \.0) { r in HStack { Text(r.0); Spacer(); Text(r.1).foregroundStyle(.secondary) } }
        }
        .onAppear {
            if case .success(let r) = model.engine.run("review.wordCount"), let d = r as? [String: Any] {
                rows = d.sorted { $0.key < $1.key }.map { ($0.key.capitalized, "\($0.value)") }
            }
        }
    }
}

struct SymbolDialog: View {
    @ObservedObject var model: DocumentModel
    @State private var picked = ""
    private let chars = Array("©®™§¶€£¥°±≠≤≥÷×∞µαβγδεζηθλμπσφωΩ∑∫√∂∆→←↑↓↔⇒✓✗★☆♥♦♣♠•…–—‘’“”«»¿¡".map(String.init))
    var body: some View {
        DialogFrame(title: "Symbol", ok: "Insert", width: 420, model: model, onOK: { if !picked.isEmpty { model.run("insert.symbol", ["char": picked]) } }) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 2), count: 10), spacing: 2) {
                ForEach(chars, id: \.self) { c in
                    Text(c).font(.system(size: 17)).frame(width: 34, height: 30)
                        .background(picked == c ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.08)).onTapGesture { picked = c }
                }
            }
        }
    }
}

/// "Search commands and help": filter the catalog and run a command.
struct CommandSearchDialog: View {
    @ObservedObject var model: DocumentModel
    @State private var query = ""
    private var results: [CommandInfo] {
        let q = query.lowercased()
        return model.catalog.filter { q.isEmpty ? false : $0.label.lowercased().contains(q) || $0.id.lowercased().contains(q) }.prefix(12).map { $0 }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search commands and help", text: $query).textFieldStyle(.roundedBorder)
            ForEach(results) { c in
                Button { model.dialog = nil; if c.needsInput { model.dialog = .unavailable(c.label) } else { model.run(c.id) } } label: {
                    HStack { Text(c.label); Spacer(); Text(c.location).font(.caption).foregroundStyle(.secondary) }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            HStack { Spacer(); Button("Close") { model.dialog = nil }.keyboardShortcut(.cancelAction) }
        }
        .padding(16).frame(width: 460)
    }
}

struct UnavailableDialog: View {
    @ObservedObject var model: DocumentModel
    let name: String
    var body: some View {
        DialogFrame(title: name, ok: "OK", width: 340, model: model, onOK: {}) {
            Text("This dialog has not been ported to Cobrain yet.").foregroundStyle(.secondary)
        }
    }
}
