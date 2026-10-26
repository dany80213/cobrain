import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let cobrainBoard = UTType(exportedAs: "com.cobrain.board")
}

/// A whiteboard file. `ReferenceFileDocument`: the board is a live object, saved from a snapshot; the system
/// saves it by itself after every undo step, so there is no Save button.
final class BoardDocument: ReferenceFileDocument {
    static var readableContentTypes: [UTType] { [.cobrainBoard] }
    let board = BoardModel()

    init() {}

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        try board.load(data)
    }

    func snapshot(contentType: UTType) throws -> Data { try board.encoded() }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }
}

struct CobrainBoardApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { BoardDocument() }) { file in
            BoardPadView(board: file.document.board)
        }
    }
}

/// `-demo file.cobrainboard`: opens a board directly, without the document browser (screenshots and tests).
struct DemoApp: App {
    @StateObject private var board = BoardModel()
    var body: some Scene {
        WindowGroup {
            NavigationStack { BoardPadView(board: board).navigationTitle("Demo").navigationBarTitleDisplayMode(.inline) }
                .onAppear {
                    let a = CommandLine.arguments
                    if let i = a.firstIndex(of: "-demo"), a.indices.contains(i + 1), let d = try? Data(contentsOf: URL(fileURLWithPath: a[i + 1])) {
                        try? board.load(d)
                        board.selection = Set(board.elements.prefix(1).map(\.id))
                        board.fitContent()
                    }
                }
        }
    }
}

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("-demo") { DemoApp.main() } else { CobrainBoardApp.main() }
    }
}
