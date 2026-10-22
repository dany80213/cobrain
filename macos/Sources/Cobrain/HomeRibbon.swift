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

    /// A 24-pt icon button with WordCraft's own icon; `on` = pressed/active state.
    private func icon(_ name: String, _ id: String, help: String, on: Bool = false, params: [String: Any] = [:]) -> some View {
        Button { model.run(id, params) } label: {
            RibbonIcon(name: name, size: 18).frame(width: 26, height: 24)
                .background(on ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }

    /// An icon with a drop-down arrow that opens a native menu of `(label, command, params)`.
    private func dropdown(_ name: String, help: String, _ items: [(String, String, [String: Any])]) -> some View {
        Button {
            let menu = NSMenu()
            for it in items {
                let mi = NSMenuItem(title: it.0, action: #selector(MenuTarget.fire), keyEquivalent: "")
                let t = MenuTarget { model.run(it.1, it.2) }
                mi.target = t; mi.representedObject = t
                menu.addItem(mi)
            }
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        } label: {
            HStack(spacing: 1) { RibbonIcon(name: name, size: 18); Text("▾").font(.system(size: 8)) }
                .frame(height: 24).padding(.horizontal, 3).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }

    /// A colour drop-down (theme grid) that runs `cmd` with `{"color": hex}`.
    private func colorDropdown(_ name: String, help: String, cmd: String) -> some View {
        Button {
            let menu = NSMenu()
            menu.addItem(MenuWidget.item(ColorGridView(theme: model.themeColors, pick: { hex in
                MenuWidget.close(); model.run(cmd, ["color": hex])
            }, more: {
                MenuWidget.close(); ColorPanelTarget.show { hex in model.run(cmd, ["color": hex]) }
            })))
            MenuWidget.active = menu
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        } label: {
            HStack(spacing: 1) { RibbonIcon(name: name, size: 18); Text("▾").font(.system(size: 8)) }
                .frame(height: 24).padding(.horizontal, 3).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }

    private func small(_ title: String, _ name: String, _ id: String) -> some View {
        Button { model.run(id) } label: {
            HStack(spacing: 6) { RibbonIcon(name: name, size: 18); Text(title).font(.system(size: 12)) }
                .frame(width: 76, alignment: .leading).padding(.vertical, 2).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var sepV: some View { Divider().frame(height: 16).padding(.horizontal, 2) }

    private var clipboard: some View {
        group("Clipboard") {
            HStack(alignment: .top, spacing: 6) {
                Button { model.paste() } label: {
                    VStack(spacing: 3) { RibbonIcon(name: "paste", size: 32); Text("Paste ▾").font(.system(size: 12)) }
                        .frame(width: 52).contentShape(Rectangle())
                }.buttonStyle(.plain).help("Paste (⌘V)")
                VStack(alignment: .leading, spacing: 2) {
                    small("Cut", "cut", "edit.cut")
                    small("Copy", "copy", "edit.copy")
                    small("Format", "painter", "edit.formatPainter")
                }
            }
        }
    }

    private var font: some View {
        group("Font") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 3) {
                    TextField("Font", text: $fontName).textFieldStyle(.roundedBorder).frame(width: 150)
                        .onSubmit { model.run("format.font", ["name": fontName]) }
                    TextField("Size", text: $fontSize).textFieldStyle(.roundedBorder).frame(width: 46)
                        .onSubmit { if let v = Double(fontSize) { model.run("format.size", ["size": v]) } }
                    icon("grow", "format.growFont", help: "Increase Font Size")
                    icon("shrink", "format.shrinkFont", help: "Decrease Font Size")
                    dropdown("case", help: "Change Case", [("Sentence case.", "format.changeCase", ["mode": "sentence"]),
                                                          ("lowercase", "format.changeCase", ["mode": "lower"]),
                                                          ("UPPERCASE", "format.changeCase", ["mode": "upper"]),
                                                          ("Capitalize Each Word", "format.changeCase", ["mode": "title"]),
                                                          ("tOGGLE cASE", "format.changeCase", ["mode": "toggle"])])
                    icon("clear", "format.clear", help: "Clear All Formatting")
                    icon("phonetic", "format.phonetic", help: "Phonetic Guide")
                }
                HStack(spacing: 1) {
                    icon("bold", "format.bold", help: "Bold (⌘B)", on: model.isOn("bold"))
                    icon("italic", "format.italic", help: "Italic (⌘I)", on: model.isOn("italic"))
                    icon("underline", "format.underline", help: "Underline (⌘U)", on: model.isOn("underline"))
                    icon("strike", "format.strikethrough", help: "Strikethrough", on: model.isOn("strike"))
                    icon("subscript", "format.subscript", help: "Subscript", on: model.isOn("subscript"))
                    icon("superscript", "format.superscript", help: "Superscript", on: model.isOn("superscript"))
                    icon("charborder", "format.border", help: "Character Border", on: model.isOn("border"))
                    icon("enclose", "format.enclose", help: "Enclose Characters")
                    sepV
                    icon("highlight", "format.highlight", help: "Text Highlight Color", params: ["color": "yellow"])
                    colorDropdown("fontcolor", help: "Font Color", cmd: "format.color")
                }
            }
        }
    }

    private var paragraph: some View {
        group("Paragraph") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 1) {
                    icon("bullets", "para.bullets", help: "Bullets")
                    icon("numbering", "para.numbering", help: "Numbering")
                    icon("multilevel", "para.multilevel", help: "Multilevel List")
                    sepV
                    icon("outdent", "para.outdent", help: "Decrease Indent")
                    icon("indent", "para.indent", help: "Increase Indent")
                    sepV
                    icon("sort", "para.sort", help: "Sort")
                    icon("pilcrow", "view.marks", help: "Show/Hide ¶")
                }
                HStack(spacing: 1) {
                    icon("alignLeft", "para.alignLeft", help: "Align Left")
                    icon("alignCenter", "para.alignCenter", help: "Center")
                    icon("alignRight", "para.alignRight", help: "Align Right")
                    icon("justify", "para.justify", help: "Justify")
                    sepV
                    icon("textLtr", "para.ltr", help: "Left-to-Right Text Direction")
                    icon("textRtl", "para.rtl", help: "Right-to-Left Text Direction")
                    sepV
                    dropdown("lineSpacing", help: "Line and Paragraph Spacing", [("1.0", "para.single", [:]), ("1.5", "para.oneAndHalf", [:]), ("2.0", "para.double", [:]),
                                                                              ("Add Space Before Paragraph", "para.addSpaceBefore", [:]),
                                                                              ("Remove Space After Paragraph", "para.removeSpaceAfter", [:])])
                    colorDropdown("shading", help: "Shading", cmd: "para.shading")
                    icon("borders", "para.borders", help: "Borders", params: ["kind": "bottom"])
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
        HStack(alignment: .top, spacing: 0) {
            group("Editing") {
                VStack(alignment: .leading, spacing: 2) {
                    small("Find", "find", "edit.findReplace")
                    small("Replace", "replace", "edit.findReplace")
                    small("Select", "select", "select.all")
                }
            }
            sep
            group("Voice") { bigButton("Dictate", "dictate", "tools.dictate") }
            sep
            group("Editor") { bigButton("Editor", "editor", "review.spelling") }
        }
    }

    private func bigButton(_ title: String, _ name: String, _ id: String) -> some View {
        Button { model.run(id) } label: {
            VStack(spacing: 3) { RibbonIcon(name: name, size: 32); Text(title).font(.system(size: 12)) }
                .frame(minWidth: 50).contentShape(Rectangle())
        }.buttonStyle(.plain)
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
