import ImageIO
import SwiftUI

// Templates for documents and whiteboards, shared by the Mac and iPad apps.
// Built-in ones are written in code (document text goes through the engine's own commands, whiteboards are lists of
// shapes). Your own are ordinary files kept in the project, in `.cobrain-templates/`, for every subject or for one:
//   <project>/.cobrain-templates/_all/<name>.docx            (every subject)
//   <project>/.cobrain-templates/<Subject>/<name>.docx       (that subject only)
// so they travel with the project through iCloud, like the notebooks do.

/// What a subject is about, guessed from its name (Italian and English).
enum SubjectKind: String, CaseIterable {
    case math, italian, history, english, science, art, music, sport, computing, geography, philosophy

    static let keywords: [(SubjectKind, [String])] = [
        (.sport, ["ginn", "sport", "motor", "gym", "educazione fisica", "physical ed"]),
        (.math, ["mat", "math", "alge", "geometr", "calcol", "statist"]),
        (.italian, ["ital", "letter", "liter", "lingua", "latin", "grec"]),
        (.history, ["stor", "hist"]),
        (.english, ["ingl", "engl", "franc", "french", "spagn", "spanish", "tedesc", "german"]),
        (.science, ["fis", "phys", "chim", "chem", "scien", "biolog", "natur"]),
        (.art, ["art", "dise", "draw", "pittur"]),
        (.music, ["music"]),
        (.computing, ["info", "comp", "program", "tecnol", "tech", "sistemi"]),
        (.geography, ["geo"]),
        (.philosophy, ["filos", "philos", "relig", "civica", "etica"]),
    ]

    static func of(_ name: String) -> SubjectKind? {
        let n = name.lowercased()
        return keywords.first { $0.1.contains { n.contains($0) } }?.0
    }

    var symbol: String {
        switch self {
        case .math: "x.squareroot"; case .italian: "text.book.closed"; case .history: "building.columns"; case .english: "globe.europe.africa"
        case .science: "atom"; case .art: "paintpalette"; case .music: "music.note"; case .sport: "figure.run"
        case .computing: "laptopcomputer"; case .geography: "map"; case .philosophy: "theatermasks"
        }
    }
}

// MARK: Template model

/// One block of a document template. `{title}`, `{date}` and `{subject}` in the text are filled in when the file is made.
enum TBlock {
    case title(String), subtitle(String), h1(String), h2(String), text(String), bullet(String)
    case table([[String]])
}

struct CobrainTemplate: Identifiable {
    enum Source {
        case document([TBlock])
        case board(() -> [BoardElement])
        case file(URL)
    }
    var id: String
    var title: String
    var detail: String
    var symbol: String
    /// The kind of subject it is for; nil: any subject.
    var kind: SubjectKind?
    /// A template of yours kept for one subject (its folder name); nil: every subject.
    var scope: String?
    var source: Source

    var isBoard: Bool {
        switch source {
        case .board: true
        case .document: false
        case .file(let u): u.pathExtension.lowercased() == "cobrainboard"
        }
    }
    var isMine: Bool { if case .file = source { true } else { false } }
    var fileExtension: String { isBoard ? "cobrainboard" : "docx" }
}

/// Italian on an Italian device, English otherwise.
private let isItalian = Locale.current.language.languageCode?.identifier == "it"
private func L(_ en: String, _ it: String) -> String { isItalian ? it : en }

// MARK: Built-in templates

enum TemplateCatalog {
    static var builtin: [CobrainTemplate] { documents + boards }

    private static func doc(_ id: String, _ title: String, _ detail: String, _ symbol: String, _ kind: SubjectKind? = nil, _ blocks: [TBlock]) -> CobrainTemplate {
        CobrainTemplate(id: id, title: title, detail: detail, symbol: symbol, kind: kind, scope: nil, source: .document(blocks))
    }

    private static func board(_ id: String, _ title: String, _ detail: String, _ symbol: String, _ kind: SubjectKind? = nil, _ make: @escaping () -> [BoardElement]) -> CobrainTemplate {
        CobrainTemplate(id: id, title: title, detail: detail, symbol: symbol, kind: kind, scope: nil, source: .board(make))
    }

