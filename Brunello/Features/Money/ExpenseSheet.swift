import SwiftUI

/// Adds an expense: an amount, a category, how it is shared and the day. No free text.
struct ExpenseSheet: View {
    let petName: String
    let otherParentName: String
    let currencyCode: String
    /// Category, amount, the part the other parent owes, and the day.
    let onSave: (ExpenseCategory, Int, Int, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var category: ExpenseCategory?
    @State private var split = ExpenseSplit.half
    @State private var customOwedText = ""
    @State private var spentAt = Date.now
    @FocusState private var isAmountFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var amountCents: Int? {
        Money.cents(from: amountText)
    }

    private var owedCents: Int? {
        guard let amountCents else { return nil }
        return split.owedCents(amountCents: amountCents, customOwedCents: Money.cents(from: customOwedText))
    }

    /// One line that says what the choice means, so nobody has to do the maths.
    private var splitSummary: String {
        guard let amountCents else { return "Type the amount first." }
        guard let owedCents else { return "Type how much \(otherParentName) owes, up to \(Money.format(cents: amountCents, currencyCode: currencyCode))." }
        if owedCents == 0 { return "\(otherParentName) owes nothing for this." }
        return "\(otherParentName) owes you \(Money.format(cents: owedCents, currencyCode: currencyCode))."
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("What did you buy for \(petName)?")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 28)
                amountField
                categoryGrid
                SectionLabel("How is it shared?")
                splitChoices
                DatePicker("When", selection: $spentAt, in: ...Date.now, displayedComponents: .date)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 4)
                Button("Save") {
                    guard let amountCents, let owedCents, let category else { return }
                    onSave(category, amountCents, owedCents, spentAt)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(amountCents == nil || owedCents == nil || category == nil)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
        .onAppear { isAmountFocused = true }
    }

    // MARK: - Pieces

    private var amountField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField("0.00", text: $amountText)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($isAmountFocused)
                .accessibilityLabel("Amount")
            Text(currencyCode)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(ExpenseCategory.spending) { choice in
                Button {
                    category = choice
                } label: {
                    VStack(spacing: 2) {
                        Text(choice.emoji).font(.title)
                        Text(choice.label).font(.footnote.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(selectionRing(isSelected: category == choice))
                }
                .buttonStyle(TintedButtonStyle(color: Theme.brand))
                .accessibilityAddTraits(category == choice ? .isSelected : [])
            }
        }
    }

    private var splitChoices: some View {
        VStack(spacing: 8) {
            ForEach(ExpenseSplit.allCases) { choice in
                Button {
                    split = choice
                } label: {
                    HStack {
                        Text(choice.label(otherName: otherParentName)).font(.subheadline.weight(.bold))
                        Spacer(minLength: 8)
                        Image(systemName: split == choice ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(split == choice ? Theme.brand : Theme.line)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .overlay(selectionRing(isSelected: split == choice))
                }
                .buttonStyle(TintedButtonStyle(color: Theme.brand))
                .accessibilityAddTraits(split == choice ? .isSelected : [])
            }
            if split == .custom {
                TextField("How much \(otherParentName) owes", text: $customOwedText)
                    .textFieldStyle(FieldStyle())
                    .keyboardType(.decimalPad)
            }
            Text(splitSummary)
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func selectionRing(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            .stroke(isSelected ? Theme.brand : .clear, lineWidth: 3)
    }
}
