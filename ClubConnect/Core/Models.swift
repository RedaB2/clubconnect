import Foundation
import SwiftUI

struct Club: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var fullName: String
    var about: String
    var accentHex: String
    static let defaultSecondaryHex = "#31675D"
    // Older on-device sample snapshots predate the second palette color.
    var secondaryHex: String?
    var logoData: Data? = nil

    private func rgb(_ hex: String) -> [Double] {
        let value = Int(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x974A30
        return [16, 8, 0].map { Double((value >> $0) & 255) / 255 }
    }

    private func color(_ hex: String) -> Color {
        let channels = rgb(hex)
        return Color(red: channels[0], green: channels[1], blue: channels[2])
    }

    var brandColor: Color { color(accentHex) }
    var secondaryBrandColor: Color { color(secondaryHex ?? Self.defaultSecondaryHex) }

    var accent: Color {
        let channels = rgb(accentHex)
        return Color(uiColor: UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            let backgroundLuminance = dark ? 0.026 : 0.91
            let required = traits.accessibilityContrast == .high ? 7.0 : 4.5
            var mix = 0.0
            var adjusted = channels
            // Keep the original hue, darkening or lightening only when the club
            // color needs more contrast against system grouped backgrounds.
            while mix < 1 {
                let linear = adjusted.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
                let ink = linear[0]*0.2126 + linear[1]*0.7152 + linear[2]*0.0722
                let ratio = (max(ink, backgroundLuminance) + 0.05) / (min(ink, backgroundLuminance) + 0.05)
                if ratio >= required { break }
                mix = min(1, mix + 0.02)
                adjusted = channels.map { $0 * (1 - mix) + (dark ? mix : 0) }
            }
            return UIColor(red: adjusted[0], green: adjusted[1], blue: adjusted[2], alpha: 1)
        })
    }
}

enum MemberKind: String, CaseIterable, Codable, Hashable {
    case student, alumni
}

struct Member: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var kind: MemberKind
    var major = ""
    var interests: [String] = []
    var experience = ""
    var bio = ""
    var photoData: Data? = nil
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
        accentHex: "#974A30")

    static func sample(now: Date = .now) -> Self {
        let me = Member(id: "demo-organizer", name: "Noor Haddad", kind: .student,
                        major: "Architecture", interests: ["Design", "Film", "Arabic coffee"],
                        experience: "Events coordinator at MENASA", bio: "Usually sketching something between classes.")
        let people = [
            me,
            Member(id: "demo-yasmin", name: "Yasmin Mansour", kind: .alumni, major: "Computer Science", interests: ["Mentorship", "Music"], experience: "Software engineer", bio: "Happy to talk about the first year after graduation."),
            Member(id: "demo-omar", name: "Omar Benali", kind: .student, major: "Film Studies", interests: ["Cinema", "Photography"], bio: "Planning our next film night."),
            Member(id: "demo-lina", name: "Lina Khoury", kind: .student, major: "Public Health", interests: ["Food", "Community gardens"]),
            Member(id: "demo-samir", name: "Samir Osman", kind: .alumni, major: "Mechanical Engineering", interests: ["Robotics", "Cycling"], experience: "Product design engineer")
        ]
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
