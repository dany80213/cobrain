import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let cobrainBoard = UTType(exportedAs: "com.cobrain.board")
}

enum Route: Hashable {
    case word(URL)
    case board(URL)
    case subject(URL)
}

@main
struct CobrainApp: App {
    @StateObject private var library = Library()
    @State private var path: [Route] = []

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                HomeView(library: library, path: $path)
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .word(let url): WordScreen(url: url, library: library)
                        case .board(let url): BoardScreen(url: url, library: library)
                        case .subject(let url): SubjectScreen(url: url, library: library, path: $path)
                        }
                    }
            }
            .onOpenURL { url in if let u = library.importFile(url) { path = [route(u)] } }
            .onAppear {
                // `-open file`: start inside a file (screenshots and tests).
                let a = CommandLine.arguments
                if let i = a.firstIndex(of: "-open"), a.indices.contains(i + 1) {
                    let u = URL(fileURLWithPath: a[i + 1])
                    if let local = library.importFile(u) { path = [route(local)] }
                }
            }
        }
    }

    private func route(_ u: URL) -> Route { FileKind(url: u) == .board ? .board(u) : .word(u) }
}
