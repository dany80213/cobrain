import SwiftUI

/// The Home tab laid out like WordCraft's: Clipboard, Font, Paragraph, Styles, Editing.
struct HomeRibbon: View {
    @ObservedObject var model: DocumentModel
    let onNeedsInput: (CommandInfo) -> Void
    @State private var fontName = ""
    @State private var fontSize = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(alignment: .top, spacing: 0) {
            clipboard; sep
            font; sep
            paragraph; sep
            styles; sep
            editing
        } }
        .padding(.horizontal, 6)
        .onChange(of: model.revision) { _ in syncFields() }
        .onAppear { syncFields() }
    }

    private func syncFields() {
        fontName = model.format["font"] as? String ?? ""
        if let s = model.format["size"] as? Double { fontSize = s == s.rounded() ? String(Int(s)) : String(s) }
    }

    private var sep: some View { Divider().padding(.vertical, 6) }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 2) {
            content().frame(maxHeight: .infinity, alignment: .top)
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func icon(_ symbol: String, _ id: String, help: String, on: Bool = false, params: [String: Any] = [:]) -> some View {
        Button { model.run(id, params) } label: {
            Image(systemName: symbol).frame(width: 24, height: 22)
                .background(on ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain).help(help)
    }

    private func small(_ title: String, _ symbol: String, _ id: String) -> some View {
        Button { model.run(id) } label: {
            HStack(spacing: 5) { Image(systemName: symbol).frame(width: 16); Text(title).font(.system(size: 12)) }
                .frame(width: 80, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var clipboard: some View {
        group("Clipboard") {
            HStack(alignment: .top, spacing: 6) {
                Button { model.paste() } label: {
                    VStack(spacing: 2) { Image(systemName: "doc.on.clipboard").font(.system(size: 28)); Text("Paste ▾").font(.system(size: 12)) }
                        .frame(width: 52).contentShape(Rectangle())
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 4) {
                    small("Cut", "scissors", "edit.cut")
                    small("Copy", "doc.on.doc", "edit.copy")
                    small("Format", "paintbrush", "edit.formatPainter")
                }
            }
        }
    }

    private var font: some View {
        group("Font") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    TextField("Font", text: $fontName).textFieldStyle(.roundedBorder).frame(width: 150)
                        .onSubmit { model.run("format.font", ["name": fontName]) }
                    TextField("Size", text: $fontSize).textFieldStyle(.roundedBorder).frame(width: 46)
                        .onSubmit { if let v = Double(fontSize) { model.run("format.size", ["size": v]) } }
                    icon("textformat.size.larger", "format.growFont", help: "Increase Font Size")
                    icon("textformat.size.smaller", "format.shrinkFont", help: "Decrease Font Size")
                    icon("eraser", "format.clear", help: "Clear All Formatting")
                }
                HStack(spacing: 2) {
                    icon("bold", "format.bold", help: "Bold (⌘B)", on: model.isOn("bold"))
                    icon("italic", "format.italic", help: "Italic (⌘I)", on: model.isOn("italic"))
                    icon("underline", "format.underline", help: "Underline (⌘U)", on: model.isOn("underline"))
                    icon("strikethrough", "format.strikethrough", help: "Strikethrough", on: model.isOn("strike"))
                    icon("textformat.subscript", "format.subscript", help: "Subscript", on: model.isOn("subscript"))
                    icon("textformat.superscript", "format.superscript", help: "Superscript", on: model.isOn("superscript"))
                    Divider().frame(height: 16)
                    icon("highlighter", "format.highlight", help: "Text Highlight Color", params: ["color": "yellow"])
                    Menu {
                        ForEach([("Black", "000000"), ("Red", "C00000"), ("Blue", "1F4E9E"), ("Green", "2E7D32"), ("Automatic", "auto")], id: \.1) { n, c in
                            Button(n) { model.run("format.color", ["color": c]) }
                        }
                    } label: { Image(systemName: "a.square").foregroundStyle(.red) }
                        .menuStyle(.borderlessButton).frame(width: 34).help("Font Color")
                }
            }
        }
    }

    private var paragraph: some View {
        group("Paragraph") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 2) {
                    icon("list.bullet", "para.bullets", help: "Bullets")
                    icon("list.number", "para.numbering", help: "Numbering")
                    icon("list.bullet.indent", "para.multilevel", help: "Multilevel List")
                    Divider().frame(height: 16)
                    icon("decrease.indent", "para.outdent", help: "Decrease Indent")
                    icon("increase.indent", "para.indent", help: "Increase Indent")
                    icon("textformat.abc", "para.sort", help: "Sort")
                    icon("paragraphsign", "view.marks", help: "Show/Hide ¶")
                }
                HStack(spacing: 2) {
                    icon("text.alignleft", "para.alignLeft", help: "Align Left")
                    icon("text.aligncenter", "para.alignCenter", help: "Center")
                    icon("text.alignright", "para.alignRight", help: "Align Right")
                    icon("text.justify", "para.justify", help: "Justify")
                    Divider().frame(height: 16)
                    Menu {
                        Button("Single") { model.run("para.single") }
                        Button("1.5") { model.run("para.oneAndHalf") }
                        Button("Double") { model.run("para.double") }
                    } label: { Image(systemName: "arrow.up.and.down.text.horizontal") }
                        .menuStyle(.borderlessButton).frame(width: 34).help("Line and Paragraph Spacing")
                }
            }
        }
    }

    private var styles: some View {
        group("Styles") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(model.styles, id: \.id) { s in
                        let current = (model.format["style"] as? String) == s.id
                        Button { model.run("para.style", ["style": s.id]) } label: {
                            VStack(spacing: 4) {
                                Text("AaBbCcDd").font(Self.preview(s.id)).foregroundStyle(Self.previewColor(s.id)).lineLimit(1)
                                    .frame(height: 30)
                                Text(s.name).font(.system(size: 11))
                            }
                            .frame(width: 82).padding(.vertical, 6)
                            .background(current ? Color.accentColor.opacity(0.18) : Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(current ? Color.accentColor : Color.secondary.opacity(0.3)))
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(width: 330)
        }
    }

    private var editing: some View {
        group("Editing") {
            VStack(alignment: .leading, spacing: 4) {
                small("Find", "magnifyingglass", "edit.findReplace")
                small("Replace", "arrow.left.arrow.right", "edit.findReplace")
                small("Select", "cursorarrow", "select.all")
            }
        }
    }

    static func preview(_ id: String) -> Font {
        switch id {
        case "Title": return .system(size: 20, weight: .light)
        case "Heading1": return .system(size: 15)
        case "Heading2": return .system(size: 13)
        case "Subtitle": return .system(size: 12)
        default: return .system(size: 12)
        }
    }

    static func previewColor(_ id: String) -> Color {
        switch id {
        case "Heading1", "Heading2": return Color(red: 0.1, green: 0.3, blue: 0.45)
        case "Subtitle": return .secondary
        default: return .primary
        }
    }
}
