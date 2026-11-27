import SwiftUI

struct EventCheckInView: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var manualCode = ""
    @State private var scanning = false
    @State private var submitting = false
    @State private var result: ResultMessage?
    @FocusState private var codeFocused: Bool
    let event: ClubEvent

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(event.title).font(.system(.title2, design: .serif, weight: .semibold))
                    Label(event.location, systemImage: "mappin")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section {
                    Button { scanning = true } label: {
                        Label("Scan ticket", systemImage: "qrcode.viewfinder")
                    }
                    .disabled(submitting)
                }
                Section("Enter a ticket code") {
                    TextField("Ticket code", text: $manualCode)
                        .textContentType(.none)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($codeFocused)
                        .submitLabel(.go)
                        .onSubmit { Task { await checkIn(manualCode) } }
                    Button { Task { await checkIn(manualCode) } } label: {
                        if submitting {
                            ProgressView()
                        } else {
                            Label("Check in member", systemImage: "person.badge.clock")
                        }
                    }
                    .disabled(submitting || manualCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let result {
                    Section {
                        Label(result.text, systemImage: result.success ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .accessibilityAddTraits(.isStaticText)
                    }
                }
            }
            .disabled(!store.isAdmin)
            .navigationTitle("Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $scanning) {
                EventScannerSheet { payload in
                    if let code = TicketBarcode.code(in: payload, for: event.id) {
                        Task { await checkIn(code) }
                    } else if payload.count <= 128, !payload.isEmpty,
                              payload.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) {
                        // Wallet passes carry the raw opaque ticket code.
                        Task { await checkIn(payload) }
                    } else {
                        result = ResultMessage(text: "This QR code is not a ticket for this event.", success: false)
                    }
                }
            }
        }
    }

    @MainActor private func checkIn(_ entry: String) async {
        let code = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard store.isAdmin, !submitting, !code.isEmpty else { return }
        submitting = true
        result = nil
        codeFocused = false
        defer { submitting = false }
        do {
            let name = try await store.checkIn(eventID: event.id, code: code)
            result = ResultMessage(text: "\(name) is checked in.", success: true)
            manualCode = ""
        } catch {
            result = ResultMessage(text: error.localizedDescription, success: false)
        }
        if let result {
            UIAccessibility.post(notification: .announcement, argument: result.text)
        }
    }

    private struct ResultMessage {
        let text: String
        let success: Bool
    }
}
