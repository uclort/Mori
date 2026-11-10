import SwiftUI

struct ResultRoute: Hashable {
    let id = UUID()
    let url: String
    let platform: Platform?
    let result: MediaResult
}

struct ServerPrompt: Identifiable {
    let id = UUID()
    let url: String
    let platform: Platform?
    let sources: [String]
}

@MainActor
final class AnalyzeModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case analyzing
        case failed(String)
    }

    @Published var input = ""
    @Published var phase: Phase = .idle
    @Published var path: [ResultRoute] = []
    @Published var serverPrompt: ServerPrompt?
    @Published var batch: BatchSession?

    private var task: Task<Void, Never>?

    var isAnalyzing: Bool { phase == .analyzing }

    func analyze() {
        let urls = URLExtractor.urls(in: input)
        if urls.count > 1 {
            let session = BatchSession(urls: urls)
            batch = session
            session.start()
            return
        }
        let target = urls.first ?? input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        run(url: target, source: nil)
    }

    func analyze(url: String) {
        input = url
        run(url: url, source: nil)
    }

    func choose(source: String, for prompt: ServerPrompt) {
        run(url: prompt.url, source: source)
    }

    #if DEBUG
    /// UI-test fixture: a 7-photo post with public sample images.
    func showDemoPhotos() {
        let photos = (1...7).map { MediaDownload(type: "PHOTO", url: "https://picsum.photos/seed/mori\($0)/900/1200.jpg") }
        let result = MediaResult(title: "Demo photo post", author: "Mori", thumbnail: photos[0].url,
                                 downloads: photos, sourceUrl: "https://www.douyin.com/note/0")
        path.append(ResultRoute(url: result.sourceUrl, platform: .douyin, result: result))
    }
    #endif

    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    private func run(url: String, source: String?) {
        task?.cancel()
        phase = .analyzing
        Haptics.tap()
        task = Task {
            do {
                let outcome = try await ScraperEngine.shared.analyze(url: url, source: source)
                guard !Task.isCancelled else { return }
                switch outcome {
                case .success(let result, let platform):
                    phase = .idle
                    HistoryStore.shared.add(url: url, platform: platform, result: result)
                    path.append(ResultRoute(url: url, platform: platform, result: result))
                    input = ""
                    if AppSettings.shared.autoDownload, let first = result.downloads.first {
                        DownloadManager.shared.start(DownloadRequest(item: first, title: result.itemTitle(for: first),
                                                                     sourceURL: result.sourceUrl, platform: platform))
                    }
                case .requireSource(let platform, let sources):
                    phase = .idle
                    serverPrompt = ServerPrompt(url: url, platform: platform, sources: sources)
                case .failure(let message):
                    phase = .failed(message)
                    Haptics.error()
                }
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
                Haptics.error()
            }
        }
    }
}

/// Multi-link batch analyze + download (server 1 with automatic server 2 fallback).
@MainActor
final class BatchSession: ObservableObject, Identifiable {
    enum ItemState: Equatable {
        case pending, analyzing, ready, failed(String)
    }

    struct Item: Identifiable {
        let id = UUID()
        let url: String
        var state: ItemState = .pending
        var result: MediaResult?
        var platform: Platform?
    }

    let id = UUID()
    @Published var items: [Item]
    @Published var isAnalyzing = false
    @Published var isDownloading = false
    private var task: Task<Void, Never>?

    init(urls: [String]) {
        items = urls.map { Item(url: $0) }
    }

    var readyCount: Int { items.filter { $0.state == .ready }.count }
    var doneCount: Int { items.filter { $0.state != .pending && $0.state != .analyzing }.count }

    func start() {
        isAnalyzing = true
        task = Task {
            for i in items.indices {
                if Task.isCancelled { break }
                items[i].state = .analyzing
                do {
                    let outcome = try await ScraperEngine.shared.analyze(url: items[i].url, prefer: "auto")
                    switch outcome {
                    case .success(let result, let platform):
                        items[i].result = result
                        items[i].platform = platform
                        items[i].state = .ready
                        HistoryStore.shared.add(url: items[i].url, platform: platform, result: result)
                    case .requireSource:
                        items[i].state = .failed(String(localized: "Server selection required"))
                    case .failure(let msg):
                        items[i].state = .failed(msg)
                    }
                } catch {
                    items[i].state = .failed(error.localizedDescription)
                }
            }
            isAnalyzing = false
        }
    }

    func cancel() {
        task?.cancel()
        isAnalyzing = false
    }

    /// Downloads the primary video of each post (or its audio when "Batch media format" is
    /// set to audio only), every track/photo for albums and photo posts.
    func downloadAll() {
        isDownloading = true
        let preferAudio = AppSettings.shared.batchFormat == .audio
        var requests: [DownloadRequest] = []
        for item in items {
            guard let result = item.result else { continue }
            let list = result.downloads.filter { !$0.isMirror }
            let isVideoPost = list.contains { $0.isVideo }
            let picks: [MediaDownload]
            if isVideoPost {
                let audio = preferAudio ? list.first(where: { $0.isAudio && !$0.isVideo }) : nil
                picks = [audio ?? list[0]]
            } else {
                picks = result.isMultiItem ? list : Array(list.prefix(1))
            }
            requests += picks.map {
                DownloadRequest(item: $0, title: result.itemTitle(for: $0),
                                sourceURL: result.sourceUrl, platform: item.platform)
            }
        }
        Task {
            _ = await DownloadManager.shared.startAll(requests)
            isDownloading = false
        }
    }
}
