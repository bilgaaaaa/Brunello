import SwiftUI

/// Asks how it went: one tap on an answer saves the entry.
struct LogSheet: View {
    let kind: EntryKind
    let petName: String
    let onChoose: (EntryDetail, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var occurredAt = Date.now

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(kind.question(petName: petName))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 28)
                    .padding(.bottom, 4)
                ForEach(kind.options) { option in
                    Button {
                        onChoose(option.detail, occurredAt)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(option.emoji).font(.title2)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(option.label).font(.headline)
                                if let hint = option.hint {
                                    Text(hint).font(.footnote).foregroundStyle(Theme.inkSoft)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(TintedButtonStyle(color: kind.color))
                }
                DatePicker(
                    "When",
                    selection: $occurredAt,
                    in: Calendar.current.startOfDay(for: .now)...Date.now,
                    displayedComponents: .hourAndMinute
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 4)
                .padding(.top, 4)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 16)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
    }
}
