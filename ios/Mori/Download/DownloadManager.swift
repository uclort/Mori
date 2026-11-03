import SwiftUI
import UIKit

struct DownloadRequest: Hashable {
    var url: String
    var type: String
    var title: String
    var sourceURL: String
    var platform: Platform?
    var headers: [String: String]? = nil

    init(item: MediaDownload, title: String, sourceURL: String, platform: Platform?) {
        self.init(url: item.url, type: item.type, title: title, sourceURL: sourceURL, platform: platform, headers: item.headers)
    }

    init(url: String, type: String, title: String, sourceURL: String, platform: Platform?, headers: [String: String]? = nil) {
        self.url = url
        self.type = type
        self.title = title
        self.sourceURL = sourceURL
        self.platform = platform
        self.headers = headers
    }
}

@MainActor
final class DownloadItem: ObservableObject, Identifiable {
    enum Status: Equatable {
        case queued, resolving, downloading, saving, completed, skipped, cancelled
        case failed(String)

        var isActive: Bool { [.queued, .resolving, .downloading, .saving].contains(self) }
        var isFinished: Bool { !isActive }
    }

    let id = UUID().uuidString
    let request: DownloadRequest
    let createdAt = Date()
    @Published var status: Status = .queued
    @Published var progress: Double = 0
    @Published var detail: String = ""
    @Published var fileURL: URL?
    @Published var savedToPhotos = false
    fileprivate var task: Task<Void, Never>?

    init(request: DownloadRequest) { self.request = request }

    var displayTitle: String {
        let t = MediaDownload(type: request.type, url: request.url)
        return t.isTrack ? t.trackTitle : request.title
    }
}

