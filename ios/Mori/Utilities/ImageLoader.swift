import SwiftUI
import ImageIO

/// Loads remote images with the Referer/User-Agent the CDN expects, with memory + disk caching
/// and an images.weserv.nl proxy fallback (same strategy as the web build).
actor ImageLoader {
    static let shared = ImageLoader()

    private let memory = NSCache<NSString, UIImage>()
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 20 << 20, diskCapacity: 200 << 20,
                                   directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                                    .appendingPathComponent("ImageCache"))
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    func image(for urlString: String, sourceURL: String?, maxPixel: CGFloat? = 600) async throws -> UIImage {
        let key = "\(urlString)#\(Int(maxPixel ?? 0))" as NSString
        if let cached = memory.object(forKey: key) { return cached }

        if urlString.hasPrefix("data:"), let comma = urlString.firstIndex(of: ","),
           let data = Data(base64Encoded: String(urlString[urlString.index(after: comma)...])),
           let img = decode(data, maxPixel: maxPixel) {
            memory.setObject(img, forKey: key)
            return img
        }

        var candidates: [URL] = []
        if let u = URL(string: urlString) ?? URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") {
            candidates.append(u)
        }
        if let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
           let proxy = URL(string: "https://images.weserv.nl/?url=\(encoded)") {
            candidates.append(proxy)
        }

        var lastError: Error = URLError(.badURL)
        for (i, url) in candidates.enumerated() {
            var req = URLRequest(url: url)
            if i == 0 {
                DownloadHeaders.preview(for: urlString, sourceURL: sourceURL).forEach {
                    req.setValue($0.value, forHTTPHeaderField: $0.key)
                }
            }
            do {
                let (data, response) = try await session.data(for: req)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                if let img = decode(data, maxPixel: maxPixel) {
                    memory.setObject(img, forKey: key)
                    return img
                }
                throw URLError(.cannotDecodeContentData)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private nonisolated func decode(_ data: Data, maxPixel: CGFloat?) -> UIImage? {
        guard let maxPixel else { return UIImage(data: data) }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return UIImage(data: data) }
        let thumbOpts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel * 3,
        ] as CFDictionary
        if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts) { return UIImage(cgImage: cg) }
        return UIImage(data: data)
    }
}

struct RemoteImage: View {
    let url: String?
    var sourceURL: String?
    var maxPixel: CGFloat? = 600
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed || url == nil || url?.isEmpty == true {
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: "photo").font(.title2).foregroundStyle(.secondary))
            } else {
                Rectangle().fill(.quaternary).overlay(ProgressView())
            }
        }
        .task(id: url) {
            guard let url, !url.isEmpty else { return }
            image = nil
            failed = false
            do {
                image = try await ImageLoader.shared.image(for: url, sourceURL: sourceURL, maxPixel: maxPixel)
            } catch {
                failed = true
            }
        }
    }
}
