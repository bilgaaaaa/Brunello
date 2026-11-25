import OSLog
import PhotosUI
import SwiftUI

/// Lets the person take a picture or choose one from their library, then hands back the image.
struct PhotoSourcePicker: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let onPick: (UIImage) -> Void

    @State private var isShowingCamera = false
    @State private var isShowingLibrary = false
    @State private var libraryItem: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take a photo") { isShowingCamera = true }
                }
                Button("Choose from my photos") { isShowingLibrary = true }
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraPicker(onPick: onPick).ignoresSafeArea()
            }
            .photosPicker(isPresented: $isShowingLibrary, selection: $libraryItem, matching: .images)
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                libraryItem = nil
                Task { @MainActor in
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        onPick(image)
                    } else {
                        Logger.photos.error("The chosen picture could not be read")
                    }
                }
            }
    }
}

extension View {
    func photoSourcePicker(isPresented: Binding<Bool>, title: String, onPick: @escaping (UIImage) -> Void) -> some View {
        modifier(PhotoSourcePicker(isPresented: isPresented, title: title, onPick: onPick))
    }
}

/// The system camera, wrapped for SwiftUI.
struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onPick(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
