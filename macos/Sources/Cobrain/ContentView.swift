import SwiftUI

struct ContentView: View {
    @ObservedObject var model: DocumentModel

    var body: some View {
        VStack(spacing: 0) {
            RibbonView(model: model)
            HStack(spacing: 0) {
                if model.navigationVisible && model.toggles["view.navigationPane"] != false { NavigationPane(model: model); Divider() }
                VStack(spacing: 0) {
                    if model.toggles["view.ruler"] != false { RulerView(model: model) }
                    PagesView(model: model)
                }
            }
        }
            .navigationTitle(model.title)
            .sheet(item: $model.dialog) { DialogView(kind: $0, model: model) }
            .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar(model: model) }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Toggle(isOn: $model.autosave) { Text("AutoSave").font(.system(size: 12)) }.toggleStyle(.switch).controlSize(.mini)
                    Button { model.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                    Button { model.run("edit.undo") } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    Button { model.run("edit.redo") } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                }
                ToolbarItem(placement: .principal) {
                    Text("\(model.title) — \(model.fileURL == nil ? "Not saved" : "Saved")").font(.headline)
                }
                ToolbarItemGroup(placement: .primaryAction) { TitleActions(model: model) }
            }
            .overlay { if model.showBackstage { BackstageView(model: model) } }
    }
}
