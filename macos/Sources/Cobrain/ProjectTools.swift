import AppKit
import PDFKit
import SwiftUI

// MARK: Search

/// "Where did I write *derivative*?": searches the text of every document in the project. Each
/// document's text comes from the engine (`document.text`) and is kept until the file changes.
final class ProjectSearch: ObservableObject {
    struct Hit: Identifiable {
        let id = UUID()
        let url: URL
        /// Subject › folder the document is in.
        let place: String
        let count: Int
        let snippets: [AttributedString]
        var name: String { url.deletingPathExtension().lastPathComponent }
    }

    @Published private(set) var hits: [Hit] = []
    @Published private(set) var searching = false
    @Published private(set) var searched = ""

    private let queue = DispatchQueue(label: "cobrain.project-search", qos: .userInitiated)
    /// Read and written on `queue` only.
    private var texts: [URL: (date: Date, text: String)] = [:]
    private var pending: DispatchWorkItem?

    /// Searches `documents` (URL and place) for `query` a moment after the last keystroke.
    func search(_ query: String, in documents: [(url: URL, place: String)]) {
        pending?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { hits = []; searched = ""; searching = false; return }
        searching = true
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            var found: [Hit] = []
            for d in documents {
                guard let text = self.text(of: d.url) else { continue }
                if let hit = Self.hit(q, in: text, url: d.url, place: d.place) { found.append(hit) }
            }
            DispatchQueue.main.async {
                guard self.pending?.isCancelled == false else { return }
                self.hits = found.sorted { $0.count > $1.count }
                self.searched = q
                self.searching = false
            }
        }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func text(of url: URL) -> String? {
        let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date ?? .distantPast
        if let cached = texts[url], cached.date == date { return cached.text }
        guard let e = Engine(path: url.path), case .success(let r) = e.run("document.text"),
              let text = (r as? [String: Any])?["text"] as? String else { return nil }
        texts[url] = (date, text)
        return text
    }

    /// Matches ignore case and accents ("perche" finds "perché"); up to three snippets, the match in bold.
    private static func hit(_ q: String, in text: String, url: URL, place: String) -> Hit? {
        var snippets: [AttributedString] = []
        var count = 0
        var from = text.startIndex
        while let r = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive], range: from..<text.endIndex) {
            count += 1
            if snippets.count < 3 { snippets.append(snippet(text, r)) }
            from = r.upperBound
            if count >= 999 { break }
        }
        return count == 0 ? nil : Hit(url: url, place: place, count: count, snippets: snippets)
    }

    /// The line around `r`, at most ~40 characters either side.
    private static func snippet(_ text: String, _ r: Range<String.Index>) -> AttributedString {
        let lineStart = text[..<r.lowerBound].lastIndex(where: \.isNewline).map { text.index(after: $0) } ?? text.startIndex
        let lineEnd = text[r.upperBound...].firstIndex(where: \.isNewline) ?? text.endIndex
        let start = text.index(r.lowerBound, offsetBy: -40, limitedBy: lineStart) ?? lineStart
        let end = text.index(r.upperBound, offsetBy: 40, limitedBy: lineEnd) ?? lineEnd
        var before = AttributedString((start > lineStart ? "…" : "") + text[start..<r.lowerBound])
        var match = AttributedString(text[r])
        var after = AttributedString(text[r.upperBound..<end] + (end < lineEnd ? "…" : ""))
        before.foregroundColor = .secondary
        after.foregroundColor = .secondary
        match.font = .caption.bold()
        return before + match + after
    }
}

// MARK: Export a subject as one PDF

extension ProjectStore {
    /// The documents under `folder` in the order the pane lists them, with where each one is.
    func documents(in folder: URL) -> [(url: URL, place: String)] {
        func walk(_ items: [ProjectItem]) -> [ProjectItem] {
            items.flatMap { $0.isFolder ? walk($0.children ?? []) : ($0.inCloudOnly ? [] : [$0]) }
        }
        func find(_ items: [ProjectItem]) -> [ProjectItem]? {
            for i in items where i.isFolder {
                if i.url == folder { return i.children ?? [] }
                if let c = find(i.children ?? []) { return c }
            }
            return nil
        }
        let items = folder == current ? tree : (find(tree) ?? [])
        return walk(items).map { ($0.url, place(of: $0.url)) }
    }

