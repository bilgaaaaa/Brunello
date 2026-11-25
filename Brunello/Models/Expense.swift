import Foundation

/// Money one parent spent on the pet. `owedCents` is the part the other parent owes the payer.
struct Expense: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let petID: UUID
    let parentID: UUID
    let category: ExpenseCategory
    let amountCents: Int
    let owedCents: Int
    let spentAt: Date

    enum CodingKeys: String, CodingKey {
        case id, category
        case petID = "pet_id"
        case parentID = "parent_id"
        case amountCents = "amount_cents"
        case owedCents = "owed_cents"
        case spentAt = "spent_at"
    }
}

/// What the app sends to add an expense; the server fills in the id.
struct NewExpense: Encodable, Sendable {
    let petID: UUID
    let parentID: UUID
    let category: ExpenseCategory
    let amountCents: Int
    let owedCents: Int
    var spentAt: Date = .now

    enum CodingKeys: String, CodingKey {
        case category
        case petID = "pet_id"
        case parentID = "parent_id"
        case amountCents = "amount_cents"
        case owedCents = "owed_cents"
        case spentAt = "spent_at"
    }
}

/// How the payer shares an expense with the other parent.
enum ExpenseSplit: String, CaseIterable, Identifiable, Sendable {
    case half, otherPaysAll, notShared, custom

    var id: String { rawValue }

    func label(otherName: String) -> String {
        switch self {
        case .half: "Half each"
        case .otherPaysAll: "\(otherName) pays it all"
        case .notShared: "I pay it all"
        case .custom: "Another amount"
        }
    }

    /// The part the other parent owes for an expense of `amountCents`; nil while a custom part is missing or too big.
    func owedCents(amountCents: Int, customOwedCents: Int?) -> Int? {
        switch self {
        case .half: amountCents / 2
        case .otherPaysAll: amountCents
        case .notShared: 0
        case .custom: customOwedCents.flatMap { $0 <= amountCents ? $0 : nil }
        }
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
