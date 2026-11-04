import Kingfisher
import SwiftUI

/// Remote image loading built on Kingfisher.
/// Requests carry the Referer / User-Agent the CDN expects; on failure the
/// images.weserv.nl proxy is tried once (same strategy as the web build).
enum ImageLoader {
    /// Kingfisher source for a remote URL string, data URI or local file.
    static func source(for urlString: String) -> Source? {
        if urlString.hasPrefix("data:"), let comma = urlString.firstIndex(of: ",") {
            let base64 = String(urlString[urlString.index(after: comma)...])
            return .provider(Base64ImageDataProvider(base64String: base64, cacheKey: "data-\(base64.hashValue)"))
        }
        guard let url = URL(string: urlString)
                ?? URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else {
            return nil
        }
        return source(for: url)
    }

    static func source(for url: URL) -> Source {
        url.isFileURL ? .provider(LocalFileImageDataProvider(fileURL: url)) : .network(url)
    }

    static func proxyURL(for urlString: String) -> URL? {
        guard !urlString.hasPrefix("data:"), !urlString.contains("images.weserv.nl"),
              let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return URL(string: "https://images.weserv.nl/?url=\(encoded)")
    }

    static func modifier(for urlString: String, sourceURL: String?, headers: [String: String]?) -> AnyModifier {
        let h = DownloadHeaders.preview(for: urlString, sourceURL: sourceURL, extra: headers)
        return AnyModifier { request in
            var r = request
            // The weserv proxy must not receive the original CDN's Referer
            guard r.url?.host?.contains("weserv.nl") != true else { return r }
            h.forEach { r.setValue($0.value, forHTTPHeaderField: $0.key) }
            return r
        }
    }

    /// Full-resolution image (used for PDF export).
    static func image(for urlString: String, sourceURL: String?, headers: [String: String]? = nil) async throws -> UIImage {
        let options: KingfisherOptionsInfo = [.requestModifier(modifier(for: urlString, sourceURL: sourceURL, headers: headers))]
        if let source = source(for: urlString) {
            if let result = try? await KingfisherManager.shared.retrieveImage(with: source, options: options) {
                return result.image
            }
        }
        guard let proxy = proxyURL(for: urlString) else { throw URLError(.cannotDecodeContentData) }
        return try await KingfisherManager.shared.retrieveImage(with: .network(proxy)).image
    }

    // MARK: Cache

    static func diskCacheSize() async -> UInt {
        (try? await ImageCache.default.diskStorageSize) ?? 0
    }

    /// Clears Kingfisher (memory + disk) plus every legacy cache location.
    static func clearAllCaches() async {
        ImageCache.default.clearMemoryCache()
        await ImageCache.default.clearDiskCache()
        URLCache.shared.removeAllCachedResponses()
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: caches.appendingPathComponent("ImageCache"))
    }
}

/// SwiftUI remote image with CDN headers, downsampling, caching and proxy fallback.
struct RemoteImage: View {
    let url: String?
    var sourceURL: String?
    var headers: [String: String]? = nil
    var maxPixel: CGFloat? = 600
    var contentMode: SwiftUI.ContentMode = .fill

    @State private var useProxy = false
    @State private var failed = false

    var body: some View {
        if let url, !url.isEmpty, !failed, let source = currentSource(url) {
            KFImage(source: source)
                .requestModifier(ImageLoader.modifier(for: url, sourceURL: sourceURL, headers: headers))
                .setProcessor(maxPixel.map { DownsamplingImageProcessor(size: CGSize(width: $0, height: $0)) as ImageProcessor }
                              ?? DefaultImageProcessor.default)
                .scaleFactor(UIScreen.main.scale)
                .cacheOriginalImage()
                .placeholder { Rectangle().fill(.quaternary).overlay(ProgressView()) }
                .onFailure { _ in
                    if !useProxy, ImageLoader.proxyURL(for: url) != nil { useProxy = true } else { failed = true }
                }
                .fade(duration: 0.2)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .id("\(url)#\(useProxy)")
        } else {
            Rectangle().fill(.quaternary)
                .overlay(Image(systemName: "photo").font(.title2).foregroundStyle(.secondary))
        }
    }

    private func currentSource(_ url: String) -> Source? {
        if useProxy, let proxy = ImageLoader.proxyURL(for: url) { return .network(proxy) }
        return ImageLoader.source(for: url)
    }
}