    /// "Subject › Folder" for a document, relative to the open project.
    func place(of url: URL) -> String {
        guard let root = current?.standardizedFileURL.pathComponents else { return "" }
        let parts = url.deletingLastPathComponent().standardizedFileURL.pathComponents
        return parts.dropFirst(root.count).joined(separator: " › ")
    }

    /// Renders every document to PDF with the engine and joins them into one file, with a
    /// bookmark per document. Calls `done` on the main queue with an error, or `nil`.
    static func exportPDF(_ documents: [URL], to dest: URL, done: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let joined = PDFDocument()
            let outline = PDFOutline()
            var failed: [String] = []
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cobrain-export-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }
            for (i, url) in documents.enumerated() {
                let pdfURL = tmp.appendingPathComponent("\(i).pdf")
                guard let e = Engine(path: url.path), e.save(to: pdfURL.path), let pdf = PDFDocument(url: pdfURL), pdf.pageCount > 0 else {
                    failed.append(url.lastPathComponent)
                    continue
                }
                let first = joined.pageCount
                for p in 0..<pdf.pageCount {
                    if let page = pdf.page(at: p) { joined.insert(page, at: joined.pageCount) }
                }
                if let page = joined.page(at: first) {
                    let mark = PDFOutline()
                    mark.label = url.deletingPathExtension().lastPathComponent
                    mark.destination = PDFDestination(page: page, at: NSPoint(x: 0, y: page.bounds(for: .mediaBox).maxY))
                    outline.insertChild(mark, at: outline.numberOfChildren)
                }
            }
            joined.outlineRoot = outline
            let ok = joined.pageCount > 0 && joined.write(to: dest)
            DispatchQueue.main.async {
                if !ok { done("Could not create the PDF.") }
                else if !failed.isEmpty { done("The PDF was saved without: \(failed.joined(separator: ", ")).") }
                else { done(nil) }
            }
        }
    }
}

// MARK: Document templates

/// Starting points for a student's documents. The text is Italian on an Italian Mac, else English.
enum DocumentTemplate: String, CaseIterable, Identifiable {
    case blank, lectureNotes, exercises, summary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blank: "Blank"
        case .lectureNotes: "Lecture Notes"
        case .exercises: "Exercises"
        case .summary: "Summary"
        }
    }

    /// Writes the template into the blank document `e` through engine commands.
    func fill(_ e: Engine, title: String, subject: String) {
        guard self != .blank else { return }
        let it = Locale.current.language.languageCode?.identifier == "it"
        func t(_ en: String, _ itText: String) -> String { it ? itText : en }
        var first = true
        func add(_ style: String, _ text: String, bullet: Bool = false) {
            if !first { _ = e.run("text.newParagraph") }
            first = false
            _ = e.run("para.style", ["style": style])
            _ = e.run("para.bullets", bullet ? [:] : ["off": true])
            if !text.isEmpty { _ = e.run("text.insert", ["text": text]) }
        }
        let date = Date().formatted(.dateTime.day().month(.wide).year().locale(it ? Locale(identifier: "it_IT") : .current))
        add("Title", title)
        add("Normal", subject.isEmpty ? date : "\(date) · \(subject)")
        switch self {
        case .lectureNotes:
            add("Heading1", t("Topics", "Argomenti"))
            add("Normal", "…", bullet: true)
            add("Heading1", t("Notes", "Appunti"))
            add("Normal", "…")
            add("Heading1", t("Key ideas", "Concetti chiave"))
            add("Normal", "…", bullet: true)
            add("Heading1", t("Questions to review", "Domande da rivedere"))
            add("Normal", "…", bullet: true)
        case .exercises:
            for n in 1...3 {
                add("Heading1", t("Exercise \(n)", "Esercizio \(n)"))
                add("Normal", t("Problem: …", "Testo: …"))
                add("Normal", t("Solution: …", "Svolgimento: …"))
                add("Normal", t("Result: …", "Risultato: …"))
            }
        case .summary:
            add("Heading1", t("In short", "In breve"))
            add("Normal", "…")
            add("Heading1", t("Main points", "Punti principali"))
            add("Normal", "…", bullet: true)
            add("Heading1", t("Definitions", "Definizioni"))
            add("Normal", "…")
            add("Heading1", t("Formulas and examples", "Formule ed esempi"))
            add("Normal", "…")
            add("Heading1", t("Links to other topics", "Collegamenti con altri argomenti"))
            add("Normal", "…", bullet: true)
        case .blank: break
        }
        _ = e.run("select.all")
        _ = e.run("select.collapse")
    }
}