    static var documents: [CobrainTemplate] {[
        // For every subject
        doc("blank", L("Blank document", "Documento vuoto"), L("An empty page", "Una pagina vuota"), "doc", nil, []),
        doc("lecture", L("Lecture notes", "Appunti di lezione"), L("Topics, notes, key ideas, questions", "Argomenti, appunti, concetti chiave, domande"), "text.book.closed", nil, [
            .title("{title}"), .text("{date} · {subject}"),
            .h1(L("Topics", "Argomenti")), .bullet("…"),
            .h1(L("Notes", "Appunti")), .text("…"),
            .h1(L("Key ideas", "Concetti chiave")), .bullet("…"),
            .h1(L("Questions to review", "Domande da rivedere")), .bullet("…"),
        ]),
        doc("cornell", L("Cornell notes", "Appunti Cornell"), L("Cues on the left, notes on the right, summary below", "Parole chiave a sinistra, appunti a destra, sintesi sotto"), "rectangle.split.2x1", nil, [
            .title("{title}"), .text("{date} · {subject}"),
            .table([[L("Cues and questions", "Parole chiave e domande"), L("Notes", "Appunti")], ["", ""], ["", ""], ["", ""], ["", ""], ["", ""]]),
            .h1(L("Summary", "Sintesi")), .text("…"),
        ]),
        doc("summary", L("Summary sheet", "Scheda di riassunto"), L("In short, main points, definitions, links", "In breve, punti principali, definizioni, collegamenti"), "list.bullet.rectangle", nil, [
            .title("{title}"), .text("{date} · {subject}"),
            .h1(L("In short", "In breve")), .text("…"),
            .h1(L("Main points", "Punti principali")), .bullet("…"),
            .h1(L("Definitions", "Definizioni")), .text("…"),
            .h1(L("Links to other topics", "Collegamenti con altri argomenti")), .bullet("…"),
        ]),
        doc("homework", L("Homework tracker", "Registro compiti"), L("What is due, by when, done or not", "Cosa c'è da fare, per quando, fatto o no"), "checklist", nil, [
            .title(L("Homework", "Compiti")), .text("{date}"),
            .table([[L("Subject", "Materia"), L("Task", "Compito"), L("Due", "Scadenza"), L("Done", "Fatto")], ["", "", "", ""], ["", "", "", ""], ["", "", "", ""], ["", "", "", ""], ["", "", "", ""]]),
        ]),
        doc("exam", L("Exam preparation", "Preparazione alla verifica"), L("Topics to cover, plan, mistakes to avoid", "Argomenti, piano di studio, errori da evitare"), "graduationcap", nil, [
            .title(L("Exam preparation", "Preparazione alla verifica")), .text("{subject} · {date}"),
            .h1(L("Topics to cover", "Argomenti da studiare")), .bullet("…"),
            .h1(L("Study plan", "Piano di studio")),
            .table([[L("Day", "Giorno"), L("What I study", "Cosa studio"), L("Done", "Fatto")], ["", "", ""], ["", "", ""], ["", "", ""], ["", "", ""]]),
            .h1(L("Mistakes to avoid", "Errori da evitare")), .bullet("…"),
            .h1(L("Questions I still have", "Dubbi rimasti")), .bullet("…"),
        ]),
        doc("reading", L("Book report", "Scheda libro"), L("Author, plot, characters, my opinion", "Autore, trama, personaggi, opinione personale"), "book", nil, [
            .title("{title}"), .text(L("Author: …", "Autore: …")),
            .h1(L("Plot", "Trama")), .text("…"),
            .h1(L("Characters", "Personaggi")), .bullet("…"),
            .h1(L("Themes", "Temi")), .bullet("…"),
            .h1(L("My opinion", "La mia opinione")), .text("…"),
        ]),

        // Mathematics
        doc("math-exercises", L("Solved exercises", "Esercizi svolti"), L("Problem, data, solution, check", "Testo, dati, svolgimento, verifica"), "x.squareroot", .math, [
            .title("{title}"), .text("{date} · {subject}"),
            .h1(L("Exercise 1", "Esercizio 1")), .text(L("Problem: …", "Testo: …")), .text(L("Data: …", "Dati: …")), .text(L("Solution: …", "Svolgimento: …")), .text(L("Check: …", "Verifica: …")),
            .h1(L("Exercise 2", "Esercizio 2")), .text(L("Problem: …", "Testo: …")), .text(L("Data: …", "Dati: …")), .text(L("Solution: …", "Svolgimento: …")), .text(L("Check: …", "Verifica: …")),
            .h1(L("Exercise 3", "Esercizio 3")), .text(L("Problem: …", "Testo: …")), .text(L("Data: …", "Dati: …")), .text(L("Solution: …", "Svolgimento: …")), .text(L("Check: …", "Verifica: …")),
        ]),
        doc("math-formulas", L("Formula sheet", "Formulario"), L("Formula, when to use it, example", "Formula, quando si usa, esempio"), "function", .math, [
            .title(L("Formulas", "Formulario")), .text("{title} · {date}"),
            .table([[L("Formula", "Formula"), L("When to use it", "Quando si usa"), L("Example", "Esempio")], ["", "", ""], ["", "", ""], ["", "", ""], ["", "", ""], ["", "", ""]]),
            .h1(L("Theorems and properties", "Teoremi e proprietà")), .bullet("…"),
        ]),
        doc("math-errors", L("Error log", "Registro degli errori"), L("Where I went wrong and how to avoid it", "Dove ho sbagliato e come evitarlo"), "exclamationmark.triangle", .math, [
            .title(L("Error log", "Registro degli errori")), .text("{date} · {subject}"),
            .table([[L("Exercise", "Esercizio"), L("My mistake", "Il mio errore"), L("Correct way", "Procedimento corretto")], ["", "", ""], ["", "", ""], ["", "", ""], ["", "", ""]]),
        ]),

        // Italian / literature
        doc("it-text", L("Text analysis", "Analisi del testo"), L("Author, genre, summary, themes, style", "Autore, genere, riassunto, temi, stile"), "text.book.closed", .italian, [
            .title(L("Text analysis", "Analisi del testo")), .text("{title}"),
            .h1(L("Author and context", "Autore e contesto")), .text("…"),
            .h1(L("Genre", "Genere")), .text("…"),
            .h1(L("Summary", "Riassunto")), .text("…"),
            .h1(L("Characters", "Personaggi")), .bullet("…"),
            .h1(L("Themes", "Temi")), .bullet("…"),
            .h1(L("Style and language", "Stile e lingua")), .text("…"),
            .h1(L("Personal comment", "Commento personale")), .text("…"),
        ]),
        doc("it-essay", L("Essay outline", "Scaletta del tema"), L("Introduction, development, conclusion", "Introduzione, sviluppo, conclusione"), "pencil.line", .italian, [
            .title("{title}"), .text("{date} · {subject}"),
            .h1(L("Introduction", "Introduzione")), .text(L("Presents the topic and my thesis. …", "Presento l'argomento e la mia tesi. …")),
            .h1(L("Development", "Sviluppo")), .bullet(L("Argument 1 + example", "Argomento 1 + esempio")), .bullet(L("Argument 2 + example", "Argomento 2 + esempio")), .bullet(L("Counter-argument and reply", "Obiezione e risposta")),
            .h1(L("Conclusion", "Conclusione")), .text(L("Sums up and closes the thesis. …", "Riprendo la tesi e chiudo. …")),
        ]),

        // History
        doc("hist-timeline", L("Timeline table", "Tabella cronologica"), L("Date, event, why it matters", "Data, evento, perché è importante"), "clock", .history, [
            .title("{title}"), .text("{date} · {subject}"),
            .table([[L("Date", "Data"), L("Event", "Evento"), L("Why it matters", "Perché è importante")], ["", "", ""], ["", "", ""], ["", "", ""], ["", "", ""], ["", "", ""], ["", "", ""]]),
        ]),
        doc("hist-causes", L("Causes and consequences", "Cause e conseguenze"), L("Context, causes, events, consequences", "Contesto, cause, fatti, conseguenze"), "arrow.triangle.branch", .history, [
            .title("{title}"), .text("{date} · {subject}"),
            .h1(L("Context", "Contesto")), .text("…"),
            .h1(L("Causes", "Cause")), .bullet("…"),
            .h1(L("Main events", "Fatti principali")), .bullet("…"),
            .h1(L("Consequences", "Conseguenze")), .bullet("…"),
            .h1(L("Sources", "Fonti")), .bullet("…"),
        ]),

        // Languages
        doc("lang-vocab", L("Vocabulary list", "Lista di vocaboli"), L("Word, meaning, example sentence", "Parola, significato, frase d'esempio"), "character.book.closed", .english, [
            .title(L("Vocabulary", "Vocaboli")), .text("{title} · {date}"),
            .table([[L("Word", "Parola"), L("Meaning", "Significato"), L("Example", "Esempio")], ["", "", ""], ["", "", ""], ["", "", ""], ["", "", ""], ["", "", ""], ["", "", ""]]),
        ]),
        doc("lang-essay", L("Essay", "Composizione"), L("Introduction, paragraphs, conclusion", "Introduzione, paragrafi, conclusione"), "pencil.and.list.clipboard", .english, [
            .title("{title}"), .text("{date} · {subject}"),
            .h1(L("Introduction", "Introduzione")), .text("…"),
            .h1(L("Paragraph 1", "Paragrafo 1")), .text("…"),
            .h1(L("Paragraph 2", "Paragrafo 2")), .text("…"),
            .h1(L("Conclusion", "Conclusione")), .text("…"),
        ]),
        doc("lang-grammar", L("Grammar notes", "Appunti di grammatica"), L("Rule, examples, exceptions", "Regola, esempi, eccezioni"), "text.quote", .english, [
            .title("{title}"), .text("{date} · {subject}"),
            .h1(L("Rule", "Regola")), .text("…"),
            .h1(L("Examples", "Esempi")), .bullet("…"),
            .h1(L("Exceptions", "Eccezioni")), .bullet("…"),
            .h1(L("Common mistakes", "Errori comuni")), .bullet("…"),
        ]),

        // Science
        doc("sci-lab", L("Lab report", "Relazione di laboratorio"), L("Aim, materials, method, data, conclusion", "Scopo, materiali, procedura, dati, conclusioni"), "flask", .science, [
            .title(L("Lab report", "Relazione di laboratorio")), .text("{title} · {date}"),
            .h1(L("Aim", "Scopo")), .text("…"),
            .h1(L("Materials", "Materiali")), .bullet("…"),
            .h1(L("Method", "Procedura")), .bullet("…"),
            .h1(L("Data", "Dati")),
            .table([[L("Trial", "Prova"), L("Measure", "Misura"), L("Unit", "Unità"), L("Notes", "Note")], ["1", "", "", ""], ["2", "", "", ""], ["3", "", "", ""]]),
            .h1(L("Analysis", "Analisi")), .text("…"),
            .h1(L("Conclusion", "Conclusioni")), .text("…"),
        ]),
        doc("sci-concepts", L("Concepts and units", "Grandezze e unità"), L("Quantity, symbol, unit, formula", "Grandezza, simbolo, unità, formula"), "ruler", .science, [
            .title(L("Concepts and units", "Grandezze e unità")), .text("{date} · {subject}"),
            .table([[L("Quantity", "Grandezza"), L("Symbol", "Simbolo"), L("Unit", "Unità"), L("Formula", "Formula")], ["", "", "", ""], ["", "", "", ""], ["", "", "", ""], ["", "", "", ""], ["", "", "", ""]]),
        ]),

        // Art, philosophy, geography, music, computing, sport
        doc("art-work", L("Artwork analysis", "Analisi di un'opera"), L("Artist, date, technique, description, meaning", "Artista, data, tecnica, descrizione, significato"), "paintpalette", .art, [
            .title("{title}"), .text(L("Artist: …   Date: …   Technique: …", "Artista: …   Data: …   Tecnica: …")),
            .h1(L("Description", "Descrizione")), .text("…"),
            .h1(L("Composition and colour", "Composizione e colore")), .text("…"),
            .h1(L("Meaning and context", "Significato e contesto")), .text("…"),
        ]),
        doc("phil-thinker", L("Thinker profile", "Scheda del pensatore"), L("Life, ideas, key terms, a quote", "Vita, idee, parole chiave, una citazione"), "theatermasks", .philosophy, [
            .title("{title}"), .text("{date} · {subject}"),
            .h1(L("Life and times", "Vita e epoca")), .text("…"),
            .h1(L("Main ideas", "Idee principali")), .bullet("…"),
            .h1(L("Key terms", "Parole chiave")), .bullet("…"),
            .h1(L("A quote", "Una citazione")), .text("…"),
        ]),
        doc("geo-place", L("Place profile", "Scheda di un luogo"), L("Location, climate, people, economy", "Posizione, clima, popolazione, economia"), "map", .geography, [
            .title("{title}"), .text("{date} · {subject}"),
            .h1(L("Where it is", "Dove si trova")), .text("…"),
            .h1(L("Climate and landscape", "Clima e paesaggio")), .text("…"),
            .h1(L("People and culture", "Popolazione e cultura")), .text("…"),
            .h1(L("Economy", "Economia")), .text("…"),
        ]),
        doc("music-piece", L("Music listening", "Ascolto di un brano"), L("Piece, composer, period, instruments, feelings", "Brano, autore, periodo, strumenti, sensazioni"), "music.note", .music, [
            .title("{title}"), .text(L("Composer: …   Period: …", "Autore: …   Periodo: …")),
            .h1(L("Instruments and form", "Strumenti e forma")), .text("…"),
            .h1(L("What I hear", "Cosa ascolto")), .text("…"),
            .h1(L("How it makes me feel", "Che sensazioni mi dà")), .text("…"),
        ]),
        doc("cs-algorithm", L("Algorithm notes", "Appunti su un algoritmo"), L("Problem, idea, steps, complexity", "Problema, idea, passi, complessità"), "laptopcomputer", .computing, [
            .title("{title}"), .text("{date} · {subject}"),
            .h1(L("Problem", "Problema")), .text("…"),
            .h1(L("Idea", "Idea")), .text("…"),
            .h1(L("Steps", "Passi")), .bullet("…"),
            .h1(L("Complexity and tests", "Complessità e test")), .text("…"),
        ]),
        doc("sport-log", L("Training log", "Diario degli allenamenti"), L("Date, activity, how it went", "Data, attività, come è andata"), "figure.run", .sport, [
            .title(L("Training log", "Diario degli allenamenti")), .text("{date}"),
            .table([[L("Date", "Data"), L("Activity", "Attività"), L("Result", "Risultato"), L("Notes", "Note")], ["", "", "", ""], ["", "", "", ""], ["", "", "", ""], ["", "", "", ""]]),
        ]),
    ]}

