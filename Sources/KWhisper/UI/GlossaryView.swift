import SwiftUI

struct GlossaryView: View {
    @ObservedObject private var store = GlossaryStore.shared
    @State private var newCanonical: String = ""
    @State private var newAliases: String = ""
    @State private var editingCanonical: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("음성 인식이 자주 틀리는 이름이나 용어를 보정합니다. 올바른 표기는 인식 힌트로 보내고, 잘못 인식한 표현을 등록하면 모든 모드에서 자동으로 바꿉니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("올바른 표기")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("예: 결제 API, 고객센터, 프로젝트 알파", text: $newCanonical)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { saveEntry() }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("잘못 인식한 표현 (선택)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("예: 결재 API, 고객 센타", text: $newAliases)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { saveEntry() }
                    }
                    VStack(alignment: .trailing, spacing: 3) {
                        Spacer().frame(height: 13)  // align with text field
                        HStack(spacing: 6) {
                            if editingCanonical != nil {
                                Button("취소", action: cancelEditing)
                            }
                            Button(editingCanonical == nil ? "추가" : "저장", action: saveEntry)
                                .disabled(canonicalTrimmed.isEmpty)
                        }
                        .frame(minWidth: editingCanonical == nil ? 52 : 108, alignment: .trailing)
                    }
                }
            }

            Divider()

            List {
                ForEach(store.parsedEntries(), id: \.canonical) { entry in
                    entryRow(entry)
                        .padding(.vertical, 4)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
    }

    @ViewBuilder
    private func entryRow(_ entry: GlossaryStore.ParsedEntry) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.canonical)
                    .font(.system(size: 13, weight: .medium))
                if entry.aliases.isEmpty {
                    Text("힌트로만 사용 중")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                } else {
                    FlowingChips(items: entry.aliases)
                }
            }
            Spacer(minLength: 6)
            Button {
                startEditing(entry)
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("수정")
            Button(role: .destructive) {
                remove(canonical: entry.canonical)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            startEditing(entry)
        }
    }

    private var canonicalTrimmed: String {
        newCanonical.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveEntry() {
        let canonical = canonicalTrimmed
        guard !canonical.isEmpty else { return }

        let aliases = newAliases
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != canonical }
            .uniqued()

        let line: String = aliases.isEmpty
            ? canonical
            : "\(canonical)|\(aliases.joined(separator: ","))"

        if let editingCanonical {
            var updated = store.terms
            if editingCanonical != canonical {
                updated.removeAll { canonicalOf($0) == canonical }
            }
            if let idx = updated.firstIndex(where: { canonicalOf($0) == editingCanonical }) {
                updated[idx] = line
            } else {
                updated.append(line)
            }
            store.terms = updated
        } else if let idx = store.terms.firstIndex(where: { canonicalOf($0) == canonical }) {
            store.terms[idx] = line
        } else {
            store.terms.append(line)
        }

        cancelEditing()
    }

    private func remove(canonical: String) {
        store.terms.removeAll { canonicalOf($0) == canonical }
        if editingCanonical == canonical {
            cancelEditing()
        }
    }

    private func startEditing(_ entry: GlossaryStore.ParsedEntry) {
        editingCanonical = entry.canonical
        newCanonical = entry.canonical
        newAliases = entry.aliases.joined(separator: ", ")
    }

    private func cancelEditing() {
        editingCanonical = nil
        newCanonical = ""
        newAliases = ""
    }

    private func canonicalOf(_ rawLine: String) -> String {
        rawLine
            .split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? ""
    }
}

// MARK: - Chip layout

/// Wraps chips to multiple lines as the parent width changes. Lightweight
/// home-grown flow layout — avoids pulling in a third-party Layout protocol implementation.
private struct FlowingChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 10))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.secondary.opacity(0.18))
                    )
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
        }
        return CGSize(width: totalWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        let maxX = bounds.maxX

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
