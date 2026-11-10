import Foundation

/// Platform-specific Referer / Origin headers required by media CDNs (ported from downloader/headers.js).
enum DownloadHeaders {
    /// Unwraps proxy links such as `pindown.io/...?file=<real url>`.
    static func cleanDownloadURL(_ url: String) -> String {
        guard url.contains("pindown.io"), url.contains("file=") else { return url }
        let pattern = #"file=(https?%3A%2F%2F[^&]+|https?://[^&]+)"#
        guard let range = url.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return url }
        let value = String(url[range].dropFirst("file=".count))
        return value.removingPercentEncoding ?? value
    }

    static func build(for downloadURL: String, sourceURL: String?, extra: [String: String]? = nil) -> [String: String] {
        var h = baseHeaders(for: downloadURL, sourceURL: sourceURL)
        // Headers supplied by the scraper for this specific item win (case-insensitive)
        for (key, value) in extra ?? [:] {
            h.keys.filter { $0.caseInsensitiveCompare(key) == .orderedSame }.forEach { h[$0] = nil }
            h[key] = value
        }
        return h
    }

    private static func baseHeaders(for downloadURL: String, sourceURL: String?) -> [String: String] {
        let d = downloadURL
        let src = sourceURL ?? ""
        let isX = src.range(of: #"(?:^|[/.])x\.com(?:[/?#:]|$)"#, options: [.regularExpression, .caseInsensitive]) != nil

        // convert1s/ytmp3.gg rotate through throwaway *.shop CDN domains
        let isYtmp3GG = d.contains("ytmp3.gg") || d.contains("convert1s.com") || d.contains(".shop/")
        let isYoutube = isYtmp3GG || d.contains("ytmp3.mobi") || d.contains("ytdown") || d.contains("ymcdn.org")
            || src.contains("youtube.com") || src.contains("youtu.be")
        let isTwitter = d.contains("tweeload") || d.contains("savetwt") || d.contains("twimg.com") || d.contains("acxcdn.com")
            || src.contains("twitter") || isX
        let isPixiv = d.contains("pixiv.net") || d.contains("pximg.net") || d.contains("pixiv.re")
        let isUgoira = d.contains("ugoira")
        let isBilibili = d.contains("bilibili") || d.contains("bilivideo") || d.contains("bstarstatic") || d.contains("akamaized.net")
            || src.contains("bilibili") || src.contains("b23.tv") || src.contains("bili.im")
        let isPinterest = d.contains("pindown.io") || d.contains("pinimg.com") || src.contains("pinterest.com") || src.contains("pin.it")

        var h: [String: String] = [
            "User-Agent": AppSettings.shared.downloadUserAgent,
            "Accept-Encoding": "identity",
        ]

        if isYtmp3GG {
            h["Referer"] = "https://media.ytmp3.gg/"
            h["Origin"] = "https://media.ytmp3.gg"
        } else if isYoutube {
            h["Referer"] = "https://ytmp3.mobi/"
            if d.contains("ymcdn.org") || d.contains("ytmp3.mobi") { h["Origin"] = "https://ytmp3.mobi" }
        }
        if isPixiv { h["Referer"] = "https://www.pixiv.net/" }
        if isUgoira { h["Referer"] = "https://ugoira.com/" }
        if isBilibili {
            h["Referer"] = (src.contains("bilibili.com") || src.contains("b23.tv") || d.contains("bilivideo.com"))
                ? "https://www.bilibili.com/" : "https://www.bilibili.tv/"
        }
        if isPinterest {
            h["Referer"] = d.contains("pindown.io") ? "https://pindown.io/" : "https://www.pinterest.com/"
        }
        if isTwitter {
            if d.contains("twimg.com") { h["Referer"] = "https://twitter.com/" }
            else if d.contains("tweeload") { h["Referer"] = "https://tweeload.com/" }
            else { h["Referer"] = "https://savetwt.com/" }
        }
        if d.contains("spotidown") || src.contains("spotify") {
            h["Referer"] = "https://spotidown.app/"
            h["Origin"] = "https://spotidown.app"
            h["Accept"] = "*/*"
        }
        if d.contains("soundloaders") || d.contains("spotimate") {
            h["Referer"] = "https://spotimate.app/"
            h["Origin"] = "https://spotimate.app"
            h["Accept"] = "*/*"
        }
        if d.contains("aplmate") { h["Referer"] = "https://aplmate.com/" }
        // Douyin / RedNote / Instagram CDNs reject foreign referers but accept none
        if h["Referer"] == nil {
            if d.contains("douyin") || d.contains("douyinvod") || d.contains("douyinpic") || src.contains("douyin") {
                h["Referer"] = "https://www.douyin.com/"
            } else if d.contains("xhscdn") || src.contains("xiaohongshu") || src.contains("xhslink") {
                h["Referer"] = "https://www.xiaohongshu.com/"
            }
        }
        return h
    }

    /// Headers used for previews (thumbnails, video streaming).
    static func preview(for url: String, sourceURL: String?, extra: [String: String]? = nil) -> [String: String] {
        var h = build(for: url, sourceURL: sourceURL, extra: extra)
        h["Accept-Encoding"] = nil
        if url.contains("cdninstagram") || url.contains("fbcdn") {
            h["Referer"] = "https://www.instagram.com/"
        }
        return h
    }
}
