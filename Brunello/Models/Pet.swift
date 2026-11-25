import Foundation

/// The dog or cat the two parents look after together.
struct Pet: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var species: Species
    var photoPath: String?
    var currencyCode: String
    let inviteCode: String

    enum CodingKeys: String, CodingKey {
        case id, name, species
        case photoPath = "photo_path"
        case currencyCode = "currency_code"
        case inviteCode = "invite_code"
    }
}

/// Kind of pet; decides the avatar and which entry kinds are offered.
enum Species: String, Codable, CaseIterable, Identifiable, Sendable {
    case dog, cat

    /// How many of `kinds` are counted in the day summary (the first ones).
    static let summaryKindCount = 4

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .dog: "🐶"
        case .cat: "🐱"
        }
    }

    var label: String {
        switch self {
        case .dog: "Dog"
        case .cat: "Cat"
        }
    }

    /// Entry kinds offered on the Today screen, in display order.
    var kinds: [EntryKind] {
        switch self {
        case .dog: [.food, .poo, .pee, .walk, .health, .photo]
        case .cat: [.food, .poo, .pee, .play, .health, .photo]
        }
    }
}
