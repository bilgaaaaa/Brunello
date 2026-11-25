import SwiftUI

/// How many times each main thing happened on the selected day.
struct DaySummaryView: View {
    let kinds: [EntryKind]
    let entries: [Entry]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(kinds) { kind in
                let count = entries.filter { $0.kind == kind }.count
                VStack(spacing: 0) {
                    Text("\(kind.emoji) \(count)")
                        .font(.title3.bold())
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                    Text(kind.countLabel)
                        .font(.caption2)
                        .foregroundStyle(Theme.inkSoft)
                }
                .frame(maxWidth: .infinity)
                .card(padding: 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(count) \(kind.countLabel)")
            }
        }
    }
}
