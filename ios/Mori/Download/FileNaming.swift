import Foundation

/// File name / extension / folder rules (ported from downloader/filename.js).
enum FileNaming {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "heic", "heif", "avif", "bmp"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi"]
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"]

    static func isAudio(type: String) -> Bool {
        type.range(of: "mp3|audio|128k|48k|m4a|wav|flac", options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func resolveExtension(type: String, url: String) -> String {
        let typeStr = type.lowercased()
        let urlLower = url.lowercased()
        let isImage = typeStr.range(of: "image|photo|jpg|jpeg|png|webp", options: .regularExpression) != nil
            || urlLower.range(of: #"\.(jpg|jpeg|png|webp)"#, options: .regularExpression) != nil
        var ext = isAudio(type: type) ? "mp3" : (isImage ? "jpg" : "mp4")

        func urlHas(_ e: String) -> Bool { urlLower.range(of: "\\.\(e)(\\?|$)", options: .regularExpression) != nil }
        if urlHas("png") || typeStr.contains("png") { ext = "png" }
        else if urlHas("webp") || typeStr.contains("webp") { ext = "webp" }
        else if urlHas("m4a") || typeStr.contains("m4a") { ext = "m4a" }
        else if urlHas("mp3") || typeStr.contains("mp3") { ext = "mp3" }
        else if urlHas("jpe?g") || typeStr.contains("jpg") || typeStr.contains("jpeg") { ext = "jpg" }
        else if urlHas("mp4") || typeStr.contains("video") || typeStr.contains("mp4")
                    || typeStr.range(of: #"\d+p"#, options: .regularExpression) != nil { ext = "mp4" }

        let probe = typeStr.isEmpty ? urlLower : typeStr
        if let r = probe.range(of: #"\.([a-z0-9]{2,5})(?:\?|$)"#, options: .regularExpression) {
            let candidate = String(probe[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".?"))
            if !["html", "htm", "php", "asp", "aspx", "jsp", "com", "net", "org"].contains(candidate) { ext = candidate }
        }

        // CDN pseudo extensions (Douyin "~tplv-…:q75.image", ".awebp") → real image extension
        if type.range(of: "image|photo", options: [.regularExpression, .caseInsensitive]) != nil,
           !imageExtensions.contains(ext.lowercased()) {
            if ext.contains("webp") { ext = "webp" }
            else if ext.contains("heic") { ext = "heic" }
            else { ext = "jpg" }
        }
        return ext.lowercased()
    }

    /// Picks a better extension from the server's MIME type when the guess is clearly wrong.
    static func correctedExtension(_ ext: String, mimeType: String?) -> String {
        guard let mime = mimeType?.lowercased() else { return ext }
        let table: [String: String] = [
            "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/gif": "gif", "image/heic": "heic",
            "video/mp4": "mp4", "video/quicktime": "mov", "audio/mpeg": "mp3", "audio/mp4": "m4a", "audio/x-m4a": "m4a",
            "application/pdf": "pdf",
        ]
        guard let real = table[mime] else { return ext }
        let sameFamily = (imageExtensions.contains(ext) && mime.hasPrefix("image/"))
            || (videoExtensions.contains(ext) && mime.hasPrefix("video/"))
            || (audioExtensions.contains(ext) && mime.hasPrefix("audio/"))
        if sameFamily && real != ext && !(ext == "jpeg" && real == "jpg") {
            return real
        }
        if !sameFamily && (mime.hasPrefix("image/") || mime.hasPrefix("video/") || mime.hasPrefix("audio/")) {
            return real
        }
        return ext
    }

    static func sanitizeTitle(_ title: String, type: String) -> String {
        let item = MediaDownload(type: type, url: "x")
        var effective = title.isEmpty ? "Mori Media" : title
        if item.isTrack { effective = item.trackTitle }
        var s = effective.replacingOccurrences(of: #"[\\/:*?"<>|#%&{}\[\]@$^+=~`';,]"#, with: "", options: .regularExpression)
        // Keep letters (any script), numbers, spaces, - _ .
        s = String(s.unicodeScalars.filter {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
                || CharacterSet.whitespaces.contains($0) || "-_.".unicodeScalars.contains($0)
        }.map(Character.init))
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if s.count > 60 { s = String(s.prefix(60)).trimmingCharacters(in: .whitespaces) }
        return s.isEmpty ? "Mori_Media" : s
    }

    /// Builds the file name from the selected template.
    /// - Parameter consumeCounter: `false` only peeks the next `{num}` (used for the pre-download
    ///   "already exists" check); the final name passes `true` to advance the per-platform counter.
    static func fileName(title: String, ext: String, platform: Platform?, type: String = "", url: String = "",
                         consumeCounter: Bool = false) -> String {
        let cleanExt = ext.lowercased()
        var clean = title
        if clean.lowercased().hasSuffix("." + cleanExt) { clean = String(clean.dropLast(cleanExt.count + 1)) }
        let pattern = AppSettings.shared.filenameTemplate.pattern
        let platformName = platform == nil ? "Media" : platformFolder(platform)
        let now = Date()
        func fmt(_ f: String) -> String {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = f
            return df.string(from: now)
        }
        var name = pattern
            .replacingOccurrences(of: "{title}", with: clean)
            .replacingOccurrences(of: "{platform}", with: platformName)
            .replacingOccurrences(of: "{date}", with: fmt("yyyy-MM-dd"))
            .replacingOccurrences(of: "{time}", with: fmt("HH-mm-ss"))
            .replacingOccurrences(of: "{quality}", with: quality(type: type, url: url))
            .replacingOccurrences(of: "{timestamp}", with: String(Int(now.timeIntervalSince1970 * 1000)))
        if name.contains("{num}") {
            name = name.replacingOccurrences(of: "{num}", with: counter(for: platformName, consume: consumeCounter))
        }
        name = name.replacingOccurrences(of: #"[\\/:*?"<>|]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = clean.isEmpty ? "Mori_Media" : clean }
        return "\(name).\(cleanExt)"
    }

    /// "1080p", "720p", "4k", "320kbps"… from the media label / URL, or "na".
    static func quality(type: String, url: String) -> String {
        let raw = "\(type) \(url)"
        let patterns = [
            #"(?:^|[^a-z0-9])(2160p|1440p|1080p|720p|480p|360p|240p|144p|8k|4k|2k|hd|sd)(?:[^a-z0-9]|$)"#,
            #"(?:^|[^a-z0-9])(\d{2,3}k(?:bps)?)(?:[^a-z0-9]|$)"#,
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
               let m = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
               let r = Range(m.range(at: 1), in: raw) {
                return raw[r].lowercased()
            }
        }
        return "na"
    }

    /// Persistent running number per platform, zero-padded to 3 digits ("001").
    static func counter(for platformName: String, consume: Bool) -> String {
        let key = "counter_\(platformName.lowercased())"
        let next = max(0, UserDefaults.standard.integer(forKey: key)) + 1
        if consume { UserDefaults.standard.set(next, forKey: key) }
        return String(format: "%03d", next)
    }

    /// Sub-folder per platform (same names the Capacitor build used, so old files stay grouped).
    static func platformFolder(_ platform: Platform?) -> String {
        switch platform {
        case .tiktok?, .douyin?: return "TikTok"
        case .instagram?: return "Instagram"
        case .youtube?: return "YouTube"
        case .twitter?: return "Twitter"
        case .facebook?: return "Facebook"
        case .pinterest?: return "Pinterest"
        case .spotify?: return "Spotify"
        case .applemusic?: return "AppleMusic"
        case .threads?: return "Threads"
        case .rednote?: return "RedNote"
        case .bilibili?: return "Bilibili"
        case .pixiv?: return "Pixiv"
        case .bandcamp?: return "Bandcamp"
        case .reddit?: return "Reddit"
        case .terabox?: return "TeraBox"
        case nil: return "Other"
        }
    }
}

/// On-disk layout inside the app's Documents folder (visible in the Files app).
enum StorageLocations {
    static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    /// Videos, photos and PDFs — kept identical to the Capacitor build ("Download/Mori").
    static var media: URL { documents.appendingPathComponent("Download/Mori", isDirectory: true) }
    /// Audio — "Music/Mori".
    static var music: URL { documents.appendingPathComponent("Music/Mori", isDirectory: true) }

    static func folder(isAudio: Bool, platform: Platform?) -> URL {
        var dir = isAudio ? music : media
        if AppSettings.shared.autoPlatformFolder {
            dir.appendPathComponent(FileNaming.platformFolder(platform), isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    enum Resolution {
        case use(URL)
        case skip(URL)
    }

    static func destination(in dir: URL, fileName: String) -> Resolution {
        let fm = FileManager.default
        let target = dir.appendingPathComponent(fileName)
        guard fm.fileExists(atPath: target.path) else { return .use(target) }
        switch AppSettings.shared.overwriteMode {
        case .skip: return .skip(target)
        case .overwrite: return .use(target)
        case .rename:
            let base = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
            var i = 1
            while true {
                let candidate = dir.appendingPathComponent(ext.isEmpty ? "\(base)_\(i)" : "\(base)_\(i).\(ext)")
                if !fm.fileExists(atPath: candidate.path) { return .use(candidate) }
                i += 1
            }
        }
    }
}
