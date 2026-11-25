import Foundation

/// One line in the pet's diary.
struct Entry: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let petID: UUID
    let parentID: UUID
    let kind: EntryKind
    let detail: EntryDetail?
    let photoPath: String?
    let occurredAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, detail
        case petID = "pet_id"
        case parentID = "parent_id"
        case photoPath = "photo_path"
        case occurredAt = "occurred_at"
    }
}

/// What the app sends to add an entry; the server fills in the id.
struct NewEntry: Encodable, Sendable {
    let petID: UUID
    let parentID: UUID
    let kind: EntryKind
    var detail: EntryDetail?
    var photoPath: String?
    var occurredAt: Date = .now

    enum CodingKeys: String, CodingKey {
        case kind, detail
        case petID = "pet_id"
        case parentID = "parent_id"
        case photoPath = "photo_path"
        case occurredAt = "occurred_at"
    }
}
