import SwiftUI

/// Adds an expense: an amount, a category and the day. No free text.
struct ExpenseSheet: View {
    let petName: String
    let currencyCode: String
    let onSave: (ExpenseCategory, Int, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var category: ExpenseCategory?
    @State private var spentAt = Date.now
    @FocusState private var isAmountFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var amountCents: Int? {
        Money.cents(from: amountText)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("What did you buy for \(petName)?")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 28)
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
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                                    .stroke(category == choice ? Theme.brand : .clear, lineWidth: 3)
                            )
                        }
                        .buttonStyle(TintedButtonStyle(color: Theme.brand))
                        .accessibilityAddTraits(category == choice ? .isSelected : [])
                    }
                }
                DatePicker("When", selection: $spentAt, in: ...Date.now, displayedComponents: .date)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 4)
                Button("Save") {
                    guard let amountCents, let category else { return }
                    onSave(category, amountCents, spentAt)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(amountCents == nil || category == nil)
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
}
