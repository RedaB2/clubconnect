import SwiftUI

struct PeopleView: View {
    @Environment(ClubStore.self) private var store
    @Environment(\.brandTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
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

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            List(selection: $selectedID) {
                Section {
                    if typeSize.isAccessibilitySize {
                        filterPicker.pickerStyle(.menu)
                    } else {
                        filterPicker.pickerStyle(.segmented)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                let people = matches
                if people.isEmpty {
                    ContentUnavailableView {
                        Label("No members found", systemImage: "person.2")
                    } description: {
                        Text(query.isEmpty ? "No members match this group yet." : "Try another name, major, or interest.")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    let groups = Dictionary(grouping: people) { $0.effectiveKind() }
                    membersSection("Students", members: groups[.student] ?? [])
                    membersSection("Alumni", members: groups[.alumni] ?? [])
                    membersSection("Members", members: groups[nil] ?? [])
                }
            }
            .listStyle(.insetGrouped)
            .brandListBackground()
            .refreshable { await store.refresh() }
            .navigationTitle("People")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement: .topBarLeading) { ActiveClubMenu() } }
            .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 520)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name, major, or interest")
        } detail: {
            if let selectedID, let member = store.members.first(where: { $0.id == selectedID }) {
                MemberProfile(member: member) {
                    if member.id != store.me.id {
                        Section { MessageMemberButton(member: member) }.listRowBackground(theme.surface)
                    }
                }
                .navigationTitle("Member profile")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Member profiles", systemImage: "person.crop.rectangle.stack", description: Text("Choose someone from the directory."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.canvas)
            }
        }
    }

    private var filterPicker: some View {
        Picker("Member type", selection: $filter) {
            ForEach(DirectoryFilter.allCases, id: \.self) { item in
                Text(item.rawValue).tag(item)
            }
        }
    }

    @ViewBuilder
    private func membersSection(_ title: LocalizedStringKey, members: [Member]) -> some View {
        if !members.isEmpty {
            Section {
                ForEach(members) { member in
                    NavigationLink(value: member.id) {
                        DirectoryPersonRow(member: member, showsInterests: true)
                    }
                    .listRowBackground(selectedID == member.id ? theme.wash : theme.surface)
                    .accessibilityIdentifier("member-" + member.id)
                }
            } header: {
                SocialSectionHeading(title: title, count: members.count)
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

struct SocialSectionHeading: View {
    @Environment(\.brandTheme) private var theme
    let title: LocalizedStringKey
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(.title3, design: .serif, weight: .semibold))
            Text(count, format: .number)
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(theme.ink.opacity(0.68))
        }
        .textCase(nil)
        .foregroundStyle(theme.ink)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct DirectoryPersonRow: View {
    @Environment(\.brandTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    let member: Member
    var showsInterests = false

    private var academicLine: String {
        let relationship: String
        switch member.effectiveKind() {
        case .student: relationship = member.classStanding?.title ?? "Student"
        case .alumni: relationship = member.graduationYear.map { "Class of \($0)" } ?? "Alumni"
        case nil: relationship = ""
        }
        return [member.major, relationship].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 13) {
            MemberPortrait(name: member.name, imageData: member.photoData, diameter: showsInterests ? 54 : 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(member.name)
                    .font(.headline)
                    .foregroundStyle(theme.ink)
                if !academicLine.isEmpty {
                    Text(academicLine)
                        .font(.subheadline)
                        .foregroundStyle(theme.ink.opacity(0.8))
                }
                if showsInterests && !member.interests.isEmpty {
                    Text(member.interests.prefix(2).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .padding(.vertical, showsInterests ? 6 : 4)
        .accessibilityElement(children: .combine)
    }
}

extension MemberKind {
    var communityTitle: String { self == .student ? "Student" : "Alumni" }
}
