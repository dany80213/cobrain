import SwiftUI

struct ContentView: View {
    @ObservedObject var model: DocumentModel

    var body: some View {
        VStack(spacing: 0) {
            RibbonView(model: model)
            HStack(spacing: 0) {
                if model.navigationVisible { NavigationPane(model: model); Divider() }
                VStack(spacing: 0) {
                    RulerView(model: model)
                    PagesView(model: model)
                }
            }
        }
            .navigationTitle(model.title)
            .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar(model: model) }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button { model.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                    Button { model.run("edit.undo") } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    Button { model.run("edit.redo") } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                }
                ToolbarItem(placement: .principal) {
                    Text("\(model.title) — \(model.fileURL == nil ? "Not saved" : "Saved")").font(.headline)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { model.open() } label: { Label("Open", systemImage: "folder") }
                    Button { model.navigationVisible.toggle() } label: { Label("Navigation", systemImage: "sidebar.left") }
                }
            }
    }
}