    // MARK: Whiteboards

    static var boards: [CobrainTemplate] {[
        board("b-mindmap", L("Mind map", "Mappa mentale"), L("A topic in the middle, branches around it", "Un argomento al centro, rami intorno"), "circle.hexagongrid", nil) { mindMap() },
        board("b-weekly", L("Weekly planner", "Piano settimanale"), L("Seven columns, one per day", "Sette colonne, una per giorno"), "calendar", nil) { weekly() },
        board("b-kanban", L("Homework board", "Bacheca dei compiti"), L("To do, doing, done", "Da fare, in corso, fatto"), "rectangle.split.3x1", nil) { kanban() },
        board("b-compare", L("Compare", "Confronto"), L("Two sides, side by side", "Due elementi a confronto"), "rectangle.split.2x1", nil) { compare() },
        board("b-timeline", L("Timeline", "Linea del tempo"), L("Events along a line", "Eventi lungo una linea"), "clock", .history) { timeline() },
        board("b-plane", L("Coordinate plane", "Piano cartesiano"), L("Axes and grid to draw functions by hand", "Assi e griglia per disegnare funzioni"), "chart.xyaxis.line", .math) { plane() },
        board("b-cycle", L("Process or cycle", "Processo o ciclo"), L("Steps joined by arrows", "Fasi collegate da frecce"), "arrow.triangle.2.circlepath", .science) { cycle() },
        board("b-wordmap", L("Word map", "Mappa lessicale"), L("A word with meanings, synonyms and examples", "Una parola con significati, sinonimi ed esempi"), "character.bubble", .english) { wordMap() },
        board("b-argument", L("Argument map", "Mappa degli argomenti"), L("Thesis, arguments, counter-arguments", "Tesi, argomenti, obiezioni"), "bubble.left.and.bubble.right", .italian) { argument() },
    ]}

