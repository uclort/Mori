import Foundation

/// Bundled + over-the-air (OTA) scraper core management.
/// OTA patches come from the upstream repository so scraper fixes ship without an app update.
enum EngineStore {
    static let versionURL = URL(string: "https://raw.githubusercontent.com/coflyn/Mori/main/public/scrapers-version.json")!
    static let bundleURL = URL(string: "https://raw.githubusercontent.com/coflyn/Mori/main/public/js/scrapers/bundle.js")!

    struct Manifest: Codable {
        var scraperVersion: Int
        var updatedAt: Double?
        var minAppVersion: String?
        var changelog: String?
    }

    struct Source {
        let text: String
        let version: Int
        let isOTA: Bool
    }

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Engine", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var otaBundleFile: URL { directory.appendingPathComponent("bundle.js") }
    private static var otaManifestFile: URL { directory.appendingPathComponent("manifest.json") }

    static var bundledManifest: Manifest {
        if let url = Bundle.main.url(forResource: "scrapers-version", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let m = try? JSONDecoder().decode(Manifest.self, from: data) {
            return m
        }
        return Manifest(scraperVersion: 5)
    }

    static var otaManifest: Manifest? {
        guard let data = try? Data(contentsOf: otaManifestFile) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    static func activeBundle() -> Source {
        let bundled = bundledManifest.scraperVersion
        if let ota = otaManifest, ota.scraperVersion >= bundled,
           let text = try? String(contentsOf: otaBundleFile, encoding: .utf8), text.count > 5000 {
            return Source(text: text, version: ota.scraperVersion, isOTA: true)
        }
        let url = Bundle.main.url(forResource: "bundle", withExtension: "js")
        let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return Source(text: text, version: bundled, isOTA: false)
    }

    static func removeOTA() {
        try? FileManager.default.removeItem(at: otaBundleFile)
        try? FileManager.default.removeItem(at: otaManifestFile)
    }

    enum UpdateResult {
        case upToDate(Int)
        case updated(Int, String?)
    }

    /// Checks the remote manifest and installs a newer core if one exists.
    static func checkForUpdate() async throws -> UpdateResult {
        var req = URLRequest(url: versionURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, _) = try await URLSession.shared.data(for: req)
        let remote = try JSONDecoder().decode(Manifest.self, from: data)
        let current = max(bundledManifest.scraperVersion, otaManifest?.scraperVersion ?? 0)
        guard remote.scraperVersion > current else { return .upToDate(current) }

        var bundleReq = URLRequest(url: bundleURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        bundleReq.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (bundleData, _) = try await URLSession.shared.data(for: bundleReq)
        guard let text = String(data: bundleData, encoding: .utf8), text.count > 5000,
              text.contains("__MoriCoreScrapers") else {
            throw EngineError(message: "Invalid engine payload")
        }
        try bundleData.write(to: otaBundleFile, options: .atomic)
        try JSONEncoder().encode(remote).write(to: otaManifestFile, options: .atomic)
        return .updated(remote.scraperVersion, remote.changelog)
    }
}
