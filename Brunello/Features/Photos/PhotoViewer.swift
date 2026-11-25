import SwiftUI

/// One photo, full screen, with who took it, plus sharing and (for your own) deleting.
struct PhotoViewer: View {
    let entry: Entry
    let family: Family
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.largeTitle)
                    }
                    .accessibilityLabel("Close")
                }
                Spacer(minLength: 0)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                } else {
                    ProgressView()
                }
                VStack(spacing: 2) {
                    Text(PetVoice.diaryMessage(for: entry)).font(.headline)
                    Text("\(entry.occurredAt.formatted(date: .complete, time: .shortened)) · with \(family.authorLabel(for: entry))")
                        .font(.footnote)
                        .opacity(0.75)
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
                HStack(spacing: 28) {
                    if let image {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview(family.pet.name, image: Image(uiImage: image))
                        ) {
                            Label("Save or share", systemImage: "square.and.arrow.up")
                        }
                    }
                    if family.isMine(entry) {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .font(.subheadline.weight(.bold))
            }
            .padding()
        }
        .foregroundStyle(.white)
        .tint(.white)
        .task {
            image = await PhotoStore.shared.image(for: entry.photoPath ?? "")
        }
    }
}
