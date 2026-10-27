import AppKit

/// The list styles of Pages' Bullets & Lists menu, each one a nine-level `list.define`
/// definition. The engine has no picture bullets, so Image uses a coloured dot.
enum ListStyle: String, CaseIterable, Identifiable {
    case bullet, image, lettered, numbered, harvard, dashed, noteTaking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bullet: "Bullet"
        case .image: "Image"
        case .lettered: "Lettered"
        case .numbered: "Numbered"
        case .harvard: "Harvard"
        case .dashed: "Dashed"
        case .noteTaking: "Note Taking"
        }
    }

    /// What the first level's marker looks like, for the menu.
    var marker: String {
        switch self {
        case .bullet, .noteTaking: "•"
        case .image: "●"
        case .lettered: "A."
        case .numbered: "1."
        case .harvard: "I."
        case .dashed: "–"
        }
    }

    /// Note Taking is the compact one; the others step in by a quarter inch per level.
    private var step: Double { self == .noteTaking ? 14 : 18 }

    /// `list.define`'s `levels`: format and text per level, and where number and text sit.
    var levels: [[String: Any]] {
        (0..<9).map { i in
            let n = i + 1
            let (format, text): (String, String)
            var color: Any = NSNull()
            switch self {
            case .bullet: (format, text) = ("bullet", "•")
            case .image: (format, text) = ("bullet", "●"); color = "0A84FF"
            case .dashed: (format, text) = ("bullet", "–")
            case .noteTaking: (format, text) = ("bullet", ["•", "–", "○"][i % 3])
            case .numbered: (format, text) = ("decimal", "%\(n).")
            case .lettered: (format, text) = (["upperLetter", "lowerLetter", "lowerRoman"][i % 3], "%\(n).")
            case .harvard:
                let formats = ["upperRoman", "upperLetter", "decimal", "lowerLetter", "decimal", "lowerLetter", "lowerRoman", "lowerLetter", "lowerRoman"]
                format = formats[i]
                text = (4...5).contains(i) ? "(%\(n))" : "%\(n)."
            }
            // The engine's own bullets use Arial for • and ○ (what Word expects); other markers
            // follow the paragraph's font.
            let font: Any = ["•", "○"].contains(text) ? "Arial" : NSNull()
            return ["format": format, "text": text, "font": font, "color": color, "bold": false,
                    "alignedAt": Double(i) * step, "indentAt": Double(i + 1) * step, "follow": "tab"]
        }
    }

    /// The menu row: the marker in its own column, then the name.
    var menuTitle: NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.tabStops = [NSTextTab(textAlignment: .left, location: 28)]
        let s = NSMutableAttributedString(string: "\(marker)\t\(title)", attributes: [.paragraphStyle: para, .font: NSFont.menuFont(ofSize: 0)])
        if self == .image { s.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: NSRange(location: 0, length: 1)) }
        return s
    }
}

extension ListStyle {
    /// App-side command id the folded ribbon menu runs (`{"style": rawValue | "none"}`).
    static let command = "cobrain.list"

    /// The same choices as a "Lists" submenu, for when the Paragraph group is folded.
    static var menuNode: SpecNode {
        func item(_ label: String, _ style: String) -> SpecNode {
            var n = SpecNode(t: "item")
            n.label = label
            n.cmd = command
            n.params = "{\"style\": \"\(style)\"}"
            return n
        }
        var node = SpecNode(t: "menu", items: [item("None", "none"), SpecNode(t: "sep")] + allCases.map { item("\($0.marker)  \($0.title)", $0.rawValue) })
        node.label = "Lists"
        return node
    }
}
