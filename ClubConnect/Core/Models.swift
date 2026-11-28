import Foundation

struct Club: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var fullName: String
    var about: String
    var accentHex: String
    static let defaultPrimaryHex = "#80523F"
    static let defaultSecondaryHex = "#F0E4D9"
    // Older on-device sample snapshots predate the second palette color.
    var secondaryHex: String?
    var logoData: Data? = nil
}

enum MemberKind: String, CaseIterable, Codable, Hashable {
    case student, alumni
}

enum GraduationTerm: String, CaseIterable, Codable {
    case spring, fall
    var title: String { rawValue.capitalized }

    static let campusCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    static var validYears: ClosedRange<Int> {
        1900...(campusCalendar.component(.year, from: .now) + 12)
    }

    static let cutoffDescription = "Your profile changes to Alumni on June 1 after a spring graduation or January 1 after a fall graduation, in Los Angeles time."

    func kind(year: Int, at date: Date = .now) -> MemberKind {
        let current = Self.campusCalendar.dateComponents([.year, .month], from: date)
        let campusYear = current.year ?? year
        if campusYear != year { return campusYear > year ? .alumni : .student }
        return self == .spring && (current.month ?? 1) >= 6 ? .alumni : .student
    }
}

enum ClassStanding: String, CaseIterable, Codable {
    case freshman, sophomore, junior, senior, graduate
    var title: String { self == .graduate ? "Graduate student" : rawValue.capitalized }
}

struct Member: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    // Kept for decoding older snapshots. Current membership comes from graduation.
    var kind: MemberKind
    var major = ""
    var interests: [String] = []
    var experience = ""
    var bio = ""
    var photoData: Data? = nil
    var graduationTerm: GraduationTerm? = nil
    var graduationYear: Int? = nil
    var classStanding: ClassStanding? = nil

    var graduationLabel: String? {
        guard let graduationTerm, let graduationYear else { return nil }
        return "\(graduationTerm.title) \(graduationYear)"
    }

    func effectiveKind(at date: Date = .now) -> MemberKind? {
        guard let graduationTerm, let graduationYear else { return nil }
        return graduationTerm.kind(year: graduationYear, at: date)
    }

    func hasCompleteAcademicProfile(at date: Date = .now) -> Bool {
        guard let kind = effectiveKind(at: date) else { return false }
        return kind == .alumni || classStanding != nil
    }
}

struct ClubEvent: Identifiable, Codable, Hashable {
    var id = UUID().uuidString.lowercased()
    var title: String
    var summary: String
    var location: String
    var startsAt: Date
    var endsAt: Date
    var category: String
}

struct EventTicket: Identifiable, Codable, Hashable {
    var id: String
    var eventID: String
    var code: String
    var checkedIn: Bool
}

struct CommunityState: Codable {
    var club: Club
    var members: [Member]
    var events: [ClubEvent]
    var tickets: [EventTicket]
    var myID: String
    var isAdmin: Bool

    static let pilot = Club(id: "menasa", name: "MENASA",
        fullName: "Middle Eastern and North African Association",
        about: "A campus community for Middle Eastern and North African students, alumni, and friends. Pull up a chair for coffee, conversation, and a little taste of home.",
        accentHex: "#974A30", secondaryHex: "#31675D")

    static func sample(now: Date = .now) -> Self {
        let campusYear = GraduationTerm.campusCalendar.component(.year, from: now)
        let me = Member(id: "demo-organizer", name: "Noor Haddad", kind: .student,
                        major: "Architecture", interests: ["Design", "Film", "Arabic coffee"],
                        experience: "Events coordinator at MENASA", bio: "Usually sketching something between classes.",
                        graduationTerm: .spring, graduationYear: campusYear + 2, classStanding: .junior)
        let people = [
            me,
            Member(id: "demo-yasmin", name: "Yasmin Mansour", kind: .alumni, major: "Computer Science", interests: ["Mentorship", "Music"], experience: "Software engineer", bio: "Happy to talk about the first year after graduation.", graduationTerm: .spring, graduationYear: campusYear - 1),
            Member(id: "demo-omar", name: "Omar Benali", kind: .student, major: "Film Studies", interests: ["Cinema", "Photography"], bio: "Planning our next film night.", graduationTerm: .fall, graduationYear: campusYear + 1, classStanding: .senior),
            Member(id: "demo-lina", name: "Lina Khoury", kind: .student, major: "Public Health", interests: ["Food", "Community gardens"], graduationTerm: .spring, graduationYear: campusYear + 3, classStanding: .sophomore),
            Member(id: "demo-samir", name: "Samir Osman", kind: .alumni, major: "Mechanical Engineering", interests: ["Robotics", "Cycling"], experience: "Product design engineer", graduationTerm: .fall, graduationYear: campusYear - 4)
        ].map { member in
            var sample = member
            if let url = Bundle.main.url(forResource: member.id, withExtension: "jpg") {
                sample.photoData = try? Data(contentsOf: url)
            }
            return sample
        }
        let calendar = Calendar.current
        func event(_ id: String, _ days: Int, _ hour: Int, _ title: String, _ summary: String, _ place: String, _ category: String) -> ClubEvent {
            let day = calendar.date(byAdding: .day, value: days, to: now) ?? now
            let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
            return ClubEvent(id: id, title: title, summary: summary, location: place, startsAt: start, endsAt: start.addingTimeInterval(5400), category: category)
        }
        return Self(club: pilot, members: people, events: [
            event("a1000000-0000-4000-8000-000000000001", 2, 16, "Coffee at the Majlis", "Join us around the table for Arabic coffee, mint tea, and a few rounds of backgammon. Bring a friend or come on your own.", "Student Union · Courtyard", "Social"),
            event("a1000000-0000-4000-8000-000000000002", 6, 18, "After graduation", "Meet MENASA alumni for a small-group conversation about finding your first role and building a community beyond campus.", "Alumni Hall · Room 204", "Alumni"),
            event("a1000000-0000-4000-8000-000000000003", 10, 19, "Cinema after dark", "An evening of short films from across the region, followed by a student-led discussion.", "Campus Cinema", "Culture")
        ], tickets: [], myID: me.id, isAdmin: true)
    }
}

struct ClubFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
