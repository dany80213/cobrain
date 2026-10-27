import SwiftUI

// Subjects ("materie") shown as school notebooks. Shared by the Mac and iPad apps.
// A subject is a folder; its look (colour, cover pattern, symbol) is kept in a small hidden file inside it,
// so it travels with the folder through iCloud and shows up the same on every device.

enum NotebookPattern: String, Codable, CaseIterable, Identifiable {
    case plain, dots, grid, stripes
    var id: String { rawValue }
    var title: String {
        switch self { case .plain: "Plain"; case .dots: "Dots"; case .grid: "Squares"; case .stripes: "Stripes" }
    }
}

struct SubjectStyle: Codable, Equatable, Hashable {
    var color = "7C6CF0"
    var pattern: NotebookPattern = .plain
    var symbol = "book.closed"

    static let fileName = ".cobrain-subject.json"
    static let colors = ["7C6CF0", "4C9AFF", "2EB5A0", "36B37E", "F2B01E", "F2763D", "E5484D", "F06CAB", "8D6E63", "5B6B7A"]
    static let symbols = ["book.closed", "x.squareroot", "function", "globe.europe.africa", "atom", "flask", "leaf", "building.columns", "paintpalette",
                          "music.note", "figure.run", "laptopcomputer", "pencil.and.ruler", "map", "text.book.closed", "theatermasks", "camera", "heart.text.square"]

    static func load(from folder: URL) -> SubjectStyle {
        if let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)), let s = try? JSONDecoder().decode(SubjectStyle.self, from: data) { return s }
        return guess(for: folder.lastPathComponent)
    }

    func save(to folder: URL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) { try? data.write(to: folder.appendingPathComponent(Self.fileName), options: .atomic) }
    }

    /// A first look from the name (Italian and English): "Matematica" gets a maths symbol, and the colour varies by name.
    static func guess(for name: String) -> SubjectStyle {
        let n = name.lowercased()
        let table: [(keys: [String], symbol: String)] = [
            (["mat", "math", "alge", "geometr", "calcol"], "x.squareroot"), (["ital", "letter", "liter", "lingua", "latin", "grec"], "text.book.closed"),
            (["stor", "hist"], "building.columns"), (["ingl", "engl", "franc", "french", "spagn", "spanish", "tedesc", "german"], "globe.europe.africa"),
            (["chim", "chem", "scien", "biolog"], "flask"), (["art", "dise", "draw", "pittur"], "paintpalette"),
            (["music"], "music.note"), (["ginn", "sport", "motor", "gym", "educazione fisica"], "figure.run"), (["fis", "phys"], "atom"), (["info", "comp", "program", "tecnol", "tech"], "laptopcomputer"),
            (["geo"], "map"), (["filos", "philos", "relig", "civica"], "theatermasks"), (["natur", "ambient", "agrar"], "leaf"),
        ]
        let symbol = table.first { $0.keys.contains { n.contains($0) } }?.symbol ?? "book.closed"
        let h = n.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        let patterns = NotebookPattern.allCases
        return SubjectStyle(color: colors[abs(h) % colors.count], pattern: patterns[abs(h / 7) % patterns.count], symbol: symbol)
    }
}

extension Color {
    /// `RRGGBB` → colour, and a lighter / darker shade of it.
    init(nb hex: String) {
        let v = UInt32(hex, radix: 16) ?? 0
        self.init(.sRGB, red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }

    static func nbShade(_ hex: String, _ f: Double) -> Color {
        let v = UInt32(hex, radix: 16) ?? 0
        func c(_ shift: UInt32) -> Double {
            let x = Double((v >> shift) & 255) / 255
            return max(0, min(1, f >= 0 ? x + (1 - x) * f : x * (1 + f)))
        }
        return Color(.sRGB, red: c(16), green: c(8), blue: c(0))
    }
}

/// A school notebook: coloured cover with a pattern, stitched spine, elastic band, a label with the subject's name,
/// and pages showing at the edge. `count` is the number of documents inside.
struct NotebookCover: View {
    let name: String
    let style: SubjectStyle
    var count: Int?
    var width: CGFloat = 150