    private static let violet: UInt32 = 0x7C6CF0, blue: UInt32 = 0x4C9AFF, green: UInt32 = 0x36B37E, yellow: UInt32 = 0xFFE56B, orange: UInt32 = 0xFFAB00, pink: UInt32 = 0xF06CAB, red: UInt32 = 0xFF5630

    private static func shape(_ kind: BoardKind, _ x: Double, _ y: Double, _ w: Double, _ h: Double, fill: UInt32? = nil, text: String = "", size: Double = 20, stroke: UInt32 = 0x2B2B33) -> BoardElement {
        var e = BoardElement(kind: kind)
        e.x = x; e.y = y; e.w = w; e.h = h
        e.fill = fill.map { .hex($0) } ?? .clear
        e.stroke = .hex(stroke)
        e.text = text; e.fontSize = size
        if kind == .sticky { e.fill = .hex(fill ?? yellow) }
        return e
    }

    private static func line(_ pts: [(Double, Double)], arrow: Bool = false, width: Double = 2, color: UInt32 = 0x2B2B33) -> BoardElement {
        var e = BoardElement(kind: arrow ? .arrow : .line)
        e.points = pts.map { [$0.0, $0.1] }
        e.lineWidth = width
        e.stroke = .hex(color)
        return e
    }

    private static func label(_ text: String, _ x: Double, _ y: Double, size: Double = 20, w: Double = 240) -> BoardElement {
        var e = BoardElement(kind: .text)
        e.x = x; e.y = y; e.w = w; e.h = size * 1.4; e.text = text; e.fontSize = size
        return e
    }

