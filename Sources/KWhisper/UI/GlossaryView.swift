import SwiftUI

struct GlossaryView: View {
    @ObservedObject private var store = GlossaryStore.shared
    @State private var newTerm: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add proper nouns, names, brand terms, and technical jargon. They get injected into Whisper's bias prompt and into post-processing prompts to preserve correct spelling.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("e.g. BoundX, Junho, Navio", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add() }
                Button("Add", action: add)
                    .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            List {
                ForEach(store.terms, id: \.self) { term in
                    HStack {
                        Text(term)
                        Spacer()
                        Button(role: .destructive) {
                            store.terms.removeAll { $0 == term }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
    }

    private func add() {
        let trimmed = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !store.terms.contains(trimmed) else { return }
        store.terms.append(trimmed)
        newTerm = ""
    }
}