/// Queue of native downloads with a configurable concurrency limit.
@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var items: [DownloadItem] = []
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var activeItems: [DownloadItem] { items.filter { $0.status.isActive } }
    var hasActive: Bool { items.contains { $0.status.isActive } }

    var overallProgress: Double {
        let active = activeItems
        guard !active.isEmpty else { return 1 }
        return active.map(\.progress).reduce(0, +) / Double(active.count)
    }

    /// Latest item for a given media URL (used by result rows to show state).
    func item(for url: String) -> DownloadItem? {
        items.last { $0.request.url == url }
    }

    @discardableResult
    func start(_ request: DownloadRequest) -> DownloadItem {
        if let existing = item(for: request.url), existing.status.isActive { return existing }
        let item = DownloadItem(request: request)
        items.append(item)
        item.task = Task { [weak self] in
            await self?.run(item)
        }
        objectWillChange.send()
        return item
    }

    /// Starts several downloads and waits for all of them.
    func startAll(_ requests: [DownloadRequest]) async -> (succeeded: Int, failed: Int) {
        let started = requests.map { start($0) }
        for item in started { await item.task?.value }
        let ok = started.filter { $0.status == .completed || $0.status == .skipped }.count
        let failed = started.filter { if case .failed = $0.status { return true } else { return false } }.count
        return (ok, failed)
    }

    func cancel(_ item: DownloadItem) {
        item.task?.cancel()
        if item.status == .queued { item.status = .cancelled }
    }

    func cancelAll() { activeItems.forEach(cancel) }

    func retry(_ item: DownloadItem) {
        items.removeAll { $0.id == item.id }
        start(item.request)
    }

    func clearFinished() {
        items.removeAll { $0.status.isFinished }
    }

    // MARK: Concurrency gate

    private var limit: Int { min(5, max(1, AppSettings.shared.concurrentDownloads)) }

    private func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        } else {
            running = max(0, running - 1)
        }
    }

    // MARK: Pipeline

    private func run(_ item: DownloadItem) async {
        await acquire()
        defer { release() }
        guard !Task.isCancelled else {
            item.status = .cancelled
            return
        }

        let bgTask = UIApplication.shared.beginBackgroundTask(withName: "MoriDownload") {}
        defer { UIApplication.shared.endBackgroundTask(bgTask) }

        let req = item.request
        do {
            // 1. Resolve indirect links through the scraper engine
            var mediaURL = req.url
            if ScraperEngine.shared.needsResolving(mediaURL) {
                item.status = .resolving
                item.detail = String(localized: "Resolving link…")
                let resolved = try await ScraperEngine.shared.resolve(url: mediaURL, taskID: item.id) { pct, text in
                    item.progress = min(0.3, pct / 100 * 0.3)
                    if !text.isEmpty { item.detail = text }
                }
                guard let resolved else { throw CancellationError() }
                mediaURL = resolved
            }
            try Task.checkCancellation()
            mediaURL = DownloadHeaders.cleanDownloadURL(mediaURL)

            guard let url = URL(string: mediaURL)
                    ?? URL(string: mediaURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else {
                throw FileDownloader.DownloadError(message: String(localized: "Invalid download link"))
            }

            // 2. Destination
            let isAudio = FileNaming.isAudio(type: req.type)
            var ext = FileNaming.resolveExtension(type: req.type, url: mediaURL)
            let title = FileNaming.sanitizeTitle(req.title, type: req.type)
            let folder = StorageLocations.folder(isAudio: isAudio, platform: req.platform)
            if case .skip(let existing) = StorageLocations.destination(in: folder, fileName: FileNaming.fileName(title: title, ext: ext, platform: req.platform)) {
                item.fileURL = existing
                item.progress = 1
                item.status = .skipped
                item.detail = String(localized: "Already downloaded")
                return
            }

            // 3. Download
            item.status = .downloading
            item.detail = String(localized: "Connecting…")
            var request = URLRequest(url: url)
            DownloadHeaders.build(for: mediaURL, sourceURL: req.sourceURL, extra: req.headers).forEach {
                request.setValue($0.value, forHTTPHeaderField: $0.key)
            }
            let base = item.progress
            let meter = SpeedMeter()
            let response = try await FileDownloader.shared.download(request) { written, total in
                let text = meter.describe(written: written, total: total)
                Task { @MainActor in
                    if total > 0 {
                        item.progress = base + (1 - base) * min(1, Double(written) / Double(total))
                    } else {
                        item.progress = base + (0.95 - base) * (1 - exp(-Double(written) / 2_500_000))
                    }
                    item.detail = text
                }
            }

            // 4. Move into place
            item.status = .saving
            ext = FileNaming.correctedExtension(ext, mimeType: response.mimeType)
            let finalName = FileNaming.fileName(title: title, ext: ext, platform: req.platform)
            let dest: URL
            switch StorageLocations.destination(in: folder, fileName: finalName) {
            case .use(let u): dest = u
            case .skip(let u):
                try? FileManager.default.removeItem(at: response.fileURL)
                item.fileURL = u
                item.status = .skipped
                return
            }
            if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
            try FileManager.default.moveItem(at: response.fileURL, to: dest)
            item.fileURL = dest

            // 5. Photo library
            let target = AppSettings.shared.saveTarget
            if target != .files, PhotoSaver.canSave(dest) {
                do {
                    try await PhotoSaver.save(dest)
                    item.savedToPhotos = true
                    if target == .photos {
                        try? FileManager.default.removeItem(at: dest)
                        item.fileURL = nil
                    }
                } catch {
                    item.detail = error.localizedDescription
                }
            }

            item.progress = 1
            item.status = .completed
            if !item.savedToPhotos || item.fileURL != nil {
                item.detail = item.savedToPhotos ? String(localized: "Saved to Files & Photos") : String(localized: "Saved")
            } else {
                item.detail = String(localized: "Saved to Photos")
            }
            Haptics.success()
            NotificationCenter.default.post(name: .moriLibraryChanged, object: nil)
        } catch is CancellationError {
            item.status = .cancelled
            item.detail = String(localized: "Cancelled")
        } catch {
            if Task.isCancelled {
                item.status = .cancelled
                item.detail = String(localized: "Cancelled")
            } else {
                let msg = (error as NSError).domain == NSURLErrorDomain
                    ? String(localized: "Network connection error") + " (\(error.localizedDescription))"
                    : error.localizedDescription
                item.status = .failed(msg)
                item.detail = msg
                Haptics.error()
            }
        }
    }
}

/// Formats "12.3 MB / 40 MB (2.1 MB/s)".
final class SpeedMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastBytes: Int64 = 0
    private var lastTime = Date()
    private var speed: Double = 0
    private let start = Date()

    func describe(written: Int64, total: Int64) -> String {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        let dt = now.timeIntervalSince(lastTime)
        if dt >= 0.5 {
            speed = Double(written - lastBytes) / dt
            lastBytes = written
            lastTime = now
        }
        let s = speed > 0 ? speed : Double(written) / max(0.001, now.timeIntervalSince(start))
        let f: (Int64) -> String = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        if total > 0 {
            return "\(f(written)) / \(f(total)) (\(f(Int64(s)))/s)"
        }
        return "\(f(written)) (\(f(Int64(s)))/s)"
    }
}

extension Notification.Name {
    static let moriLibraryChanged = Notification.Name("moriLibraryChanged")
}

enum Haptics {
    static func success() {
        guard AppSettings.shared.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        guard AppSettings.shared.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func tap() {
        guard AppSettings.shared.haptics else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