    private static func mindMap() -> [BoardElement] {
        var els = [shape(.ellipse, 330, 230, 220, 130, fill: violet, text: L("Topic", "Argomento"), size: 26)]
        let branches: [(Double, Double, UInt32)] = [(60, 60, blue), (640, 60, green), (60, 440, orange), (640, 440, pink)]
        for (i, b) in branches.enumerated() {
            els.append(shape(.roundRect, b.0, b.1, 200, 90, fill: b.2, text: L("Idea \(i + 1)", "Idea \(i + 1)")))
            let cx = b.0 + 100, cy = b.1 + 45
            let toX = cx < 440 ? 340.0 : 540.0, toY = cy < 300 ? 270.0 : 330.0
            els.append(line([(cx < 440 ? b.0 + 200 : b.0, cy), (toX, toY)], arrow: true))
        }
        return els
    }

    private static func weekly() -> [BoardElement] {
        let days = isItalian ? ["Lunedì", "Martedì", "Mercoledì", "Giovedì", "Venerdì", "Sabato", "Domenica"] : ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let colors = [violet, blue, green, orange, pink, red, 0x5B6B7A]
        var els: [BoardElement] = [label(L("This week", "Questa settimana"), 40, 0, size: 30, w: 400)]
        for (i, d) in days.enumerated() {
            let x = 40 + Double(i) * 150
            els.append(shape(.rect, x, 60, 140, 40, fill: colors[i], text: d, size: 16, stroke: colors[i]))
            els.append(shape(.rect, x, 100, 140, 420))
        }
        return els
    }

    private static func kanban() -> [BoardElement] {
        let cols = [(L("To do", "Da fare"), red), (L("Doing", "In corso"), orange), (L("Done", "Fatto"), green)]
        var els: [BoardElement] = [label(L("Homework", "Compiti"), 40, 0, size: 30, w: 400)]
        for (i, c) in cols.enumerated() {
            let x = 40 + Double(i) * 290
            els.append(shape(.rect, x, 60, 270, 44, fill: c.1, text: c.0, size: 20, stroke: c.1))
            els.append(shape(.rect, x, 104, 270, 440))
        }
        els.append(shape(.sticky, 60, 130, 160, 120, text: L("Task 1", "Compito 1")))
        els.append(shape(.sticky, 60, 270, 160, 120, fill: 0xFFB8D9, text: L("Task 2", "Compito 2")))
        return els
    }

    private static func compare() -> [BoardElement] {
        [label(L("Compare", "Confronto"), 40, 0, size: 30, w: 400),
         shape(.rect, 40, 60, 360, 44, fill: blue, text: L("A", "A"), size: 22, stroke: blue), shape(.rect, 40, 104, 360, 420),
         shape(.rect, 420, 60, 360, 44, fill: pink, text: L("B", "B"), size: 22, stroke: pink), shape(.rect, 420, 104, 360, 420),
         label(L("Similarities", "Somiglianze"), 40, 545, size: 18), shape(.roundRect, 40, 580, 740, 100)]
    }

    private static func timeline() -> [BoardElement] {
        var els: [BoardElement] = [label(L("Timeline", "Linea del tempo"), 40, 0, size: 30, w: 400), line([(40, 260), (900, 260)], arrow: true, width: 4)]
        let colors = [violet, blue, green, orange, pink]
        for i in 0..<5 {
            let x = 90 + Double(i) * 170
            els.append(shape(.ellipse, x, 245, 30, 30, fill: colors[i], stroke: colors[i]))
            els.append(label(L("Year", "Anno"), x - 20, i % 2 == 0 ? 195 : 285, size: 18, w: 90))
            els.append(shape(.sticky, x - 60, i % 2 == 0 ? 330 : 100, 150, 110, fill: [yellow, 0xFFB8D9, 0xB8E4FF, 0xC9F2C7, 0xFFD9A8][i], text: L("Event", "Evento")))
        }
        return els
    }

