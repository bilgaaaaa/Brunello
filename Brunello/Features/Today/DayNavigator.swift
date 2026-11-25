import SwiftUI

/// Steps back and forth between days, never past today or before the first entry.
struct DayNavigator: View {
    @Binding var selectedDay: Date
    let earliestDay: Date

    private let calendar = Calendar.current

    private var title: String {
        if calendar.isDateInToday(selectedDay) { return "Today" }
        if calendar.isDateInYesterday(selectedDay) { return "Yesterday" }
        return selectedDay.formatted(.dateTime.weekday(.wide))
    }

    var body: some View {
        HStack {
            stepButton(systemImage: "chevron.left", label: "Previous day", days: -1)
                .disabled(selectedDay <= earliestDay)
            Spacer()
            VStack(spacing: 0) {
                Text(title).font(.headline).foregroundStyle(Theme.ink)
                Text(selectedDay.formatted(.dateTime.day().month(.wide)))
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            stepButton(systemImage: "chevron.right", label: "Next day", days: 1)
                .disabled(selectedDay >= calendar.startOfDay(for: .now))
        }
        .card(padding: 6)
    }

    private func stepButton(systemImage: String, label: String, days: Int) -> some View {
        Button {
            guard let day = calendar.date(byAdding: .day, value: days, to: selectedDay) else { return }
            withAnimation(.snappy) { selectedDay = day }
        } label: {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .frame(width: 38, height: 38)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .foregroundStyle(Theme.ink)
        .accessibilityLabel(label)
    }
}
