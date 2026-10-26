import SwiftUI

/// "Search commands and help" field of the title bar: filters the engine's command catalog.
struct TitleSearch: View {
    @ObservedObject var model: DocumentModel
    @State private var query = ""
    @State private var open = false

    private var results: [CommandInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return model.catalog.filter { $0.label.lowercased().contains(q) }.prefix(10).map { $0 }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search commands and help", text: $query).textFieldStyle(.plain)
                .onChange(of: query) { _, v in open = !v.isEmpty }
        }
        .padding(.horizontal, 10).padding(.vertical, 4).frame(width: 280)
        .background(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.4)))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(results) { c in
                    Button {
                        open = false; query = ""
                        if c.needsInput { model.dialog = .unavailable(c.label) } else { model.perform(shortcutCommand: c.id) }
                    } label: {
                        HStack { Text(c.label); Spacer(); Text(c.location).font(.caption).foregroundStyle(.secondary) }
                            .padding(.horizontal, 8).padding(.vertical, 3).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                if results.isEmpty { Text("No commands found").foregroundStyle(.secondary).padding(8) }
            }
            .frame(width: 380).padding(6)
        }
    }
}

struct TitleActions: View {
    @ObservedObject var model: DocumentModel

    var body: some View {
        HStack(spacing: 8) {
            TitleSearch(model: model)
            Button { model.run("review.newComment") } label: { Label("Comments", systemImage: "bubble.left") }
                .buttonStyle(.bordered)
            Menu {
                Button("Editing") { if model.toggles["review.trackChanges"] == true { model.run("review.trackChanges") } }
                Button("Reviewing") { if model.toggles["review.trackChanges"] != true { model.run("review.trackChanges") } }
            } label: {
                Label(model.toggles["review.trackChanges"] == true ? "Reviewing" : "Editing", systemImage: "pencil")
            }.menuStyle(.borderlessButton).fixedSize()
            Button { model.share() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// File tab: the full-window "backstage" with document actions and info.
struct BackstageView: View {
    @ObservedObject var model: DocumentModel
    @State private var page = "Home"
    @State private var info: [(String, String)] = []

    private let items: [(String, String)] = [("Home", "house"), ("Info", "info.circle"), ("New", "doc.badge.plus"), ("Open", "folder"), ("Save", "square.and.arrow.down"),
                                             ("Save As", "square.and.arrow.down.on.square"), ("Export PDF", "doc.richtext"), ("Print", "printer")]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Button { model.showBackstage = false } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28) }
                    .buttonStyle(.plain).padding(.bottom, 12)
                ForEach(items, id: \.0) { it in
                    Button { choose(it.0) } label: {
                        Label(it.0, systemImage: it.1).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7).padding(.horizontal, 10)
                            .background(page == it.0 ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6)).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(16).frame(width: 220).background(Color.accentColor.opacity(0.08))
            VStack(alignment: .leading, spacing: 14) {
                if page == "Home" {
                    HomePage(model: model)
                } else {
                    Text(page).font(.title.weight(.semibold))
                    Text(model.title).font(.title3)
                    if let url = model.fileURL { Text(url.path).foregroundStyle(.secondary).font(.caption) }
                    Divider()
                    ForEach(info, id: \.0) { r in HStack { Text(r.0).frame(width: 140, alignment: .leading); Text(r.1).foregroundStyle(.secondary) } }
                    Spacer()
                }
            }
            .padding(30).frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: loadInfo)
    }

    private func loadInfo() {
        if case .success(let r) = model.engine.run("file.info"), let d = r as? [String: Any] {
            let wanted = [("pages", "Pages"), ("words", "Words"), ("paragraphs", "Paragraphs"), ("sections", "Sections"), ("comments", "Comments")]
            info = wanted.compactMap { k, label in d[k].map { (label, "\($0)") } }
            if let props = d["properties"] as? [String: Any] {
                for (k, label) in [("title", "Title"), ("creator", "Author"), ("lastModifiedBy", "Last modified by")] {
                    if let v = props[k] as? String, !v.isEmpty { info.append((label, v)) }
                }
            }
        }
    }

    private func choose(_ item: String) {
        page = item
        switch item {
        case "New": NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil); model.newDocument(); model.showBackstage = false
        case "Open": model.showBackstage = false; model.open()
        case "Save": model.save(); model.showBackstage = false
        case "Save As": model.showBackstage = false; model.saveAs()
        case "Export PDF": model.showBackstage = false; model.exportPDF()
        case "Print": model.showBackstage = false; model.printDocument()
        default: loadInfo()
        }
    }
}