    var body: some View {
        let w = width, h = width * 1.34
        let base = style.color
        ZStack(alignment: .topLeading) {
            // Pages peeking out at the right and bottom.
            RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.96))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.12), lineWidth: 0.5))
                .frame(width: w - 3, height: h - 3).offset(x: 5, y: 5)
            RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.9)).frame(width: w - 3, height: h - 3).offset(x: 3, y: 3)
            cover(w, h, base)
        }
        .frame(width: w + 6, height: h + 6, alignment: .topLeading)
        .shadow(color: .black.opacity(0.22), radius: 6, x: 2, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }

    private func cover(_ w: CGFloat, _ h: CGFloat, _ base: String) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 10, topTrailingRadius: 10)
        let spine = w * 0.11
        return ZStack(alignment: .topLeading) {
            shape.fill(LinearGradient(colors: [Color.nbShade(base, 0.10), Color.nbShade(base, -0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
            patternLayer(w, h).clipShape(shape)
            // Spine with stitching.
            UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 0, topTrailingRadius: 0)
                .fill(Color.nbShade(base, -0.28)).frame(width: spine, height: h)
            Path { p in p.move(to: CGPoint(x: spine * 0.5, y: 10)); p.addLine(to: CGPoint(x: spine * 0.5, y: h - 10)) }
                .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            Rectangle().fill(Color.black.opacity(0.18)).frame(width: 1, height: h).offset(x: spine)
            // Elastic band.
            Rectangle().fill(Color.nbShade(base, -0.35)).frame(width: w * 0.045, height: h).offset(x: w * 0.80)
            // Label.
            VStack(spacing: 2) {
                Text(name).font(.system(size: max(11, w * 0.105), weight: .semibold, design: .rounded)).lineLimit(2).multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6).foregroundStyle(Color(white: 0.12))
                if let count { Text(count == 1 ? "1 file" : "\(count) files").font(.system(size: max(9, w * 0.07))).foregroundStyle(Color(white: 0.4)) }
            }
            .padding(.horizontal, 8).padding(.vertical, 7).frame(width: w * 0.62)
            .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.15), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
            .offset(x: spine + (w - spine) * 0.5 - w * 0.31 - w * 0.02, y: h * 0.16)
            // Subject symbol.
            Image(systemName: style.symbol).font(.system(size: w * 0.26, weight: .regular)).foregroundStyle(Color.white.opacity(0.55))
                .frame(width: w - spine).offset(x: spine, y: h * 0.62)
        }
        .frame(width: w, height: h)
        .overlay(shape.stroke(Color.black.opacity(0.18), lineWidth: 0.6))
    }

    @ViewBuilder private func patternLayer(_ w: CGFloat, _ h: CGFloat) -> some View {
        let ink = Color.white.opacity(0.22)
        switch style.pattern {
        case .plain: Color.clear
        case .dots:
            Canvas { ctx, size in
                var p = Path()
                for x in stride(from: 12.0, to: size.width, by: 14) { for y in stride(from: 12.0, to: size.height, by: 14) { p.addEllipse(in: CGRect(x: x, y: y, width: 2.4, height: 2.4)) } }
                ctx.fill(p, with: .color(ink))
            }
        case .grid:
            Canvas { ctx, size in
                var p = Path()
                for x in stride(from: 10.0, to: size.width, by: 14) { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }
                for y in stride(from: 10.0, to: size.height, by: 14) { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }
                ctx.stroke(p, with: .color(ink), lineWidth: 0.7)
            }
        case .stripes:
            Canvas { ctx, size in
                var p = Path()
                for y in stride(from: 8.0, to: size.height, by: 18) { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }
                ctx.stroke(p, with: .color(ink), lineWidth: 5)
            }
        }
    }
}

/// A dashed "add a subject" notebook outline.
struct NewNotebookTile: View {
    var width: CGFloat = 150
    var body: some View {
        RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .frame(width: width, height: width * 1.34)
            .overlay(VStack(spacing: 6) { Image(systemName: "plus").font(.system(size: 28, weight: .light)); Text("New subject").font(.system(size: 13)) }.foregroundStyle(.secondary))
            .padding(.trailing, 6).padding(.bottom, 6)
    }
}

/// Create or restyle a subject: name, cover colour, pattern and symbol, with a live preview.
struct SubjectEditor: View {
    let isNew: Bool
    @State var name: String
    @State var style: SubjectStyle
    let onSave: (String, SubjectStyle) -> Void
    let onCancel: () -> Void
    @State private var touchedLook = false

    init(isNew: Bool, name: String, style: SubjectStyle, onSave: @escaping (String, SubjectStyle) -> Void, onCancel: @escaping () -> Void) {
        self.isNew = isNew; self._name = State(initialValue: name); self._style = State(initialValue: style); self.onSave = onSave; self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 18) {
            Text(isNew ? "New subject" : "Customize notebook").font(.title2.weight(.semibold))
            NotebookCover(name: name.isEmpty ? "Subject" : name, style: style, width: 130)
            TextField("Name (e.g. Mathematics)", text: $name).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                .onChange(of: name) { _, v in if isNew && !touchedLook { style = SubjectStyle.guess(for: v) } }
            HStack(spacing: 8) {
                ForEach(SubjectStyle.colors, id: \.self) { c in
                    Button { style.color = c; touchedLook = true } label: {
                        Circle().fill(Color(nb: c)).frame(width: 28, height: 28)
                            .overlay(Circle().stroke(Color.primary, lineWidth: style.color == c ? 2.5 : 0).padding(-3))
                    }.buttonStyle(.plain)
                }
            }
            Picker("Cover", selection: Binding(get: { style.pattern }, set: { style.pattern = $0; touchedLook = true })) {
                ForEach(NotebookPattern.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).frame(maxWidth: 320)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 6), count: 9), spacing: 6) {
                ForEach(SubjectStyle.symbols, id: \.self) { s in
                    Button { style.symbol = s; touchedLook = true } label: {
                        Image(systemName: s).font(.system(size: 17)).frame(width: 38, height: 34)
                            .background(style.symbol == s ? Color.accentColor.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                }
            }
            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save") { onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), style) }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(minWidth: 380)
    }
}

