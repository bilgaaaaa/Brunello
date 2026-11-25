import SwiftUI

/// What was spent on the pet, who paid, and who owes whom.
struct MoneyView: View {
    @Environment(AppState.self) private var appState
    let family: Family

    @State private var isAddingExpense = false
    @State private var isConfirmingSettleUp = false

    private var currencyCode: String {
        family.pet.currencyCode
    }

    private var balanceCents: Int {
        Money.balanceCents(expenses: appState.expenses, myParentID: family.me.id)
    }

    private var monthSpending: [CategoryTotal] {
        Money.spending(in: appState.expenses, monthOf: .now)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("\(family.pet.name)'s money")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                balanceCard
                Button {
                    isAddingExpense = true
                } label: {
                    Label("Add an expense", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                SectionLabel("This month")
                monthCard
                SectionLabel("Everything")
                expenseList
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 12)
        }
        .background(Theme.background)
        .refreshable { await appState.refresh() }
        .sheet(isPresented: $isAddingExpense) {
            ExpenseSheet(petName: family.pet.name, currencyCode: currencyCode) { category, amountCents, spentAt in
                Task { await appState.addExpense(category: category, amountCents: amountCents, spentAt: spentAt) }
            }
        }
        .confirmationDialog(settleUpTitle, isPresented: $isConfirmingSettleUp, titleVisibility: .visible) {
            Button("Yes, I paid \(Money.format(cents: -balanceCents, currencyCode: currencyCode))") {
                let amountCents = -balanceCents
                Task { await appState.settleUp(amountCents: amountCents) }
            }
        }
    }

    private var settleUpTitle: String {
        "Did you pay \(family.otherParent?.name ?? "the other parent") back?"
    }

    // MARK: - Pieces

    @ViewBuilder
    private var balanceCard: some View {
        VStack(spacing: 6) {
            if let otherParent = family.otherParent {
                if balanceCents == 0 {
                    Text("🎉").font(.largeTitle)
                    Text("All square").font(.title2.bold()).foregroundStyle(Theme.ink)
                    Text("Nobody owes anything.").font(.footnote).foregroundStyle(Theme.inkSoft)
                } else if balanceCents > 0 {
                    Text("\(otherParent.name) owes you").font(.subheadline).foregroundStyle(Theme.inkSoft)
                    amountText(balanceCents)
                } else {
                    Text("You owe \(otherParent.name)").font(.subheadline).foregroundStyle(Theme.inkSoft)
                    amountText(-balanceCents)
                    Button("I paid \(otherParent.name) back") {
                        isConfirmingSettleUp = true
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 6)
                }
            } else {
                Text("🤝").font(.largeTitle)
                Text("The balance shows up when the other parent joins.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: 18)
    }

    private func amountText(_ cents: Int) -> some View {
        Text(Money.format(cents: cents, currencyCode: currencyCode))
            .font(.system(size: 40, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.ink)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }

    @ViewBuilder
    private var monthCard: some View {
        if monthSpending.isEmpty {
            Text("Nothing spent on \(family.pet.name) this month yet.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .card()
        } else {
            VStack(spacing: 10) {
                ForEach(monthSpending) { total in
                    moneyRow(emoji: total.category.emoji, label: total.category.label, cents: total.amountCents, isBold: false)
                }
                Divider()
                moneyRow(emoji: "🧾", label: "Total", cents: monthSpending.reduce(0) { $0 + $1.amountCents }, isBold: true)
            }
            .card()
        }
    }

    private func moneyRow(emoji: String, label: String, cents: Int, isBold: Bool) -> some View {
        HStack {
            Text(emoji)
            Text(label)
            Spacer(minLength: 8)
            Text(Money.format(cents: cents, currencyCode: currencyCode)).monospacedDigit()
        }
        .font(isBold ? .headline : .subheadline.weight(.semibold))
        .foregroundStyle(Theme.ink)
    }

    @ViewBuilder
    private var expenseList: some View {
        if appState.expenses.isEmpty {
            VStack(spacing: 6) {
                Text("💶").font(.largeTitle)
                Text("No expenses yet. Add the first thing you bought for \(family.pet.name).")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .card(padding: 20)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(appState.expenses) { expense in
                    ExpenseRow(expense: expense, payerLabel: family.payerLabel(for: expense), currencyCode: currencyCode)
                        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                        .contextMenu {
                            if family.isMine(expense) {
                                Button(role: .destructive) {
                                    Task { await appState.deleteExpense(expense) }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                }
            }
            .animation(.snappy, value: appState.expenses)
        }
    }
}

/// One expense or payback in the list.
struct ExpenseRow: View {
    let expense: Expense
    let payerLabel: String
    let currencyCode: String

    private var detailLine: String {
        let day = expense.spentAt.formatted(.dateTime.day().month(.abbreviated))
        let verb = expense.category == .settleUp ? "from" : "paid by"
        return "\(verb) \(payerLabel) · \(day)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(expense.category.emoji)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(Theme.brand.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.category.label)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 8)
            Text(Money.format(cents: expense.amountCents, currencyCode: currencyCode))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .card(padding: 12)
        .accessibilityElement(children: .combine)
    }
}
