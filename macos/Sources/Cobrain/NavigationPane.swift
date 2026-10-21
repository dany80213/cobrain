import SwiftUI

/// Headings list like WordCraft's Navigation pane.
struct NavigationPane: View {
    @ObservedObject var model: DocumentModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Navigation").font(.title3.weight(.semibold))
            HStack {
                Text("Headings").padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                Text("Pages").foregroundStyle(.secondary).padding(.horizontal, 6)
                Text("Results").foregroundStyle(.secondary).padding(.horizontal, 6)
            }.font(.system(size: 12))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.headings) { h in
                        Text(h.text)
                            .font(.system(size: 13, weight: h.level == 1 ? .semibold : .regular))
                            .padding(.leading, CGFloat(max(0, h.level - 1)) * 14)
                            .lineLimit(2)
                    }
                    if model.headings.isEmpty {
                        Text("Headings you add to the document appear here.").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(width: 240)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
