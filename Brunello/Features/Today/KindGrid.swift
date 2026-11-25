import SwiftUI

/// The six big buttons for logging what the pet did.
struct KindGrid: View {
    let kinds: [EntryKind]
    let isSendingPhoto: Bool
    let onSelect: (EntryKind) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(kinds) { kind in
                Button {
                    onSelect(kind)
                } label: {
                    VStack(spacing: 2) {
                        if kind == .photo && isSendingPhoto {
                            ProgressView().frame(height: 38)
                        } else {
                            Text(kind.emoji).font(.system(size: 32)).frame(height: 38)
                        }
                        Text(kind.label).font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(TintedButtonStyle(color: kind.color))
                .disabled(kind == .photo && isSendingPhoto)
            }
        }
    }
}
