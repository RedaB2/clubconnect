import SwiftUI

struct EventEditorView: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ClubEvent
    @State private var saving = false
    @State private var errorText: String?
    private let isNew: Bool
    let onSave: (String) -> Void

    init(event: ClubEvent?, onSave: @escaping (String) -> Void = { _ in }) {
        let start = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        _draft = State(initialValue: event ?? ClubEvent(
            title: "", summary: "", location: "", startsAt: start,
            endsAt: start.addingTimeInterval(3_600), category: "General"
        ))
        isNew = event == nil
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Event title", text: $draft.title)
                        .accessibilityLabel("Event title")
                    TextField("Location", text: $draft.location)
                        .accessibilityLabel("Location")
                    TextField("Category", text: $draft.category)
                        .accessibilityLabel("Category")
                }
                Section("When") {
                    DatePicker("Starts", selection: $draft.startsAt)
                        .onChange(of: draft.startsAt) { oldStart, newStart in
                            if newStart >= draft.endsAt {
                                draft.endsAt = newStart.addingTimeInterval(max(3_600, draft.endsAt.timeIntervalSince(oldStart)))
                            }
                        }
                    DatePicker("Ends", selection: $draft.endsAt, in: draft.startsAt...)
                    if draft.endsAt <= draft.startsAt {
                        Text("Choose an end time after the start.").foregroundStyle(.secondary)
                    }
                }
                Section("About this event") {
                    TextField("What should members know?", text: $draft.summary, axis: .vertical)
                        .lineLimit(3...9)
                        .accessibilityLabel("Event description")
                }
                if let fieldProblem {
                    Section {
                        Label(fieldProblem, systemImage: "exclamationmark.circle")
                    }
                }
            }
            .disabled(saving)
            .navigationTitle(isNew ? "New event" : "Edit event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Publish" : "Save") { Task { await save() } }
                        .disabled(!valid || saving || !store.isAdmin)
                }
            }
            .interactiveDismissDisabled(saving)
            .alert("Couldn’t save event", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorText ?? "") }
        }
    }

    private var fieldProblem: String? {
        if draft.title.eventTextLength > 160 { return "Use 160 characters or fewer for the title." }
        if draft.location.eventTextLength > 300 { return "Use 300 characters or fewer for the location." }
        if draft.category.eventTextLength > 80 { return "Use 80 characters or fewer for the category." }
        if draft.summary.eventTextLength > 6_000 { return "Use 6,000 characters or fewer for the description." }
        return nil
    }

    private var valid: Bool {
        fieldProblem == nil &&
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        draft.endsAt > draft.startsAt && (!isNew || draft.endsAt > .now)
    }

    @MainActor private func save() async {
        guard valid, store.isAdmin, !saving else { return }
        saving = true
        defer { saving = false }
        var event = draft
        event.title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.summary = event.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        event.location = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = event.category.trimmingCharacters(in: .whitespacesAndNewlines)
        event.category = category.isEmpty ? "General" : category
        do {
            try await store.saveEvent(event)
            dismiss()
            onSave(event.id)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private extension String {
    var eventTextLength: Int {
        trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
    }
}
