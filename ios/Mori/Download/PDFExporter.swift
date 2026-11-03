import UIKit

/// Combines gallery images into a single PDF (replaces pdf-lib from the web build).
enum PDFExporter {
    static func export(title: String, images: [MediaDownload], sourceURL: String, platform: Platform?,
                       progress: @escaping (Double) -> Void) async throws -> URL {
        var loaded: [UIImage] = []
        for (i, item) in images.enumerated() {
            try Task.checkCancellation()
            if let img = try? await ImageLoader.shared.image(for: item.url, sourceURL: sourceURL, maxPixel: nil) {
                loaded.append(img)
            }
            await MainActor.run { progress(Double(i + 1) / Double(images.count) * 0.9) }
        }
        guard !loaded.isEmpty else {
            throw FileDownloader.DownloadError(message: String(localized: "Could not load any image."))
        }

        let pageWidth: CGFloat = 1240
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageWidth))
        let data = renderer.pdfData { ctx in
            for img in loaded {
                let scale = pageWidth / max(1, img.size.width)
                let rect = CGRect(x: 0, y: 0, width: pageWidth, height: img.size.height * scale)
                ctx.beginPage(withBounds: rect, pageInfo: [:])
                img.draw(in: rect)
            }
        }

        let folder = StorageLocations.folder(isAudio: false, platform: platform)
        let name = FileNaming.sanitizeTitle(title, type: "pdf") + ".pdf"
        let dest: URL
        switch StorageLocations.destination(in: folder, fileName: name) {
        case .use(let u): dest = u
        case .skip(let u): dest = u
        }
        try data.write(to: dest, options: .atomic)
        await MainActor.run {
            progress(1)
            NotificationCenter.default.post(name: .moriLibraryChanged, object: nil)
        }
        return dest
    }
}
