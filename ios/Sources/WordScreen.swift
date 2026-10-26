import SwiftUI
import UIKit

/// A word document on iPad: pages in the middle, a touch-sized formatting bar on top.
struct WordScreen: View {
    let url: URL
    @ObservedObject var library: Library
    @StateObject private var holder = DocHolder()
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if let doc = holder.doc { DocumentBody(doc: doc) } else { ProgressView().task { holder.load(url) } }
        }
        .navigationTitle(url.deletingPathExtension().lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: phase) { _, p in if p != .active { holder.doc?.saveNow() } }
        .onDisappear { holder.doc?.saveNow(); library.reload() }
    }
}

final class DocHolder: ObservableObject {
    @Published var doc: PadDocument?
    func load(_ url: URL) { if doc == nil { doc = PadDocument(url: url) } }
}

struct DocumentBody: View {
    @ObservedObject var doc: PadDocument

    var body: some View {
        VStack(spacing: 0) {
            FormatBar(doc: doc)
            Divider()
            PagesScroll(doc: doc)
            Divider()
            HStack(spacing: 14) {
                Text("Page \((doc.caret?.page ?? 0) + 1) of \(doc.pageCount)")
                Text("\(doc.wordCount) words")
                if let e = doc.lastError { Text(e).foregroundStyle(.red) }
                Spacer()
                Button { doc.zoom = max(0.5, doc.zoom - 0.1) } label: { Image(systemName: "minus") }
                Text("\(Int((doc.zoom * 100).rounded()))%").monospacedDigit().frame(width: 46)
                Button { doc.zoom = min(3, doc.zoom + 0.1) } label: { Image(systemName: "plus") }
            }
            .font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { doc.run("edit.undo") } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!doc.isEnabled("edit.undo"))
                Button { doc.run("edit.redo") } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!doc.isEnabled("edit.redo"))
                Button { doc.keyboardWanted.toggle() } label: { Image(systemName: doc.keyboardWanted ? "keyboard.chevron.compact.down" : "keyboard") }
                if let pdf = doc.pdfURL() { ShareLink(item: pdf) { Image(systemName: "square.and.arrow.up") } }
            }
        }
    }
}

// MARK: Formatting bar

