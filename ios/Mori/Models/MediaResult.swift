import Foundation

/// One downloadable rendition returned by a scraper (a video quality, a photo, an audio track…).
struct MediaDownload: Codable, Hashable, Identifiable {
    var id = UUID()
    var type: String
    var url: String
    var quality: String?
    var isMirror: Bool
    var thumbnail: String?
    /// Extra request headers the scraper says this media needs (e.g. Bilibili's User-Agent).
    var headers: [String: String]?

    init(type: String, url: String, quality: String? = nil, isMirror: Bool = false, thumbnail: String? = nil,
         headers: [String: String]? = nil) {
        self.type = type
        self.url = url
        self.quality = quality
        self.isMirror = isMirror
        self.thumbnail = thumbnail
        self.headers = headers
    }

    init?(json: [String: Any]) {
        let rawURL: String?
        if let s = json["url"] as? String {
            rawURL = s
        } else if let o = json["url"] as? [String: Any] {
            rawURL = (o["url"] as? String) ?? (o["src"] as? String)
        } else {
            rawURL = nil
        }
        guard let url = rawURL, !url.isEmpty else { return nil }
        self.init(type: MediaDownload.string(json["type"]) ?? "Media",
                  url: url,
                  quality: MediaDownload.string(json["quality"]),
                  isMirror: (json["isMirror"] as? Bool) ?? false,
                  thumbnail: MediaDownload.string(json["thumbnail"]),
                  headers: (json["headers"] as? [String: Any])?.compactMapValues { MediaDownload.string($0) })
    }

    private static func string(_ v: Any?) -> String? {
        switch v {
        case let s as String: return s.isEmpty ? nil : s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    /// Display label without raw "[MP3]" / "[MP4]" tags.
    var cleanType: String {
        type.replacingOccurrences(of: #"\s*\[(MP3|MP4|JPG|PNG|WEBP)\]"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    /// Playlist / album entries look like "1. Track name".
    var isTrack: Bool { cleanType.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil }

    var trackTitle: String {
        let t = cleanType.replacingOccurrences(of: #"^\d+\.\s+"#, with: "", options: .regularExpression)
        return t.isEmpty ? cleanType : t
    }

    var displayLabel: String {
        if let q = quality, !q.isEmpty { return "\(cleanType) - \(q)" }
        return cleanType
    }

    var isPhoto: Bool {
        let t = type.uppercased()
        return t.contains("PHOTO") || t.contains("IMAGE") || t.contains("SLIDE") || t.contains("PAGE")
            || url.lowercased().range(of: #"\.(jpg|jpeg|png|webp)"#, options: .regularExpression) != nil
    }

    var isVideo: Bool {
        let t = type.uppercased()
        return t.contains("VIDEO") || t.contains("MP4") || t.range(of: #"\d+P"#, options: .regularExpression) != nil
            || url.lowercased().range(of: #"\.(mp4|mkv|mov|avi)"#, options: .regularExpression) != nil
    }

    var isAudio: Bool {
        type.range(of: "mp3|audio|128k|48k|m4a|wav|flac", options: [.regularExpression, .caseInsensitive]) != nil
    }

    var kind: MediaKind {
        if isAudio { return .audio }
        if isPhoto && !isVideo { return .photo }
        return .video
    }
}

enum MediaKind: String, Codable, CaseIterable {
    case video, photo, audio, pdf, other

    var systemImage: String {
        switch self {
        case .video: return "film"
        case .photo: return "photo"
        case .audio: return "music.note"
        case .pdf: return "doc.richtext"
        case .other: return "doc"
        }
    }
}

struct MediaResult: Codable, Hashable {
    var title: String
    var author: String?
    var thumbnail: String?
    var downloads: [MediaDownload]
    var sourceUrl: String

    init(title: String, author: String?, thumbnail: String?, downloads: [MediaDownload], sourceUrl: String) {
        self.title = title
        self.author = author
        self.thumbnail = thumbnail
        self.downloads = downloads
        self.sourceUrl = sourceUrl
    }

    init(json: [String: Any], fallbackURL: String) {
        let rawTitle = (json["title"] as? String) ?? ""
        title = rawTitle.decodingHTMLEntities.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { title = "Media" }
        author = (json["author"] as? String)?.decodingHTMLEntities
        let thumb = json["thumbnail"] as? String
        // Inline data-URI thumbnails can be huge; keep them only when small
        thumbnail = (thumb?.hasPrefix("data:") == true && (thumb?.count ?? 0) > 25000) ? nil : thumb
        downloads = ((json["downloads"] as? [[String: Any]]) ?? []).compactMap(MediaDownload.init(json:))
        sourceUrl = (json["sourceUrl"] as? String) ?? fallbackURL
    }

    /// Title without hashtags, for display.
    var displayTitle: String {
        title.replacingOccurrences(of: #"#[^\s#]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var photoDownloads: [MediaDownload] { downloads.filter(\.isPhoto) }

    var isPlaylistOrAlbum: Bool {
        let pattern = "playlist|album"
        return sourceUrl.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
            || title.range(of: #"\((Playlist|Album)\)"#, options: [.regularExpression, .caseInsensitive]) != nil
            || downloads.contains(where: \.isTrack)
    }

    var isMultiPhoto: Bool { photoDownloads.count > 1 }

    var isMultiItem: Bool { (isPlaylistOrAlbum || isMultiPhoto) && downloads.count >= 2 }

    /// Images eligible for "Export as PDF".
    var galleryImages: [MediaDownload] {
        downloads.filter { !$0.isMirror && $0.isPhoto && !$0.isVideo }
    }

    /// Per-item title used for file naming (mirrors the web app's behaviour).
    func itemTitle(for item: MediaDownload) -> String {
        if item.isTrack { return item.trackTitle }
        if isMultiPhoto, let idx = photoDownloads.firstIndex(of: item) { return "\(title)_\(idx + 1)" }
        return title
    }
}

enum AnalyzeOutcome {
    case success(MediaResult, platform: Platform?)
    case requireSource(platform: Platform?, sources: [String])
    case failure(message: String)

    init(json: [String: Any]) {
        let platform = (json["platform"] as? String).flatMap(Platform.init(rawValue:))
        if (json["requireSource"] as? Bool) == true {
            self = .requireSource(platform: platform, sources: (json["sources"] as? [String]) ?? [])
            return
        }
        if (json["status"] as? Bool) == true, let result = json["result"] as? [String: Any] {
            let fallback = (json["inputUrl"] as? String) ?? ""
            let media = MediaResult(json: result, fallbackURL: fallback)
            if media.downloads.isEmpty {
                self = .failure(message: "No downloadable media found.")
            } else {
                self = .success(media, platform: platform)
            }
            return
        }
        var message = (json["message"] as? String) ?? "Unknown error occurred."
        if let code = json["statusCode"] as? Int, code == 403 || code == 429 {
            message = String(localized: "IP blocked by the server. Try another server, a VPN or mobile data.")
        }
        self = .failure(message: message)
    }
}

extension String {
    var decodingHTMLEntities: String {
        guard contains("&") else { return self }
        var s = self
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#039;": "'", "&#39;": "'", "&apos;": "'"]
        for (k, v) in map { s = s.replacingOccurrences(of: k, with: v) }
        let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);")
        let ns = s as NSString
        var result = ""
        var last = 0
        regex?.enumerateMatches(in: s, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let isHex = ns.substring(with: m.range(at: 1)) == "x"
            let num = ns.substring(with: m.range(at: 2))
            if let code = UInt32(num, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                result += String(Character(scalar))
            } else {
                result += ns.substring(with: m.range)
            }
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
