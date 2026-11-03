import Photos
import UIKit

/// Saves files into the system photo library.
enum PhotoSaver {
    enum SaveError: LocalizedError {
        case denied, unsupported, failed(String)
        var errorDescription: String? {
            switch self {
            case .denied: return String(localized: "Photo library access denied. Allow it in Settings.")
            case .unsupported: return String(localized: "This file type can't be saved to Photos.")
            case .failed(let m): return m
            }
        }
    }

    static func canSave(_ url: URL) -> Bool {
        kind(of: url) != nil
    }

    private static func kind(of url: URL) -> PHAssetMediaType? {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"].contains(ext) { return .image }
        if ["mp4", "mov", "m4v"].contains(ext) { return .video }
        return nil
    }

    static func save(_ url: URL) async throws {
        guard let kind = kind(of: url) else { throw SaveError.unsupported }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.denied }

        var source = url
        var tempCopy: URL?
        // Photos may reject WebP files; convert them to JPEG first
        if url.pathExtension.lowercased() == "webp",
           let image = UIImage(contentsOfFile: url.path),
           let data = image.jpegData(compressionQuality: 0.95) {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
            try data.write(to: tmp)
            source = tmp
            tempCopy = tmp
        }
        defer { if let tempCopy { try? FileManager.default.removeItem(at: tempCopy) } }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = url.lastPathComponent
                request.addResource(with: kind == .image ? .photo : .video, fileURL: source, options: options)
            }
        } catch {
            throw SaveError.failed(error.localizedDescription)
        }
    }
}
