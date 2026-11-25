import Foundation

/// The pet and its parents, seen from this phone.
struct Family: Equatable, Sendable {
    var pet: Pet
    var me: Parent
    var otherParent: Parent?

    /// "you" for my own entries, otherwise the other parent's name.
    func authorLabel(for entry: Entry) -> String {
        if entry.parentID == me.id { return "you" }
        if let otherParent, otherParent.id == entry.parentID { return otherParent.name }
        return "a parent"
    }

    func isMine(_ entry: Entry) -> Bool {
        entry.parentID == me.id
    }

    /// "you" for what I paid, otherwise the other parent's name.
    func payerLabel(for expense: Expense) -> String {
        if expense.parentID == me.id { return "you" }
        if let otherParent, otherParent.id == expense.parentID { return otherParent.name }
        return "a parent"
    }

    func isMine(_ expense: Expense) -> Bool {
        expense.parentID == me.id
    }

    /// Who owes what for one expense, for example "Marco owes €12.50"; nil for a payback.
    func shareLabel(for expense: Expense) -> String? {
        if expense.category == .settleUp { return nil }
        if expense.owedCents == 0 { return "not shared" }
        let owed = Money.format(cents: expense.owedCents, currencyCode: pet.currencyCode)
        return isMine(expense) ? "\(otherParentName) owes \(owed)" : "you owe \(owed)"
    }

    /// The other parent's name, or a neutral stand-in until they join.
    var otherParentName: String {
        otherParent?.name ?? "The other parent"
    }
}
