import Foundation

/// One line of the monthly summary: how much went to one category.
struct CategoryTotal: Identifiable, Equatable, Sendable {
    let category: ExpenseCategory
    let amountCents: Int

    var id: ExpenseCategory { category }
}

/// Sums and formatting for the pet's expenses. Amounts are whole cents to avoid rounding surprises.
enum Money {
    static let maxAmountCents = 10_000_000
    static let fallbackCurrencyCode = "EUR"
    static let commonCurrencyCodes = ["EUR", "USD", "GBP", "CHF", "TRY", "CAD", "AUD"]

    /// Positive: the other parent owes me this much. Negative: I owe them.
    /// An expense counts for half (it is shared); a payback counts in full.
    static func balanceCents(expenses: [Expense], myParentID: UUID) -> Int {
        var doubledBalance = 0
        for expense in expenses {
            let sign = expense.parentID == myParentID ? 1 : -1
            let weight = expense.category == .settleUp ? 2 : 1
            doubledBalance += sign * weight * expense.amountCents
        }
        return doubledBalance / 2
    }

    /// What both parents spent on the pet in the month of `date`, largest category first. Paybacks are not spending.
    static func spending(in expenses: [Expense], monthOf date: Date, calendar: Calendar = .current) -> [CategoryTotal] {
        var totals: [ExpenseCategory: Int] = [:]
        for expense in expenses where expense.category != .settleUp && calendar.isDate(expense.spentAt, equalTo: date, toGranularity: .month) {
            totals[expense.category, default: 0] += expense.amountCents
        }
        return totals
            .map { CategoryTotal(category: $0.key, amountCents: $0.value) }
            .sorted { ($0.amountCents, $1.category.rawValue) > ($1.amountCents, $0.category.rawValue) }
    }

    /// Reads what the person typed ("12", "12.5", "12,50") as cents; nil when it is not a usable amount.
    static func cents(from text: String) -> Int? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let whole = parts.first, !whole.isEmpty,
              normalized.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else { return nil }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.count <= 2, let wholeUnits = Int(whole), wholeUnits <= maxAmountCents / 100 else { return nil }
        let cents = wholeUnits * 100 + (Int(fraction.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0)
        return (1...maxAmountCents).contains(cents) ? cents : nil
    }

    /// Money as people read it in their own region, for example "€25.00" or "25,00 €".
    static func format(cents: Int, currencyCode: String) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: currencyCode))
    }

    /// The currency of the phone's region, used when a pet is first created.
    static var deviceCurrencyCode: String {
        Locale.current.currency?.identifier ?? fallbackCurrencyCode
    }

    /// Currencies offered in settings, always including the one already in use.
    static func currencyChoices(including currencyCode: String) -> [String] {
        commonCurrencyCodes.contains(currencyCode) ? commonCurrencyCodes : [currencyCode] + commonCurrencyCodes
    }
}