    private static func plane() -> [BoardElement] {
        var els: [BoardElement] = []
        let cx = 420.0, cy = 300.0, step = 40.0
        for i in -10...10 where i != 0 {
            let g: UInt32 = 0xD0D4DC
            els.append(line([(cx + Double(i) * step, cy - 280), (cx + Double(i) * step, cy + 280)], width: 1, color: g))
            if abs(i) <= 7 { els.append(line([(cx - 420, cy + Double(i) * step), (cx + 420, cy + Double(i) * step)], width: 1, color: g)) }
        }
        els.append(line([(cx - 430, cy), (cx + 440, cy)], arrow: true, width: 2.5))
        els.append(line([(cx, cy + 290), (cx, cy - 300)], arrow: true, width: 2.5))
        els.append(label("x", cx + 420, cy + 6, size: 22, w: 30)); els.append(label("y", cx + 8, cy - 320, size: 22, w: 30)); els.append(label("O", cx + 6, cy + 4, size: 16, w: 30))
        return els
    }

    private static func cycle() -> [BoardElement] {
        let pos: [(Double, Double)] = [(320, 20), (620, 230), (320, 440), (20, 230)]
        let colors = [blue, green, orange, pink]
        var els: [BoardElement] = []
        for (i, p) in pos.enumerated() {
            els.append(shape(.roundRect, p.0, p.1, 220, 100, fill: colors[i], text: L("Step \(i + 1)", "Fase \(i + 1)")))
        }
        els.append(line([(540, 70), (640, 230)], arrow: true)); els.append(line([(700, 330), (540, 470)], arrow: true))
        els.append(line([(320, 490), (180, 330)], arrow: true)); els.append(line([(120, 230), (320, 80)], arrow: true))
        return els
    }

    private static func wordMap() -> [BoardElement] {
        [shape(.ellipse, 300, 220, 240, 120, fill: violet, text: L("Word", "Parola"), size: 28),
         shape(.roundRect, 40, 40, 220, 90, fill: blue, text: L("Meaning", "Significato")), shape(.roundRect, 580, 40, 220, 90, fill: green, text: L("Synonyms", "Sinonimi")),
         shape(.roundRect, 40, 430, 220, 90, fill: orange, text: L("Opposites", "Contrari")), shape(.roundRect, 580, 430, 220, 90, fill: pink, text: L("Example", "Esempio")),
         line([(240, 130), (330, 230)], arrow: true), line([(600, 130), (510, 230)], arrow: true), line([(240, 430), (340, 330)], arrow: true), line([(600, 430), (500, 330)], arrow: true)]
    }

    private static func argument() -> [BoardElement] {
        [shape(.roundRect, 260, 20, 320, 100, fill: violet, text: L("Thesis", "Tesi"), size: 26),
         shape(.rect, 40, 220, 220, 110, fill: green, text: L("Argument 1", "Argomento 1")), shape(.rect, 310, 220, 220, 110, fill: green, text: L("Argument 2", "Argomento 2")), shape(.rect, 580, 220, 220, 110, fill: red, text: L("Objection", "Obiezione")),
         shape(.sticky, 40, 380, 220, 130, text: L("Example", "Esempio")), shape(.sticky, 310, 380, 220, 130, text: L("Example", "Esempio")), shape(.sticky, 580, 380, 220, 130, fill: 0xFFB8D9, text: L("Reply", "Risposta")),
         line([(420, 120), (150, 220)], arrow: true), line([(420, 120), (420, 220)], arrow: true), line([(420, 120), (690, 220)], arrow: true)]
    }
}

// MARK: Creating files from templates

enum TemplateWriter {
    /// Makes a new file from `template` in `folder` and returns it. `subject` is the subject's name (empty if none).
    @MainActor static func create(_ template: CobrainTemplate, in folder: URL, subject: String, setup: ((Engine) -> Void)? = nil) -> URL? {
        let base = template.title
        let url = freshURL(base, ext: template.fileExtension, in: folder)
        switch template.source {
        case .file(let src):
            do { try FileManager.default.copyItem(at: src, to: url) } catch { return nil }
            return url
        case .board(let make):
            let board = BoardModel()
            board.elements = make()
            guard let data = try? board.encoded(), (try? data.write(to: url)) != nil else { return nil }
            return url
        case .document(let blocks):
            guard let e = Engine() else { return nil }
            setup?(e)
            write(blocks, into: e, title: template.id == "blank" ? "" : url.deletingPathExtension().lastPathComponent, subject: subject)
            return e.save(to: url.path) ? url : nil
        }
    }

