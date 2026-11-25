import Foundation

/// Rules for the short texts people type: names stay short and letters-only, so they cannot become a chat.
enum NameRules {
    static let parentNameLimit = 12
    static let petNameLimit = 20
    static let inviteCodeLength = 6
    static let nicknameIdeas = ["Mama", "Mommy", "Papà", "Daddy"]

    /// Trims spaces and joins accents to their letters, so the length matches what the server counts.
    static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    /// A parent's name or nickname: starts with a letter, then letters, spaces, apostrophes or hyphens.
    static func isValidParentName(_ text: String) -> Bool {
        let cleaned = clean(text)
        guard (1...parentNameLimit).contains(cleaned.unicodeScalars.count), cleaned.first?.isLetter == true else { return false }
        return cleaned.allSatisfy { $0.isLetter || $0 == " " || $0 == "'" || $0 == "-" }
    }

    static func isValidPetName(_ text: String) -> Bool {
        (1...petNameLimit).contains(clean(text).unicodeScalars.count)
    }

    /// Invite codes are six letters or digits; spaces and dashes typed by the person are ignored.
    static func cleanInviteCode(_ text: String) -> String {
        String(text.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    static func isValidInviteCode(_ text: String) -> Bool {
        cleanInviteCode(text).count == inviteCodeLength
    }
}
