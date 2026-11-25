import Foundation

/// Problems the app can explain to the person in plain words.
enum DiaryError: LocalizedError, Equatable {
    case inviteNotFound
    case familyFull
    case alreadyInFamily
    case notSignedIn

    /// Maps the short error words raised by the database functions.
    init?(serverMessage: String) {
        switch serverMessage {
        case "invite_not_found": self = .inviteNotFound
        case "family_full": self = .familyFull
        case "already_in_family": self = .alreadyInFamily
        case "not_signed_in": self = .notSignedIn
        default: return nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .inviteNotFound: "That code does not match any pet. Check it with the other parent."
        case .familyFull: "This pet already has two parents, so the code no longer works."
        case .alreadyInFamily: "This phone is already part of a pet's family."
        case .notSignedIn: "The app could not sign in. Close it and open it again."
        }
    }
}
