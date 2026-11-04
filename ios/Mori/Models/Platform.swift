import SwiftUI

/// Supported platforms. Raw values match the keys used by EngineHost.js.
enum Platform: String, CaseIterable, Identifiable, Codable {
    case tiktok, instagram, youtube, twitter, spotify, pinterest, applemusic, facebook
    case rednote, douyin, bilibili, threads, bandcamp, pixiv, reddit, terabox

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiktok: return "TikTok"
        case .instagram: return "Instagram"
        case .youtube: return "YouTube"
        case .twitter: return "X / Twitter"
        case .spotify: return "Spotify"
        case .pinterest: return "Pinterest"
        case .applemusic: return "Apple Music"
        case .facebook: return "Facebook"
        case .rednote: return String(localized: "RedNote")
        case .douyin: return String(localized: "Douyin")
        case .bilibili: return "Bilibili"
        case .threads: return "Threads"
        case .bandcamp: return "Bandcamp"
        case .pixiv: return "Pixiv"
        case .reddit: return "Reddit"
        case .terabox: return "TeraBox"
        }
    }

    /// Compact name for dense layouts.
    var shortName: String { self == .twitter ? "X" : displayName }

    var systemImage: String {
        switch self {
        case .tiktok, .douyin: return "music.note.tv"
        case .instagram: return "camera"
        case .youtube: return "play.rectangle.fill"
        case .twitter: return "xmark"
        case .spotify: return "dot.radiowaves.left.and.right"
        case .pinterest: return "pin.fill"
        case .applemusic: return "music.note"
        case .facebook: return "f.cursive"
        case .rednote: return "book.closed.fill"
        case .bilibili: return "tv"
        case .threads: return "at"
        case .bandcamp: return "opticaldisc"
        case .pixiv: return "paintbrush.pointed.fill"
        case .reddit: return "bubble.left.and.bubble.right.fill"
        case .terabox: return "externaldrive.fill.badge.icloud"
        }
    }

    var tint: Color {
        switch self {
        case .tiktok: return Color(red: 0.0, green: 0.95, blue: 0.92)
        case .douyin: return Color(red: 0.99, green: 0.17, blue: 0.33)
        case .instagram: return Color(red: 0.88, green: 0.19, blue: 0.42)
        case .youtube: return .red
        case .twitter: return .primary
        case .spotify: return Color(red: 0.11, green: 0.73, blue: 0.33)
        case .pinterest: return Color(red: 0.90, green: 0.0, blue: 0.14)
        case .applemusic: return Color(red: 0.98, green: 0.24, blue: 0.33)
        case .facebook: return Color(red: 0.09, green: 0.47, blue: 0.95)
        case .rednote: return Color(red: 1.0, green: 0.14, blue: 0.26)
        case .bilibili: return Color(red: 0.0, green: 0.68, blue: 0.93)
        case .threads: return .primary
        case .bandcamp: return Color(red: 0.38, green: 0.6, blue: 0.67)
        case .pixiv: return Color(red: 0.0, green: 0.59, blue: 0.98)
        case .reddit: return Color(red: 1.0, green: 0.27, blue: 0.0)
        case .terabox: return Color(red: 0.2, green: 0.45, blue: 1.0)
        }
    }

    /// Whether the platform offers a Server 1 / Server 2 choice.
    var hasServerChoice: Bool {
        [.tiktok, .instagram, .youtube, .twitter, .spotify].contains(self)
    }

    var serverDescription: String {
        switch self {
        case .tiktok:
            return String(localized: "Server 1: TikTokIO (HD Video · MP3 · Photo Slideshow)\nServer 2: TikDownloader (Full HD 1080p · MP3 · Photo Slideshow)")
        case .instagram:
            return String(localized: "Server 1: InDown (Multi Quality MP4 / Photos)\nServer 2: SaveVid (Fast MP4 / Story / Reel)")
        case .youtube:
            return String(localized: "Server 1: YTMP3.gg (Multi Resolution 1080p - 360p + MP3)\nServer 2: YTMP3.mobi (Fast & Stable MP4 / MP3)")
        case .twitter:
            return String(localized: "Server 1: TVD (Full HD 1080p · 720p · Multi-Res)\nServer 2: SaveTWT (HD MP4 · Multi-Res)")
        case .spotify:
            return String(localized: "Server 1: SpotiDown (Playlist & Single Track)\nServer 2: SoundLoaders (Playlist & Single Track)")
        default:
            return ""
        }
    }

    /// Best-effort platform detection from any URL (same rules as the engine).
    static func detect(_ url: String) -> Platform? {
        let u = url.lowercased()
        if u.contains("tiktok.com") || u.contains("tt.site") { return .tiktok }
        if u.contains("instagram.com") { return .instagram }
        if u.contains("youtube.com") || u.contains("youtu.be") { return .youtube }
        if u.contains("twitter.com") || u.range(of: #"(?:^|[/.])x\.com(?:[/?#:]|$)"#, options: .regularExpression) != nil
            || u.contains("fixupx.com") || u.contains("fxtwitter.com") || u.contains("vxtwitter.com") { return .twitter }
        if u.contains("spotify.com") { return .spotify }
        if u.contains("pinterest.com") || u.contains("pin.it") { return .pinterest }
        if u.contains("music.apple.com") { return .applemusic }
        if u.contains("facebook.com") || u.contains("fb.watch") { return .facebook }
        if u.contains("xiaohongshu.com") || u.contains("rednote.com") || u.contains("xhslink.com") || u.contains("xhslink.cn") { return .rednote }
        if u.contains("douyin.com") { return .douyin }
        if u.contains("bilibili.com") || u.contains("b23.tv") || u.contains("bili.im") || u.contains("bilibili.tv") { return .bilibili }
        if u.contains("threads.net") || u.contains("threads.com") { return .threads }
        if u.contains("bandcamp.com") { return .bandcamp }
        if u.contains("pixiv.net") { return .pixiv }
        if u.contains("reddit.com") || u.contains("redd.it") { return .reddit }
        if u.range(of: "terabox|1024tera|nephobox|4funbox|mirrobox|momerybox|tibibox", options: .regularExpression) != nil { return .terabox }
        return nil
    }
}

enum URLExtractor {
    /// All http(s) links found in arbitrary share text, de-duplicated, in order.
    static func urls(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s"'<>，。]+"#, options: .caseInsensitive) else { return [] }
        let ns = text as NSString
        var seen = Set<String>()
        var out: [String] = []
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var s = ns.substring(with: m.range)
            while let last = s.last, ",.;)]}".contains(last) { s.removeLast() }
            if seen.insert(s).inserted { out.append(s) }
        }
        return out
    }

    static func firstURL(in text: String) -> String? { urls(in: text).first }
}
