import SwiftUI

/// Small uppercase heading above a group of cards.
struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.heavy))
            .kerning(0.8)
            .foregroundStyle(Theme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Rounded card surface used across the app.
    func card(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

/// The main call-to-action button.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration)
    }
}

/// Draws the primary button; a separate view so it can dim itself when the button is disabled.
private struct PrimaryButtonBody: View {
    let configuration: ButtonStyle.Configuration

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onBrand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// A large, soft button tinted with a color (kind buttons, log options, choices).
struct TintedButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.ink)
            .background(color.opacity(0.22), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// A rounded text field that matches the cards.
struct FieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.body.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line, lineWidth: 2))
    }
}

/// Round picture of the pet: its photo when there is one, otherwise the species emoji.
struct PetAvatar: View {
    let pet: Pet
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            Circle().fill(Theme.brand.opacity(0.16))
            if let photoPath = pet.photoPath {
                RemotePhoto(path: photoPath)
            } else {
                Text(pet.species.emoji).font(.system(size: size * 0.55))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.card, lineWidth: 3))
        .accessibilityHidden(true)
    }
}

/// A picture stored on the server, filling whatever frame it is given.
struct RemotePhoto: View {
    let path: String

    @State private var image: UIImage?

    var body: some View {
        Theme.line
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ProgressView()
                }
            }
            .clipped()
            .task(id: path) {
                image = await PhotoStore.shared.image(for: path)
            }
    }
}

/// A short message that slides up from the bottom and leaves on its own.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

struct ToastOverlay: ViewModifier {
    let toast: Toast?
    let onFinished: (Toast) -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast.text)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.ink, in: Capsule())
                        .padding(.bottom, 64)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: toast.id) {
                            try? await Task.sleep(for: .seconds(2.5))
                            onFinished(toast)
                        }
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .animation(.snappy, value: toast)
    }
}

extension View {
    func toast(_ toast: Toast?, onFinished: @escaping (Toast) -> Void) -> some View {
        modifier(ToastOverlay(toast: toast, onFinished: onFinished))
    }
}

extension UIImage {
    /// Shrinks the picture so its longest side fits `maxDimension`, then encodes it as JPEG for upload.
    func jpegDataForUpload(maxDimension: CGFloat = AppConfig.photoMaxDimension) -> Data? {
        let scale = min(1, maxDimension / max(size.width, size.height))
        let targetSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
