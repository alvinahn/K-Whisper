import SwiftUI
import AppKit

struct HistoryView: View {
    @ObservedObject private var store = HistoryStore.shared
    @State private var selection: HistoryEntry.ID?
    @State private var query: String = ""

    var filtered: [HistoryEntry] {
        guard !query.isEmpty else { return store.entries }
        let q = query.lowercased()
        return store.entries.filter {
            $0.processedText.lowercased().contains(q)
            || $0.rawTranscript.lowercased().contains(q)
            || $0.modeName.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search…", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button(role: .destructive) { store.clear() } label: { Text("Clear all") }
                    .disabled(store.entries.isEmpty)
            }
            .padding(.bottom, 8)

            HSplitView {
                List(selection: $selection) {
                    ForEach(filtered) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.processedText.isEmpty ? entry.rawTranscript : entry.processedText)
                                .lineLimit(2)
                            HStack {
                                Text(entry.modeName).font(.caption2).foregroundStyle(.secondary)
                                Text(entry.language.uppercased()).font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Text(entry.timestamp, style: .relative).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .tag(entry.id as HistoryEntry.ID?)
                    }
                }
                .frame(minWidth: 280)

                if let sel = selection, let entry = store.entries.first(where: { $0.id == sel }) {
                    detail(entry)
                } else {
                    Text("Select an entry").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func detail(_ entry: HistoryEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                    .font(.caption).foregroundStyle(.secondary)

                GroupBox("Output (\(entry.modeName))") {
                    HStack {
                        Text(entry.processedText).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.processedText, forType: .string)
                        } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.plain)
                    }.padding(8)
                }

                GroupBox("Raw transcript") {
                    Text(entry.rawTranscript).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            }
            .padding(12)
        }
    }
}
