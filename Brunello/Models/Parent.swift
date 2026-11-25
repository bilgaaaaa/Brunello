import Foundation

/// One of the two people looking after the pet. `nickname` is what the pet calls them in notifications.
struct Parent: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let petID: UUID
    let userID: UUID
    var name: String
    var nickname: String

    enum CodingKeys: String, CodingKey {
        case id, name, nickname
        case petID = "pet_id"
        case userID = "user_id"
    }
}
