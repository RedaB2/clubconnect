import SwiftUI

struct ClubView: View {
    @Environment(ClubStore.self) private var store
    @State private var editing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ClubIdentity(club: store.club)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                if !store.club.about.isEmpty {
                    Section("About the club") {
                        Text(store.club.about)
                            .padding(.vertical, 4)
                            .textSelection(.enabled)
                    }
                }
                Section("Community") {
                    LabeledContent {
                        Text("\(store.members.filter { $0.kind == .student }.count)").monospacedDigit()
                    } label: {
                        Label("Students", systemImage: "book")
                    }
                    LabeledContent {
                        Text("\(store.members.filter { $0.kind == .alumni }.count)").monospacedDigit()
                    } label: {
                        Label("Alumni", systemImage: "graduationcap")
                    }
                    ShareLink(item: store.inviteURL, subject: Text("Join \(store.club.name)"), message: Text("Join \(store.club.name) on Club Connect.")) {
                        Label("Invite a friend", systemImage: "person.badge.plus")
                    }
                    .accessibilityIdentifier("share-club-invite")
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await store.refresh() }
            .navigationTitle("Club")
            .toolbar {
                if store.isAdmin {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Edit") { editing = true }
                            .accessibilityLabel("Edit club")
                    }
                }
            }
            .sheet(isPresented: $editing) {
                ClubEditor(club: store.club)
            }
        }
    }
}

private struct ClubIdentity: View {
    let club: Club

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            CommunityMark(logoData: club.logoData, side: 60)
                .padding(8)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 4) {
                Text(club.name)
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                if !club.fullName.isEmpty && club.name != club.fullName {
                    Text(club.fullName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(alignment: .topTrailing) {
            ZStack {
                ClubPattern(rotation: 0).stroke(club.brandColor.opacity(0.32), lineWidth: 1.3)
                ClubPattern(rotation: .pi / 4).stroke(club.secondaryBrandColor.opacity(0.55), lineWidth: 1.3)
            }
            .frame(width: 190, height: 120)
            .accessibilityHidden(true)
        }
        .background(club.brandColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 19))
    }
}

private struct ClubPattern: Shape {
    let rotation: Double

    func path(in rect: CGRect) -> Path {
        var result = Path()
        let spacing = rect.width / 3
        for row in -1...1 {
            for column in 0...3 {
                let center = CGPoint(x: CGFloat(column) * spacing + spacing / 2,
                                     y: CGFloat(row) * spacing + spacing / 3)
                for vertex in 0..<4 {
                    let angle = rotation + Double(vertex) * .pi / 2
                    let point = CGPoint(x: center.x + cos(angle) * spacing * 0.52,
                                        y: center.y + sin(angle) * spacing * 0.52)
                    if vertex == 0 { result.move(to: point) } else { result.addLine(to: point) }
                }
                result.closeSubpath()
            }
        }
        return result
    }
}

private struct ClubEditor: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Club
    @State private var loadingImage = false
    @State private var saving = false
    @State private var problem: String?

    init(club: Club) { _draft = State(initialValue: club) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    AdaptivePhotoRow {
                        CommunityMark(logoData: draft.logoData, side: 60)
                        CommunityPhotoPicker(label: "Choose logo", removalLabel: "Remove logo", data: $draft.logoData, isLoading: $loadingImage, preservesTransparency: true)
                    }
                    .padding(.vertical, 4)
                    LabeledContent("Short name") {
                        TextField("Short name", text: $draft.name)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                    }
                    TextField("Full name", text: $draft.fullName, axis: .vertical)
                        .textInputAutocapitalization(.words)
                }
                Section("Club palette") {
                    palettePicker("Primary color", hex: draft.accentHex, color: draft.brandColor) { draft.accentHex = $0 }
                    palettePicker("Secondary color", hex: draft.secondaryHex ?? Club.defaultSecondaryHex, color: draft.secondaryBrandColor) { draft.secondaryHex = $0 }
                }
                Section("About the club") {
                    TextField("Describe your club", text: $draft.about, axis: .vertical)
                        .lineLimit(3...10)
                }
                Section("Preview") {
                    ClubIdentity(club: draft)
                        .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Edit club")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(saving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(saving || loadingImage || draft.name.communityTrimmed.isEmpty || draft.fullName.communityTrimmed.isEmpty)
                }
            }
            .interactiveDismissDisabled(saving)
            .alert("Couldn’t save club", isPresented: Binding(
                get: { problem != nil }, set: { if !$0 { problem = nil } }
            )) { Button("OK") {} } message: { Text(problem ?? "") }
        }
    }

    private func palettePicker(_ label: String, hex: String, color: Color,
                               setHex: @escaping (String) -> Void) -> some View {
        ColorPicker(selection: Binding(get: { color }, set: { selected in
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard UIColor(selected).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
            let rgb = [red, green, blue].map { Int((min(1, max(0, $0)) * 255).rounded()) }
            setHex(String(format: "#%02X%02X%02X", rgb[0], rgb[1], rgb[2]))
        }), supportsOpacity: false) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                Text(hex.uppercased()).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        guard !saving else { return }
        var update = draft
        update.name = draft.name.communityTrimmed
        update.fullName = draft.fullName.communityTrimmed
        update.about = draft.about.communityTrimmed
        saving = true
        Task {
            do {
                try await store.saveClub(update)
                dismiss()
            } catch { problem = error.localizedDescription }
            saving = false
        }
    }
}