    static func freshURL(_ base: String, ext: String, in folder: URL) -> URL {
        var n = 1
        while true {
            let name = n == 1 ? base : "\(base) \(n)"
            let u = folder.appendingPathComponent(name).appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: u.path) { return u }
            n += 1
        }
    }

    /// Writes the blocks into the blank document `e` through the engine's commands.
    static func write(_ blocks: [TBlock], into e: Engine, title: String, subject: String) {
        guard !blocks.isEmpty else { return }
        let date = Date().formatted(.dateTime.day().month(.wide).year().locale(isItalian ? Locale(identifier: "it_IT") : .current))
        func fill(_ s: String) -> String {
            var out = s.replacingOccurrences(of: "{title}", with: title).replacingOccurrences(of: "{date}", with: date).replacingOccurrences(of: "{subject}", with: subject)
            if subject.isEmpty { out = out.replacingOccurrences(of: " · ", with: "").replacingOccurrences(of: ": ", with: ": ").trimmingCharacters(in: .whitespaces) }
            return out
        }
        var fresh = true   // the document's first paragraph is already there; so is the paragraph after a table
        func paragraph(_ style: String, _ text: String, bullet: Bool = false) {
            if !fresh { _ = e.run("text.newParagraph") }
            fresh = false
            _ = e.run("para.style", ["style": style])
            _ = e.run("para.bullets", bullet ? [:] : ["off": true])
            if !text.isEmpty { _ = e.run("text.insert", ["text": text]) }
        }
        for b in blocks {
            switch b {
            case .title(let t): paragraph("Title", fill(t))
            case .subtitle(let t): paragraph("Subtitle", fill(t))
            case .h1(let t): paragraph("Heading1", fill(t))
            case .h2(let t): paragraph("Heading2", fill(t))
            case .text(let t): paragraph("Normal", fill(t))
            case .bullet(let t): paragraph("Normal", fill(t), bullet: true)
            case .table(let rows):
                let cols = rows.map(\.count).max() ?? 1
                paragraph("Normal", "")
                _ = e.run("insert.table", ["rows": rows.count, "cols": cols])
                for (r, row) in rows.enumerated() {
                    for (c, cell) in row.enumerated() {
                        if !cell.isEmpty { _ = e.run("text.insert", ["text": fill(cell)]) }
                        if !(r == rows.count - 1 && c == row.count - 1) { _ = e.run("text.tab") }
                    }
                }
                _ = e.run("caret.docEnd")
                fresh = true
            }
        }
        _ = e.run("caret.docStart")
        e.markClean()
    }
}

// MARK: Your own templates

/// Templates of yours, stored as files inside the project (see the top of this file).
struct TemplateStore {
    let root: URL
    static let folderName = ".cobrain-templates"
    static let allScope = "_all"

    private var base: URL { root.appendingPathComponent(Self.folderName) }

    func list() -> [CobrainTemplate] {
        let fm = FileManager.default
        var out: [CobrainTemplate] = []
        for scopeDir in (try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? [] {
            let scope = scopeDir.lastPathComponent
            for f in (try? fm.contentsOfDirectory(at: scopeDir, includingPropertiesForKeys: nil)) ?? [] where ["docx", "cobrainboard"].contains(f.pathExtension.lowercased()) {
                let isBoard = f.pathExtension.lowercased() == "cobrainboard"
                let subject = scope == Self.allScope ? nil : scope
                out.append(CobrainTemplate(id: f.path, title: f.deletingPathExtension().lastPathComponent, detail: subject.map { L("For \($0)", "Per \($0)") } ?? L("For every subject", "Per tutte le materie"),
                                           symbol: isBoard ? "scribble.variable" : "doc.text", kind: nil, scope: subject, source: .file(f)))
            }
        }
        return out.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Keeps a copy of `file` as a template, for one subject (`scope` = its folder name) or for all (`nil`).
    @discardableResult
    func save(copyOf file: URL, name: String, scope: String?) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        guard !clean.isEmpty, !clean.hasPrefix(".") else { return false }
        let dir = base.appendingPathComponent(scope ?? Self.allScope)
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch { return false }
        let dest = dir.appendingPathComponent(clean).appendingPathExtension(file.pathExtension)
        try? FileManager.default.removeItem(at: dest)
        do { try FileManager.default.copyItem(at: file, to: dest) } catch { return false }
        return true
    }

    func delete(_ t: CobrainTemplate) { if case .file(let u) = t.source { try? FileManager.default.removeItem(at: u) } }

    /// The subject a file belongs to: the first folder under the project, if it is inside one.
    func subject(of file: URL) -> String? {
        let r = root.standardizedFileURL.path, p = file.standardizedFileURL.path
        guard p.hasPrefix(r + "/") else { return nil }
        let parts = p.dropFirst(r.count + 1).split(separator: "/")
        return parts.count >= 2 ? String(parts[0]) : nil
    }
}

// MARK: Views

/// Pick a template: documents and whiteboards, the ones for this subject first, then those for every subject, then yours.
struct TemplateGallery: View {
    let subject: String?
    let root: URL
    let onPick: (CobrainTemplate) -> Void
    let onCancel: () -> Void
    @State private var boards = ProcessInfo.processInfo.environment["COBRAIN_GALLERY_BOARDS"] != nil
    @State private var mine: [CobrainTemplate] = []
    @State private var toDelete: CobrainTemplate?

    private var kind: SubjectKind? { subject.flatMap { SubjectKind.of($0) } }
    private var store: TemplateStore { TemplateStore(root: root) }

