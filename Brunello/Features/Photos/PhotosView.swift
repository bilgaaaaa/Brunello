import SwiftUI

/// Every photo in the diary, newest first.
struct PhotosView: View {
    @Environment(AppState.self) private var appState
    let family: Family

    @State private var viewedPhoto: Entry?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    private var photos: [Entry] {
        appState.entries.filter { $0.kind == .photo }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(family.pet.name)'s photos")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.ink)
                if photos.isEmpty {
                    VStack(spacing: 6) {
                        Text("📸").font(.largeTitle)
                        Text("No photos yet. Send the first one from Today.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .card(padding: 20)
                } else {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(photos) { entry in
                            photoCell(entry)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 12)
        }
        .background(Theme.background)
        .refreshable { await appState.refresh() }
        .fullScreenCover(item: $viewedPhoto) { entry in
            PhotoViewer(entry: entry, family: family) {
                Task { await appState.deleteEntry(entry) }
            }
        }
    }

    private func photoCell(_ entry: Entry) -> some View {
        Button {
            viewedPhoto = entry
        } label: {
            RemotePhoto(path: entry.photoPath ?? "")
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Photo from \(entry.occurredAt.formatted(date: .abbreviated, time: .shortened))")
    }
}
