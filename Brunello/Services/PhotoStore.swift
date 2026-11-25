import OSLog
import UIKit

/// Loads diary photos once: from memory, then from the phone's cache folder, then from the server.
actor PhotoStore {
    static let shared = PhotoStore()

    private let memory = NSCache<NSString, UIImage>()
    private var downloads: [String: Task<UIImage?, Never>] = [:]
    private let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("photos", isDirectory: true)

    init() {
        memory.countLimit = 80
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func image(for path: String) async -> UIImage? {
        if let cached = memory.object(forKey: path as NSString) { return cached }
        if let running = downloads[path] { return await running.value }

        let cachedFile = fileURL(for: path)
        let download = Task<UIImage?, Never> {
            if let data = try? Data(contentsOf: cachedFile), let image = UIImage(data: data) { return image }
            do {
                let data = try await DiaryService.shared.downloadPhoto(path: path)
                try? data.write(to: cachedFile, options: .atomic)
                return UIImage(data: data)
            } catch {
                Logger.photos.error("Photo download failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        downloads[path] = download
        let image = await download.value
        downloads[path] = nil
        if let image { memory.setObject(image, forKey: path as NSString) }
        return image
    }

    /// Keeps a picture this phone just uploaded, so it shows without downloading it again.
    func store(_ image: UIImage, data: Data, for path: String) {
        memory.setObject(image, forKey: path as NSString)
        try? data.write(to: fileURL(for: path), options: .atomic)
    }

    private func fileURL(for path: String) -> URL {
        folder.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_"))
    }
}
