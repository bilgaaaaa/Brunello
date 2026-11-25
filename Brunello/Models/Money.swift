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
    /// Each expense adds the part its payer is owed; a payback counts in full.
    static func balanceCents(expenses: [Expense], myParentID: UUID) -> Int {
        expenses.reduce(0) { balance, expense in
            balance + (expense.parentID == myParentID ? expense.owedCents : -expense.owedCents)
        }
    }

    /// What I end up paying for the pet in the month of `date`, after sharing, and what the other parent does.
    static func parts(in expenses: [Expense], monthOf date: Date, myParentID: UUID, calendar: Calendar = .current) -> (mine: Int, other: Int) {
        var mine = 0, other = 0
        for expense in expenses where expense.category != .settleUp && calendar.isDate(expense.spentAt, equalTo: date, toGranularity: .month) {
            let payerPart = expense.amountCents - expense.owedCents
            if expense.parentID == myParentID {
                mine += payerPart
                other += expense.owedCents
            } else {
                mine += expense.owedCents
                other += payerPart
            }
        }
        return (mine, other)
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
