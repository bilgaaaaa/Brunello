import Foundation

/// Money one parent spent on the pet. Every expense is shared half and half between the two parents.
struct Expense: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let petID: UUID
    let parentID: UUID
    let category: ExpenseCategory
    let amountCents: Int
    let spentAt: Date

    enum CodingKeys: String, CodingKey {
        case id, category
        case petID = "pet_id"
        case parentID = "parent_id"
        case amountCents = "amount_cents"
        case spentAt = "spent_at"
    }
}

/// What the app sends to add an expense; the server fills in the id.
struct NewExpense: Encodable, Sendable {
    let petID: UUID
    let parentID: UUID
    let category: ExpenseCategory
    let amountCents: Int
    var spentAt: Date = .now

    enum CodingKeys: String, CodingKey {
        case category
        case petID = "pet_id"
        case parentID = "parent_id"
        case amountCents = "amount_cents"
        case spentAt = "spent_at"
    }
}

/// What the money was for. `settleUp` is one parent paying the other back.
/// Keep in step with EXPENSE_VOICE_LINES in supabase/functions/notify-parent/petVoice.ts.
enum ExpenseCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case food, vet, medicine, grooming, toys, other
    case settleUp = "settle_up"

    /// The categories offered when adding an expense; paying back has its own button.
    static let spending: [ExpenseCategory] = [.food, .vet, .medicine, .grooming, .toys, .other]

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .food: "🍖"
        case .vet: "🩺"
        case .medicine: "💊"
        case .grooming: "✂️"
        case .toys: "🧸"
        case .other: "🛍️"
        case .settleUp: "🤝"
        }
    }

    var label: String {
        switch self {
        case .food: "Food"
        case .vet: "Vet"
        case .medicine: "Medicine"
        case .grooming: "Grooming"
        case .toys: "Toys"
        case .other: "Other"
        case .settleUp: "Paid back"
        }
    }
}
