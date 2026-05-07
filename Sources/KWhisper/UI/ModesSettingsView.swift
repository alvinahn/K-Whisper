import SwiftUI

struct ModesSettingsView: View {
    @ObservedObject private var manager = ModeManager.shared
    @State private var selectedId: String?
    @State private var draft: Mode?

    var body: some View {
        // Plain HStack instead of HSplitView so it composes cleanly inside the
        // outer NavigationSplitView (HSplitView confuses the navigation column model).
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selectedId) {
                    ForEach(manager.modes) { mode in
                        HStack(spacing: 6) {
                            Text(mode.name)
                                .lineLimit(1)
                            if mode.isBuiltIn {
                                Text("built-in")
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.gray.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                            Spacer()
                        }
                        .tag(mode.id as String?)
                    }
                }
                .listStyle(.inset)

                Divider()

                HStack(spacing: 4) {
                    Button { addNew() } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .help("Add a new mode")
                    Button { delete() } label: { Image(systemName: "minus") }
                        .buttonStyle(.borderless)
                        .disabled(!canDelete)
                        .help("Delete the selected mode")
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(width: 220)

            Divider()

            Group {
                if let draft = draft {
                    ModeEditor(mode: draft) { updated in
                        manager.upsert(updated)
                        self.draft = updated
                    }
                    // Force a fresh editor instance per mode so its internal @State
                    // (the editable Mode copy) re-initializes from the new selection.
                    // Without this, SwiftUI reuses the old @State and the form looks
                    // frozen on the previously selected mode.
                    .id(draft.id)
                } else {
                    Text("Select a mode to edit, or click + to create a new one.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: selectedId) { _, id in
            draft = id.flatMap { manager.mode(id: $0) }
        }
    }

    private var canDelete: Bool {
        guard let id = selectedId, let m = manager.mode(id: id) else { return false }
        return !m.isBuiltIn
    }

    private func addNew() {
        let newMode = Mode(
            id: Mode.makeUserId(),
            name: "New mode",
            systemPrompt: "Rewrite the transcript clearly. Match the language of the input. Output ONLY the result.",
            provider: .gemini,
            model: DefaultModels.geminiFlash,
            temperature: 0.3,
            maxTokens: 1024,
            isBuiltIn: false
        )
        manager.upsert(newMode)
        selectedId = newMode.id
    }

    private func delete() {
        if let id = selectedId { manager.delete(id: id); selectedId = nil; draft = nil }
    }
}

private struct ModeEditor: View {
    @State var mode: Mode
    let onSave: (Mode) -> Void

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $mode.name).disabled(mode.isBuiltIn && mode.id != "")
                Text("ID: \(mode.id)").font(.caption).foregroundStyle(.secondary)
            }
            Section("Provider") {
                Picker("Provider", selection: $mode.provider) {
                    ForEach(LLMProviderKind.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                if mode.provider != .none {
                    TextField("Model", text: $mode.model)
                    HStack {
                        Text("Temperature")
                        Slider(value: $mode.temperature, in: 0...1, step: 0.05)
                        Text(String(format: "%.2f", mode.temperature))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 40, alignment: .trailing)
                    }
                    Stepper("Max tokens: \(mode.maxTokens)", value: $mode.maxTokens, in: 64...4096, step: 64)
                }
            }
            Section("System prompt") {
                TextEditor(text: $mode.systemPrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)
                Text("Use {KOREAN_TONE} as a placeholder for the user's default tone setting.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Save changes") { onSave(mode) }
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        .formStyle(.grouped)
    }
}
