import SwiftUI

struct PeopleView: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var filter = DirectoryFilter.everyone
    @State private var query = ""
    @State private var selectedID: String?
    @State private var compactColumn = NavigationSplitViewColumn.sidebar

    private var matches: [Member] {
        let words = query.communityTrimmed.split(whereSeparator: \.isWhitespace)
        return store.members.filter { member in
            guard filter.matches(member.effectiveKind()) else { return false }
            let fields = [member.name, member.major] + member.interests
            return words.allSatisfy { word in
                fields.contains { $0.localizedStandardContains(String(word)) }
            }
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var filterPicker: some View {
        Picker("Member type", selection: $filter) {
            ForEach(DirectoryFilter.allCases, id: \.self) { item in
                Text(item.rawValue).tag(item)
            }
        }
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            List(selection: $selectedID) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        filterPicker.pickerStyle(.menu)
                    } else {
                        filterPicker.pickerStyle(.segmented)
                    }
                }
                .listRowSeparator(.hidden)
                .padding(.vertical, 5)

                if matches.isEmpty {
                    ContentUnavailableView {
                        Label("No members found", systemImage: "person.2")
                    } description: {
                        Text(query.isEmpty ? "Members will appear here when they join." : "Try another name, major, or interest.")
                    }
                    .listRowSeparator(.hidden)
                } else {
                    Section {
                        ForEach(matches) { member in
                            NavigationLink(value: member.id) {
                                MemberRow(member: member)
                            }
                            .accessibilityIdentifier("member-\(member.id)")
                        }
                    } header: {
                        Text("\(matches.count) \(matches.count == 1 ? "member" : "members")")
                            .font(.footnote.weight(.semibold))
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .brandListBackground()
            .refreshable { await store.refresh() }
            .navigationTitle("People")
            .toolbar { ToolbarItem(placement: .topBarLeading) { ActiveClubMenu() } }
            .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 500)
            .searchable(text: $query, prompt: "Name, major, or interest")
        } detail: {
            if let selectedID, let member = store.members.first(where: { $0.id == selectedID }) {
                MemberProfile(member: member) {
                    if member.id != store.me.id {
                        Section { MessageMemberButton(member: member) }
                    }
                }
                    .navigationTitle("Member profile")
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Member profiles", systemImage: "person.crop.rectangle.stack", description: Text("Choose someone from the directory."))
            }
        }
    }
}

private enum DirectoryFilter: String, CaseIterable {
    case everyone = "Everyone"
    case students = "Students"
    case alumni = "Alumni"

    func matches(_ kind: MemberKind?) -> Bool {
        switch self {
        case .everyone: true
        case .students: kind == .student
        case .alumni: kind == .alumni
        }
    }
}

private struct MemberRow: View {
    let member: Member

    var body: some View {
        HStack(spacing: 14) {
            MemberPortrait(name: member.name, imageData: member.photoData, diameter: 49)
            VStack(alignment: .leading, spacing: 4) {
                Text(member.name)
                    .font(.headline)
                Text([member.effectiveKind()?.communityTitle ?? "Graduation term needed", member.major].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .combine)
    }
}

extension MemberKind {
    var communityTitle: String { self == .student ? "Student" : "Alumni" }
}
