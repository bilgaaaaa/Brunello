import SwiftUI

/// The main screen: today's summary, the six log buttons and the day's diary.
struct TodayView: View {
    @Environment(AppState.self) private var appState
    let family: Family

    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var sheetKind: EntryKind?
    @State private var isChoosingPhoto = false
    @State private var viewedPhoto: Entry?

    private var dayEntries: [Entry] {
        appState.entries.filter { Calendar.current.isDate($0.occurredAt, inSameDayAs: selectedDay) }
    }

    /// The oldest day that has an entry; the day navigator stops there.
    private var earliestDay: Date {
        Calendar.current.startOfDay(for: appState.entries.last?.occurredAt ?? .now)
    }

    private var diaryTitle: String {
        Calendar.current.isDateInToday(selectedDay) ? "Today's diary" : "Diary"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PetHeader(family: family)
                if family.otherParent == nil {
                    InviteCard(pet: family.pet)
                }
                DayNavigator(selectedDay: $selectedDay, earliestDay: earliestDay)
                DaySummaryView(kinds: Array(family.pet.species.kinds.prefix(Species.summaryKindCount)), entries: dayEntries)
                SectionLabel("What did \(family.pet.name) do?")
                KindGrid(kinds: family.pet.species.kinds, isSendingPhoto: appState.isSendingPhoto, onSelect: open)
                SectionLabel(diaryTitle)
                diary
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 12)
        }
        .background(Theme.background)
        .refreshable { await appState.refresh() }
        .sheet(item: $sheetKind) { kind in
            LogSheet(kind: kind, petName: family.pet.name) { detail, occurredAt in
                selectedDay = Calendar.current.startOfDay(for: occurredAt)
                Task { await appState.logEntry(kind: kind, detail: detail, occurredAt: occurredAt) }
            }
        }
        .photoSourcePicker(isPresented: $isChoosingPhoto, title: EntryKind.photo.question(petName: family.pet.name)) { image in
            selectedDay = Calendar.current.startOfDay(for: .now)
            Task { await appState.sendPhoto(image) }
        }
        .fullScreenCover(item: $viewedPhoto) { entry in
            PhotoViewer(entry: entry, family: family) {
                Task { await appState.deleteEntry(entry) }
            }
        }
    }

    @ViewBuilder
    private var diary: some View {
        if dayEntries.isEmpty {
            VStack(spacing: 6) {
                Text(family.pet.species.emoji).font(.largeTitle)
                Text("Nothing in the diary for this day yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .card(padding: 20)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(dayEntries) { entry in
                    EntryRow(entry: entry, authorLabel: family.authorLabel(for: entry))
                        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                        .onTapGesture {
                            if entry.kind == .photo { viewedPhoto = entry }
                        }
                        .contextMenu {
                            if family.isMine(entry) {
                                Button(role: .destructive) {
                                    Task { await appState.deleteEntry(entry) }
                                } label: {
                                    Label("Remove from the diary", systemImage: "trash")
                                }
                            }
                        }
                }
            }
            .animation(.snappy, value: dayEntries)
        }
    }

    private func open(_ kind: EntryKind) {
        if kind == .photo {
            isChoosingPhoto = true
        } else {
            sheetKind = kind
        }
    }
}

/// The pet's picture and name, with the two parents underneath.
struct PetHeader: View {
    let family: Family

    private var parentsLine: String {
        if let otherParent = family.otherParent {
            return "with \(family.me.name) & \(otherParent.name)"
        }
        return "Waiting for the other parent"
    }

    var body: some View {
        HStack(spacing: 12) {
            PetAvatar(pet: family.pet, size: 58)
            VStack(alignment: .leading, spacing: 2) {
                Text(family.pet.name)
                    .font(.title.bold())
                    .foregroundStyle(Theme.ink)
                Text(parentsLine)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
