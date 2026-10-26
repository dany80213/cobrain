import SwiftUI

/// The iPad whiteboard: the board fills the screen; tools float over it where a thumb or the Pencil hand reaches.
struct BoardPadView: View {
    @ObservedObject var board: BoardModel
    @Environment(\.undoManager) private var undoManager
    @State private var showStyle = false

    private static let drawing: [BoardTool] = [.select, .hand, .pen, .eraser]
    private static let shapes: [BoardTool] = [.rect, .roundRect, .ellipse, .triangle, .diamond, .star, .line, .arrow]
    private static let content: [BoardTool] = [.text, .sticky]
    private let swatches: [UInt32] = [0x2B2B33, 0x7C6CF0, 0x4C9AFF, 0x36B37E, 0xFFAB00, 0xFF5630, 0xF06CAB, 0xFFFFFF]

    var body: some View {
        BoardSurface(board: board)
            .ignoresSafeArea(.container, edges: .bottom)
            .overlay(alignment: .leading) { palette.padding(.leading, 12) }
            .overlay(alignment: .top) { if !board.selection.isEmpty { selectionBar.padding(.top, 8).transition(.move(edge: .top).combined(with: .opacity)) } }
            .overlay(alignment: .bottom) { styleBar.padding(.bottom, 14) }
            .overlay(alignment: .bottomTrailing) { zoomControls.padding(.trailing, 14).padding(.bottom, 82) }
            .animation(.snappy(duration: 0.2), value: board.selection.isEmpty)
            .onAppear { if let undoManager { board.undoManager = undoManager }; board.lineWidth = max(board.lineWidth, 3) }
            .onChange(of: undoManager) { _, m in if let m { board.undoManager = m } }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { board.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!board.canUndo)
                    Button { board.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!board.canRedo)
                    ShareLink(item: BoardPNG(board: board), preview: SharePreview("Whiteboard")) { Image(systemName: "square.and.arrow.up") }
                        .disabled(board.elements.isEmpty)
                }
            }
    }

    // MARK: Tool palette
    private var palette: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(Self.drawing) { toolButton($0) }
                separator
                Menu {
                    ForEach(Self.shapes) { t in Button { board.tool = t } label: { Label(t.label, systemImage: t.symbol) } }
                } label: { toolIcon("square.on.circle", active: Self.shapes.contains(board.tool)) }
                ForEach(Self.content) { toolButton($0) }
                separator
                Button { board.pencilOnly.toggle() } label: {
                    toolIcon(board.pencilOnly ? "applepencil" : "hand.draw", active: false)
                }
                .accessibilityLabel(board.pencilOnly ? "Only Apple Pencil draws" : "Finger draws too")
            }
            .padding(8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 62).fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    private var separator: some View { Divider().frame(width: 28) }

    private func toolButton(_ t: BoardTool) -> some View {
        Button { board.endEditing(); board.tool = t } label: { toolIcon(t.symbol, active: board.tool == t) }
            .accessibilityLabel(t.label)
    }

    private func toolIcon(_ symbol: String, active: Bool) -> some View {
        Image(systemName: symbol).font(.system(size: 19)).frame(width: 46, height: 46)
            .foregroundStyle(active ? Color.white : Color.primary)
            .background(active ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
    }

    // MARK: Contextual bars
    private var selectionBar: some View {
        HStack(spacing: 4) {
            barButton("plus.square.on.square", "Duplicate") { board.duplicateSelection() }
            barButton("square.3.layers.3d.top.filled", "Bring to front") { board.bringToFront() }
            barButton("square.3.layers.3d.bottom.filled", "Send to back") { board.sendToBack() }
            barButton("trash", "Delete", tint: .red) { board.deleteSelection() }
        }
        .padding(6).background(.regularMaterial, in: Capsule()).shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    private func barButton(_ symbol: String, _ label: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(tint).frame(width: 46, height: 40) }
            .accessibilityLabel(label)
    }

    private var shown: BoardElement? { board.selection.first.flatMap { board.element($0) } }

    private var styleBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(swatches, id: \.self) { v in
                    let c = BoardColor.hex(v)
                    Button { board.setStroke(c); if board.tool != .pen && board.tool != .line && board.tool != .arrow { board.setFill(c) } } label: {
                        Circle().fill(c.color).frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Color.gray.opacity(0.5), lineWidth: 1))
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: board.stroke == c ? 3 : 0).padding(-4))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                }
                ColorPicker("Colour", selection: Binding(get: { (shown?.stroke ?? board.stroke).color }, set: { board.setStroke(BoardColor($0)) }), supportsOpacity: true)
                    .labelsHidden()
                Divider().frame(height: 26)
                Image(systemName: "line.diagonal").foregroundStyle(.secondary)
                Slider(value: Binding(get: { shown?.lineWidth ?? board.lineWidth }, set: board.setLineWidth), in: 1...24, step: 1).frame(width: 130)
                Button { board.setFill(.clear) } label: { Image(systemName: "nosign").frame(width: 40, height: 40) }.accessibilityLabel("No fill")
                ColorPicker("Fill", selection: Binding(get: { (shown?.fill ?? board.fill).color }, set: { board.setFill(BoardColor($0)) }), supportsOpacity: true)
                    .labelsHidden()
                Stepper(value: Binding(get: { shown?.fontSize ?? board.fontSize }, set: board.setFontSize), in: 10...96, step: 2) {
                    Image(systemName: "textformat.size")
                }.fixedSize()
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: 760).fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: Capsule()).shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .padding(.horizontal, 20)
    }

    private var zoomControls: some View {
        HStack(spacing: 0) {
            Button { board.zoom(by: 1 / 1.25) } label: { Image(systemName: "minus").frame(width: 44, height: 40) }
            Button { board.fitContent() } label: { Text("\(Int((board.zoom * 100).rounded()))%").font(.system(size: 13).monospacedDigit()).frame(width: 52, height: 40) }
            Button { board.zoom(by: 1.25) } label: { Image(systemName: "plus").frame(width: 44, height: 40) }
        }
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: Capsule()).shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }
}

/// The board as a PNG for the share sheet, rendered only when the user shares.
struct BoardPNG: Transferable {
    let board: BoardModel
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            await MainActor.run { item.board.renderPNG() ?? Data() }
        }
    }
}
