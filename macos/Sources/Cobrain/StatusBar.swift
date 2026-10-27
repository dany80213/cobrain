import SwiftUI

/// Bottom bar like WordCraft's: page, words, language on the left; focus, views and zoom on the right.
struct StatusBar: View {
    @ObservedObject var model: DocumentModel
    @AppStorage("proofingLanguage") private var newDocumentLanguage = Proofing.defaultTag

    var body: some View {
        HStack(spacing: 14) {
            Text("Page \(model.caretPage + 1) of \(model.engine.pageCount)")
            Text("\(model.wordCount) words")
            languageMenu
            Spacer()
            Label("Focus", systemImage: "arrow.up.left.and.arrow.down.right")
            Image(systemName: "book")
            Image(systemName: "doc.text").foregroundStyle(Color.accentColor)
            Image(systemName: "globe")
            HStack(spacing: 6) {
                Button { model.zoom = max(0.25, model.zoom - 0.1) } label: { Image(systemName: "minus") }.buttonStyle(.plain)
                Slider(value: $model.zoom, in: 0.25...3).frame(width: 130).controlSize(.mini)
                Button { model.zoom = min(3, model.zoom + 0.1) } label: { Image(systemName: "plus") }.buttonStyle(.plain)
                Text("\(Int((model.zoom * 100).rounded()))%").frame(width: 40, alignment: .trailing)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).frame(height: 26)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }

    /// The proofing language at the caret; choosing one checks the whole document in it.
    private var languageMenu: some View {
        Menu {
            Section("This document") {
                ForEach(Proofing.languages) { l in
                    Toggle(l.name, isOn: Binding(get: { model.language == l.tag }, set: { _ in model.setDocumentLanguage(l.tag) }))
                }
            }
            Section("New documents") {
                ForEach(Proofing.languages) { l in
                    Toggle(l.name, isOn: Binding(get: { newDocumentLanguage == l.tag }, set: { _ in model.setDefaultLanguage(l.tag) }))
                }
            }
        } label: {
            Text(Proofing.name(for: model.language ?? "en-US"))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Proofing language")
    }
}

/// Horizontal ruler over the page (inches), with margin shading.
struct RulerView: View {
    @ObservedObject var model: DocumentModel

    var body: some View {
        Canvas { ctx, size in
            let z = model.zoom
            let pw = model.pageWidth * z
            let left = (size.width - pw) / 2
            let margin: CGFloat = 72 * z
            let bar = CGRect(x: left, y: 6, width: pw, height: 16)
            ctx.fill(Path(bar), with: .color(Color(nsColor: .controlBackgroundColor)))
            ctx.fill(Path(CGRect(x: left + margin, y: 6, width: pw - 2 * margin, height: 16)), with: .color(.white))
            let inch = 72 * z
            var x = left + margin
            var i = 0
            while x < left + pw - margin + 0.5 {
                ctx.fill(Path(CGRect(x: x, y: 11, width: 1, height: 6)), with: .color(.secondary))
                if i > 0 { ctx.draw(Text("\(i)").font(.system(size: 9)).foregroundStyle(.secondary), at: CGPoint(x: x, y: 14)) }
                let half = x + inch / 2
                if half < left + pw - margin { ctx.fill(Path(CGRect(x: half, y: 12, width: 1, height: 4)), with: .color(.secondary)) }
                x += inch; i += 1
            }
            x = left + margin - inch / 2
            var j = 1
            while x > left {
                ctx.fill(Path(CGRect(x: x, y: 12, width: 1, height: 4)), with: .color(.secondary)); x -= inch / 2; j += 1
            }
        }
        .frame(height: 28)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}