    private func visible(_ list: [CobrainTemplate]) -> [CobrainTemplate] { list.filter { $0.isBoard == boards } }
    private var forSubject: [CobrainTemplate] {
        visible(TemplateCatalog.builtin.filter { $0.kind != nil && $0.kind == kind } + mine.filter { $0.scope != nil && $0.scope == subject })
    }
    private var forAll: [CobrainTemplate] { visible(TemplateCatalog.builtin.filter { $0.kind == nil }) }
    private var yours: [CobrainTemplate] { visible(mine.filter { $0.scope == nil }) }
    private var others: [CobrainTemplate] { visible(TemplateCatalog.builtin.filter { $0.kind != nil && $0.kind != kind }) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(subject.map { L("New in \($0)", "Nuovo in \($0)") } ?? L("New from template", "Nuovo da modello")).font(.title2.weight(.semibold))
                Spacer()
                Button(L("Cancel", "Annulla"), action: onCancel).keyboardShortcut(.cancelAction)
            }.padding([.horizontal, .top], 20)
            Picker("", selection: $boards) {
                Text(L("Documents", "Documenti")).tag(false)
                Text(L("Whiteboards", "Lavagne")).tag(true)
            }.pickerStyle(.segmented).frame(maxWidth: 320).padding(.vertical, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section(subject.map { L("For \($0)", "Per \($0)") } ?? "", forSubject)
                    section(L("For every subject", "Per tutte le materie"), forAll)
                    section(L("My templates", "I miei modelli"), yours, emptyHint: L("Save a document or whiteboard as a template to find it here.", "Salva un documento o una lavagna come modello per trovarlo qui."))
                    section(L("For other subjects", "Per altre materie"), others)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .onAppear { mine = store.list() }
        .confirmationDialog(L("Delete the template “\(toDelete?.title ?? "")”?", "Eliminare il modello “\(toDelete?.title ?? "")”?"), isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
            Button(L("Delete", "Elimina"), role: .destructive) { if let t = toDelete { store.delete(t); mine = store.list() }; toDelete = nil }
        }
    }

    @ViewBuilder private func section(_ title: String, _ items: [CobrainTemplate], emptyHint: String? = nil) -> some View {
        if !items.isEmpty || emptyHint != nil {
            VStack(alignment: .leading, spacing: 10) {
                if !title.isEmpty { Text(title).font(.headline) }
                if items.isEmpty, let emptyHint { Text(emptyHint).foregroundStyle(.secondary).font(.callout) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128, maximum: 150), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(items) { t in
                        TemplatePickTile(template: t) { onPick(t) }
                            .contextMenu { if t.isMine { Button(L("Delete template", "Elimina modello"), role: .destructive) { toDelete = t } } }
                    }
                }
            }
        }
    }
}

struct TemplatePickTile: View {
    let template: CobrainTemplate
    let action: () -> Void
    @State private var image: CGImage?

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                ZStack {
                    Color.white
                    if let image { Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: template.isBoard ? .fit : .fill) }
                    else { Image(systemName: template.symbol).font(.system(size: 26)).foregroundStyle(.secondary) }
                }
                .frame(width: 128, height: template.isBoard ? 100 : 160).clipped()
                .overlay(Rectangle().stroke(Color.gray.opacity(0.45)))
                .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                Text(template.title).font(.system(size: 12.5, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading).frame(width: 128, alignment: .leading)
                Text(template.detail).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading).frame(width: 128, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .task { await MainActor.run { image = TemplateThumbnails.image(for: template) } }
    }
}

/// Previews of templates, drawn the first time they are shown.
@MainActor enum TemplateThumbnails {
    private static var cache: [String: CGImage] = [:]

    static func image(for t: CobrainTemplate) -> CGImage? {
        if let c = cache[t.id] { return c }
        var img: CGImage?
        switch t.source {
        case .file(let u): img = FileThumbnails.image(for: u, width: 260)
        case .board(let make):
            let b = BoardModel(); b.elements = make()
            if let png = b.renderPNG(scale: 0.6), let src = CGImageSourceCreateWithData(png as CFData, nil) { img = CGImageSourceCreateImageAtIndex(src, 0, nil) }
        case .document(let blocks):
            if t.id != "blank", let e = Engine() {
                TemplateWriter.write(blocks, into: e, title: t.title, subject: "")
                if let size = e.pageSize(0) { img = e.renderPage(0, scale: 260 / size.width) }
            }
        }
        if let img { cache[t.id] = img }
        return img
    }
}

/// "Save as template": name, and whether it is for every subject or just this one.
struct SaveTemplateForm: View {
    let subject: String?
    @State var name: String
    let onSave: (String, Bool) -> Void   // name, for every subject
    let onCancel: () -> Void
    @State private var forAll = true

    init(subject: String?, name: String, onSave: @escaping (String, Bool) -> Void, onCancel: @escaping () -> Void) {
        self.subject = subject; self._name = State(initialValue: name); self.onSave = onSave; self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Save as template", "Salva come modello")).font(.title2.weight(.semibold))
            TextField(L("Template name", "Nome del modello"), text: $name).textFieldStyle(.roundedBorder)
            if let subject {
                Picker(L("Use it in", "Usalo in"), selection: $forAll) {
                    Text(L("Every subject", "Tutte le materie")).tag(true)
                    Text(L("Only \(subject)", "Solo \(subject)")).tag(false)
                }
                #if os(macOS)
                .pickerStyle(.radioGroup)
                #else
                .pickerStyle(.inline)
                #endif
            } else {
                Text(L("It will be available in every subject.", "Sarà disponibile in tutte le materie.")).foregroundStyle(.secondary).font(.callout)
            }
            HStack {
                Spacer()
                Button(L("Cancel", "Annulla"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(L("Save", "Salva")) { onSave(name, subject == nil ? true : forAll) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24).frame(minWidth: 360)
    }
}