struct FormatBar: View {
    @ObservedObject var doc: PadDocument
    private let colors = ["000000", "C00000", "ED7D31", "FFC000", "00B050", "0070C0", "7030A0", "7F7F7F"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                stylesMenu
                group {
                    iconButton("shrink", "format.shrinkFont", "Smaller")
                    Text("\(Int((doc.format["size"] as? Double) ?? 11))").font(.system(size: 14).monospacedDigit()).frame(width: 30)
                    iconButton("grow", "format.growFont", "Larger")
                }
                group {
                    toggle("bold", "format.bold", "Bold"); toggle("italic", "format.italic", "Italic")
                    toggle("underline", "format.underline", "Underline"); toggle("strike", "format.strikethrough", "Strikethrough")
                }
                group {
                    Menu {
                        ForEach(colors, id: \.self) { c in Button { doc.run("format.color", ["color": c]) } label: { Label(c, systemImage: "circle.fill") }.tint(Color(hex: c)) }
                        Button("Automatic") { doc.run("format.color", ["color": "auto"]) }
                    } label: { cell { RibbonIcon(name: "fontcolor") } }
                    Menu {
                        ForEach(["yellow", "brightGreen", "turquoise", "pink", "none"], id: \.self) { c in Button(c) { doc.run("format.highlight", ["color": c]) } }
                    } label: { cell { RibbonIcon(name: "highlight") } }
                }
                group {
                    iconButton("bullets", "para.bullets", "Bullets"); iconButton("numbering", "para.numbering", "Numbering")
                    iconButton("outdent", "para.outdent", "Decrease indent"); iconButton("indent", "para.indent", "Increase indent")
                }
                group {
                    iconButton("alignLeft", "para.alignLeft", "Left"); iconButton("alignCenter", "para.alignCenter", "Center")
                    iconButton("alignRight", "para.alignRight", "Right"); iconButton("justify", "para.justify", "Justify")
                }
                group {
                    Menu {
                        Button("Table 3 × 3") { doc.run("insert.table", ["rows": 3, "cols": 3]) }
                        Button("Table 4 × 4") { doc.run("insert.table", ["rows": 4, "cols": 4]) }
                        Button("Page Break") { doc.run("insert.pageBreak") }
                    } label: { cell { RibbonIcon(name: "table") } }
                    Button { doc.paste() } label: { cell { RibbonIcon(name: "paste") } }
                    iconButton("copy", "edit.copy", "Copy"); iconButton("cut", "edit.cut", "Cut")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .background(Color(.secondarySystemBackground))
    }

    private var stylesMenu: some View {
        Menu {
            ForEach(doc.styles, id: \.id) { s in Button(s.name) { doc.run("para.style", ["style": s.id]) } }
        } label: {
            HStack(spacing: 4) { Text(styleName).font(.system(size: 14)).lineLimit(1); Image(systemName: "chevron.down").font(.system(size: 10)) }
                .frame(width: 130, height: 40).background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
        }
    }

    private var styleName: String {
        let id = doc.format["style"] as? String
        return doc.styles.first { $0.id == id }?.name ?? "Normal"
    }

    private func group<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 2) { content() }
            .padding(.horizontal, 4).background(Color(.systemBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    private func cell<C: View>(@ViewBuilder _ icon: () -> C, on: Bool = false) -> some View {
        icon().frame(width: 44, height: 40).background(on ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
    }

    private func iconButton(_ icon: String, _ cmd: String, _ label: String) -> some View {
        Button { doc.run(cmd) } label: { cell { RibbonIcon(name: icon) } }.disabled(!doc.isEnabled(cmd)).accessibilityLabel(label)
    }

    private func toggle(_ icon: String, _ cmd: String, _ label: String) -> some View {
        Button { doc.run(cmd) } label: { cell({ RibbonIcon(name: icon) }, on: doc.isPressed(cmd)) }.accessibilityLabel(label)
    }
}

extension Color {
    init(hex: String) {
        let v = UInt32(hex, radix: 16) ?? 0
        self.init(.sRGB, red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}

// MARK: Pages

struct PagesScroll: View {
    @ObservedObject var doc: PadDocument
    @State private var baseZoom: CGFloat?

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(spacing: 16) {
                ForEach(0..<max(doc.pageCount, 1), id: \.self) { i in PageView(doc: doc, index: i) }
            }
            .padding(.vertical, 16).padding(.horizontal, 16)
            .frame(minWidth: 0)
        }
        .background(Color(.systemGray5))
        .scrollDismissesKeyboard(.interactively)
        .gesture(MagnifyGesture().onChanged { v in
            let b = baseZoom ?? doc.zoom
            baseZoom = b
            doc.zoom = max(0.5, min(3, b * v.magnification))
        }.onEnded { _ in baseZoom = nil })
        .background(KeyboardCatcher(doc: doc).frame(width: 0, height: 0))
    }
}

struct PageView: View {
    @ObservedObject var doc: PadDocument
    let index: Int
    @State private var image: UIImage?
    @State private var imageKey = ""
    @State private var caretOn = true
    private let blink = Timer.publish(every: 0.55, on: .main, in: .common).autoconnect()

    var body: some View {
        let size = doc.engine.pageSize(index) ?? Engine.Page(width: 612, height: 792)
        let z = doc.zoom
        ZStack(alignment: .topLeading) {
            Color.white
            if let image { Image(uiImage: image).resizable().frame(width: size.width * z, height: size.height * z) }
            ForEach(Array(doc.marks.find.enumerated()), id: \.offset) { _, r in mark(r, z, Color.yellow.opacity(0.45)) }
            ForEach(Array(doc.marks.selection.enumerated()), id: \.offset) { _, r in mark(r, z, Color.accentColor.opacity(0.3)) }
            if let c = doc.caret, c.page == index, caretOn, doc.marks.selection.isEmpty {
                Rectangle().fill(Color.black).frame(width: 1.5, height: c.height * z).offset(x: c.x * z, y: c.top * z)
            }
        }
        .frame(width: size.width * z, height: size.height * z)
        .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { location in
            doc.click(page: index, x: location.x / z, y: location.y / z)
            doc.run("select.word"); doc.keyboardWanted = true
        }
        .onTapGesture { location in
            caretOn = true
            doc.click(page: index, x: location.x / z, y: location.y / z)
            doc.keyboardWanted = true
        }
        .gesture(
            // Touch and hold, then drag, to select: a plain drag scrolls.
            LongPressGesture(minimumDuration: 0.25).sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { v in
                    if case .second(true, let drag?) = v {
                        if drag.translation == .zero { doc.click(page: index, x: drag.startLocation.x / z, y: drag.startLocation.y / z) }
                        else { doc.click(page: index, x: drag.location.x / z, y: drag.location.y / z, extend: true) }
                    }
                }
        )
        .onReceive(blink) { _ in caretOn.toggle() }
        .task(id: "\(doc.revision)-\(doc.zoom)") { render(size) }
    }

    private func mark(_ r: [Double], _ z: CGFloat, _ color: Color) -> some View {
        Group {
            if r.count == 5, Int(r[0]) == index {
                Rectangle().fill(color).frame(width: r[3] * z, height: r[4] * z).offset(x: r[1] * z, y: r[2] * z)
            }
        }
    }

    private func render(_ size: Engine.Page) {
        let scale = UITraitCollection.current.displayScale * doc.zoom
        let key = "\(doc.revision)-\(scale)"
        guard key != imageKey, let cg = doc.engine.renderPage(index, scale: scale) else { return }
        image = UIImage(cgImage: cg)
        imageKey = key
    }
}

// MARK: Keyboard

/// An invisible responder that takes typing from the on-screen or hardware keyboard and turns it into engine commands.
struct KeyboardCatcher: UIViewRepresentable {
    @ObservedObject var doc: PadDocument

    func makeUIView(context: Context) -> KeyView { let v = KeyView(); v.doc = doc; return v }

    func updateUIView(_ v: KeyView, context: Context) {
        v.doc = doc
        DispatchQueue.main.async {
            if doc.keyboardWanted { if !v.isFirstResponder { v.becomeFirstResponder() } }
            else if v.isFirstResponder { v.resignFirstResponder() }
        }
    }

    final class KeyView: UIView, UIKeyInput {
        weak var doc: PadDocument?
        override var canBecomeFirstResponder: Bool { true }
        var hasText: Bool { true }
        var autocorrectionType: UITextAutocorrectionType = .no
        var autocapitalizationType: UITextAutocapitalizationType = .none
        var spellCheckingType: UITextSpellCheckingType = .no

        func insertText(_ text: String) {
            if text == "\n" { doc?.run("text.newParagraph") } else if text == "\t" { doc?.run("text.tab") } else { doc?.run("text.insert", ["text": text]) }
        }
        func deleteBackward() { doc?.run("text.backspace") }

        override var keyCommands: [UIKeyCommand]? {
            var list: [UIKeyCommand] = []
            let arrows: [(String, String)] = [(UIKeyCommand.inputLeftArrow, "caret.left"), (UIKeyCommand.inputRightArrow, "caret.right"),
                                              (UIKeyCommand.inputUpArrow, "caret.up"), (UIKeyCommand.inputDownArrow, "caret.down")]
            for (input, _) in arrows {
                for mods: UIKeyModifierFlags in [[], .shift, .alternate, [.alternate, .shift], .command, [.command, .shift]] {
                    let k = UIKeyCommand(input: input, modifierFlags: mods, action: #selector(arrow(_:)))
                    k.wantsPriorityOverSystemBehavior = true
                    list.append(k)
                }
            }
            for ch in "abcdefghijklmnopqrstuvwxyz" {
                for mods: UIKeyModifierFlags in [.command, [.command, .shift]] {
                    let k = UIKeyCommand(input: String(ch), modifierFlags: mods, action: #selector(shortcut(_:)))
                    k.wantsPriorityOverSystemBehavior = true
                    list.append(k)
                }
            }
            return list
        }

        @objc private func arrow(_ k: UIKeyCommand) {
            guard let input = k.input else { return }
            let extend = k.modifierFlags.contains(.shift)
            let word = k.modifierFlags.contains(.alternate), line = k.modifierFlags.contains(.command)
            let id: String
            switch input {
            case UIKeyCommand.inputLeftArrow: id = line ? "caret.home" : word ? "caret.wordLeft" : "caret.left"
            case UIKeyCommand.inputRightArrow: id = line ? "caret.end" : word ? "caret.wordRight" : "caret.right"
            case UIKeyCommand.inputUpArrow: id = line ? "caret.docStart" : "caret.up"
            default: id = line ? "caret.docEnd" : "caret.down"
            }
            doc?.run(id, extend ? ["extend": true] : [:])
        }

        /// ⌘ shortcuts come from the engine's registry (`Mod+B` …), so they match the Mac app.
        @objc private func shortcut(_ k: UIKeyCommand) {
            guard let doc, let input = k.input else { return }
            let name = (k.modifierFlags.contains(.shift) ? "Mod+Shift+" : "Mod+") + input.uppercased()
            switch name {
            case "Mod+V": doc.paste()
            case "Mod+S": doc.saveNow()
            default: if let id = doc.engine.command(forShortcut: name) { doc.run(id) }
            }
        }
    }
}
