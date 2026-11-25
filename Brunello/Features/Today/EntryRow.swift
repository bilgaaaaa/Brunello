import SwiftUI

/// One diary line, told in the pet's voice.
struct EntryRow: View {
    let entry: Entry
    let authorLabel: String

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.kind.emoji)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(entry.kind.tint, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(PetVoice.diaryMessage(for: entry))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Text("\(entry.occurredAt.formatted(date: .omitted, time: .shortened)) · with \(authorLabel)")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
            if let photoPath = entry.photoPath {
                RemotePhoto(path: photoPath)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .card(padding: 12)
        .accessibilityElement(children: .combine)
    }
}
