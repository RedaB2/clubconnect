import PassKit
import SwiftUI

struct EventTicketView: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.brandTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var cancelling = false
    @State private var loading = false
    @State private var failure: String?
    @State private var walletSheet: WalletSheet?
    let event: ClubEvent

    private var ticket: EventTicket? { store.tickets.first { $0.eventID == event.id } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let ticket {
                    VStack(spacing: 22) {
                        VStack(spacing: 6) {
                            Label(ticket.checkedIn ? "Checked in" : "Going", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(theme.accent)
                            Text(event.title)
                                .font(.system(.title, design: .serif, weight: .semibold))
                                .multilineTextAlignment(.center)
                            Text(event.startsAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                            Text(event.location).font(.subheadline).foregroundStyle(Color.primary.opacity(0.68))
                        }
                        walletAction(ticket)
                        if !ticket.checkedIn {
                            Divider()
                            let payload = TicketBarcode.payload(eventID: event.id, code: ticket.code)
                            if let qr = TicketBarcode.image(payload: payload) {
                                Image(decorative: qr, scale: 1)
                                    .interpolation(.none).resizable().aspectRatio(1, contentMode: .fit)
                                    .frame(maxWidth: 188)
                                    .padding(20)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                                    .accessibilityHidden(true)
                            }
                            VStack(spacing: 5) {
                                Text("Check-in code").font(.caption).foregroundStyle(Color.primary.opacity(0.68))
                                Text(ticket.code)
                                    .font(.system(.title3, design: .monospaced, weight: .semibold))
                                    .accessibilityIdentifier("event-ticket-code")
                                    .textSelection(.enabled)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 460)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 24))
                    .padding()
                    if !ticket.checkedIn, event.endsAt > .now {
                        Button("Cancel RSVP", role: .destructive) { cancelling = true }
                            .padding(.bottom, 12).disabled(loading)
                    }
                } else {
                    ContentUnavailableView("Ticket unavailable", systemImage: "ticket")
                }
            }
            .frame(maxWidth: .infinity)
            .background(theme.canvas)
            .navigationTitle("Your ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Cancel your RSVP?", isPresented: $cancelling, titleVisibility: .visible) {
                Button("Cancel RSVP", role: .destructive) { Task { await cancel() } }
                Button("Keep ticket", role: .cancel) {}
            } message: { Text("Your ticket for this event will be released.") }
            .sheet(item: $walletSheet) { sheet in WalletPassPresenter(controller: sheet.controller) }
            .alert("Ticket update failed", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(failure ?? "") }
        }
    }

    @ViewBuilder private func walletAction(_ ticket: EventTicket) -> some View {
        if ticket.checkedIn {
            walletNote("This ticket has been used. No new Wallet pass is needed.")
        } else if event.endsAt < .now {
            walletNote("This event has ended.")
        } else if !PKAddPassesViewController.canAddPasses() {
            walletNote("To add this ticket to Apple Wallet, open it on a compatible iPhone. You can check in with the code below.")
        } else if !store.walletAvailable {
            walletNote("Sign in with your USC account to add a pass to Apple Wallet. The sample check-in code is available below.")
        } else {
            VStack(spacing: 6) {
                WalletButton { Task { await loadPass() } }
                    .frame(width: 168, height: 50)
                    .disabled(loading)
                    .accessibilityLabel("Add to Apple Wallet")
                    .accessibilityIdentifier("add-ticket-to-wallet")
                if loading {
                    ProgressView("Preparing pass").font(.footnote)
                } else if store.isPreview {
                    Text("This pass is for sample check-in.")
                        .font(.footnote).foregroundStyle(Color.primary.opacity(0.72))
                }
            }
        }
    }

    private func walletNote(_ text: String) -> some View {
        Label(text, systemImage: "wallet.pass")
            .accessibilityIdentifier("wallet-status")
            .font(.footnote)
            .foregroundStyle(Color.primary.opacity(0.72))
            .fixedSize(horizontal: false, vertical: true)
    }

    @MainActor private func cancel() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            try await store.setRSVP(eventID: event.id, attending: false)
            dismiss()
        } catch { failure = error.localizedDescription }
    }

    @MainActor private func loadPass() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let data = try await store.walletPass(eventID: event.id)
            let pass = try PKPass(data: data)
            guard let controller = PKAddPassesViewController(pass: pass) else {
                failure = "Wallet could not open the pass."
                return
            }
            walletSheet = WalletSheet(controller: controller)
        } catch { failure = error.localizedDescription }
    }
}

private struct WalletSheet: Identifiable {
    let id = UUID()
    let controller: PKAddPassesViewController
}

private struct WalletButton: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    let action: () -> Void

    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: colorScheme == .dark ? .blackOutline : .black)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: PKAddPassButton, context: Context) {
        button.addPassButtonStyle = colorScheme == .dark ? .blackOutline : .black
        button.isEnabled = isEnabled
    }
}

private struct WalletPassPresenter: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let controller: PKAddPassesViewController

    final class Coordinator: NSObject, PKAddPassesViewControllerDelegate {
        let dismiss: () -> Void
        init(_ dismiss: @escaping () -> Void) { self.dismiss = dismiss }
        func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) { dismiss() }
    }

    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }
    func makeUIViewController(context: Context) -> PKAddPassesViewController {
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: PKAddPassesViewController, context: Context) {}
}
