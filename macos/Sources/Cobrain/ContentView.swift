import SwiftUI

struct ContentView: View {
    @ObservedObject var model: DocumentModel

    var body: some View {
        VStack(spacing: 0) {
            RibbonView(model: model)
            PagesView(model: model)
        }
            .navigationTitle(model.title)
            .toolbar {
                ToolbarItemGroup {
                    Button { model.open() } label: { Label("Open", systemImage: "folder") }
                    Button { model.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                }
                ToolbarItemGroup {
                    Button { model.run("format.bold") } label: { Label("Bold", systemImage: "bold") }
                    Button { model.run("format.italic") } label: { Label("Italic", systemImage: "italic") }
                    Button { model.run("format.underline") } label: { Label("Underline", systemImage: "underline") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text("Page count: \(model.engine.pageCount)")
                    Spacer()
                    if let e = model.lastError { Text(e).foregroundStyle(.red) }
                    Text("Engine \(Engine.version)").foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.bar)
            }
    }
}
