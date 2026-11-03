import SwiftUI

struct ResultView: View {
    let url: String
    let platform: Platform?
    let result: MediaResult

    @EnvironmentObject private var downloads: DownloadManager
    @State private var downloadingAll = false
    @State private var allSummary: String?
    @State private var pdfProgress: Double?
    @State private var pdfFile: URL?
    @State private var errorMessage: String?
    @State private var viewer: PhotoViewerState?
    @State private var player: VideoPlayerState?

    var body: some View {
        List {
            Section {
                MediaPreview(result: result, platform: platform, previewItems: previewItems, isSinglePreview: isSinglePreview,
                             onOpenPhoto: { index in
                                 viewer = PhotoViewerState(items: previewItems.filter(\.isPhoto), start: index)
                             },
                             onPlayVideo: { item in player = VideoPlayerState(item: item) })
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                info
            }

            if result.isMultiItem || galleryImages.count >= 2 {
                Section {
                    if result.isMultiItem { downloadAllRow }
                    if galleryImages.count >= 2 { pdfRow }
                }
            }

            Section {
                ForEach(Array(result.downloads.enumerated()), id: \.element.id) { index, item in
                    DownloadOptionRow(index: index, item: item, result: result, platform: platform,
                                      showThumbnail: result.isMultiPhoto && !result.isPlaylistOrAlbum && item.isPhoto,
                                      onPreview: {
                                          let photos = result.photoDownloads
                                          if let i = photos.firstIndex(of: item) {
                                              viewer = PhotoViewerState(items: photos, start: i)
                                          }
                                      })
                }
            } header: {
                Text(result.isPlaylistOrAlbum ? "Tracks" : "Download options")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(platform?.displayName ?? String(localized: "Result"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let link = URL(string: result.sourceUrl) {
                        Link(destination: link) { Label("Open original", systemImage: "safari") }
                        ShareLink(item: link) { Label("Share link", systemImage: "square.and.arrow.up") }
                    }
                    Button {
                        UIPasteboard.general.string = result.sourceUrl
                    } label: { Label("Copy link", systemImage: "doc.on.doc") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: pdfFileItem) { (item: IdentifiableURL) in ShareSheet(items: [item.url]) }
        .fullScreenCover(item: $viewer) { state in
            PhotoViewer(state: state, result: result, platform: platform)
        }
        .fullScreenCover(item: $player) { state in
            VideoPlayerScreen(item: state.item, sourceURL: result.sourceUrl)
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.displayTitle.isEmpty ? String(localized: "Untitled") : result.displayTitle)
                .font(.headline)
                .lineLimit(4)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                if let platform {
                    Label(platform.displayName, systemImage: platform.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(platform.tint)
                }
                if let author = result.author, !author.isEmpty {
                    Text(author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Download all

    private var downloadAllRow: some View {
        Button {
            downloadAll()
        } label: {
            HStack {
                Label(allTitle, systemImage: downloadingAll ? "stop.circle" : "arrow.down.circle.fill")
                Spacer()
                if downloadingAll {
                    ProgressView()
                } else {
                    Text(result.isMultiPhoto && !result.isPlaylistOrAlbum
                         ? String(localized: "\(downloadableItems.count) photos")
                         : String(localized: "\(downloadableItems.count) items"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .footnoteIfNeeded(allSummary)
    }

    private var allTitle: String {
        if downloadingAll { return String(localized: "Cancel") }
        return result.isMultiPhoto && !result.isPlaylistOrAlbum
            ? String(localized: "Download all photos") : String(localized: "Download all")
    }

    private var downloadableItems: [MediaDownload] { result.downloads.filter { !$0.isMirror } }

    private func downloadAll() {
        if downloadingAll {
            for item in downloadableItems {
                if let d = downloads.item(for: item.url) { downloads.cancel(d) }
            }
            return
        }
        downloadingAll = true
        allSummary = nil
        let requests = downloadableItems.map {
            DownloadRequest(item: $0, title: result.itemTitle(for: $0),
                            sourceURL: result.sourceUrl, platform: platform)
        }
        Task {
            let (ok, failed) = await downloads.startAll(requests)
            downloadingAll = false
            allSummary = failed == 0
                ? String(localized: "All \(ok) items downloaded")
                : String(localized: "Downloaded \(ok)/\(requests.count) items (\(failed) failed) — tap failed rows to retry")
        }
    }

    // MARK: PDF

    private var galleryImages: [MediaDownload] { isSinglePreview ? [] : result.galleryImages }

    private var pdfRow: some View {
        Button {
            exportPDF()
        } label: {
            HStack {
                Label("Export as PDF", systemImage: "doc.richtext")
                Spacer()
                if let pdfProgress {
                    ProgressView(value: pdfProgress).frame(width: 60)
                } else {
                    Text("\(galleryImages.count) pages").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
        }
        .disabled(pdfProgress != nil)
    }

    private var pdfFileItem: Binding<IdentifiableURL?> {
        Binding(get: { pdfFile.map(IdentifiableURL.init) }, set: { pdfFile = $0?.url })
    }

    private func exportPDF() {
        pdfProgress = 0
        Task {
            do {
                let file = try await PDFExporter.export(title: result.title, images: galleryImages, sourceURL: result.sourceUrl,
                                                        platform: platform) { pdfProgress = $0 }
                pdfProgress = nil
                Haptics.success()
                pdfFile = file
            } catch {
                pdfProgress = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Preview selection (ported from ui/result.js)

    private var isSinglePreview: Bool {
        [.youtube, .spotify, .applemusic, .bandcamp, .bilibili].contains(platform)
    }

    private var previewItems: [MediaDownload] {
        let items = result.downloads.filter { !$0.isMirror }
        let hasPhoto = items.contains(where: \.isPhoto)
        let hasVideo = items.contains(where: \.isVideo)
        switch platform {
        case .douyin?:
            return hasPhoto ? items.filter(\.isPhoto) : Array(items.prefix(1))
        case .bilibili?:
            return Array(items.prefix(1))
        case .rednote? where hasVideo:
            return Array(items.prefix(1))
        case .twitter?, .tiktok?:
            return hasPhoto ? items.filter(\.isPhoto) : Array(items.prefix(1))
        default:
            // Photo posts show every photo; otherwise one preview is enough (qualities are duplicates)
            return hasPhoto && !hasVideo ? items.filter(\.isPhoto) : Array(items.prefix(1))
        }
    }
}

struct IdentifiableURL: Identifiable {
    let url: URL
    var id: URL { url }
}

private extension View {
    @ViewBuilder
    func footnoteIfNeeded(_ text: String?) -> some View {
        if let text {
            VStack(alignment: .leading, spacing: 4) {
                self
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
        } else {
            self
        }
    }
}

// MARK: - Rows

struct DownloadOptionRow: View {
    let index: Int
    let item: MediaDownload
    let result: MediaResult
    let platform: Platform?
    let showThumbnail: Bool
    let onPreview: () -> Void

    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        let state = downloads.item(for: item.url)
        HStack(spacing: 12) {
            if showThumbnail {
                Button(action: onPreview) {
                    RemoteImage(url: item.thumbnail ?? item.url, sourceURL: result.sourceUrl, maxPixel: 120)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            Text("\((result.photoDownloads.firstIndex(of: item) ?? index) + 1)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 5)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(3)
                        }
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: item.kind == .audio ? "music.note" : item.kind == .photo ? "photo" : "film")
                    .foregroundStyle(.tint)
                    .frame(width: 28)
            }

            VStack(alignment: .leading, spacing: 2) {
                if item.isTrack {
                    Text(item.cleanType).font(.subheadline).lineLimit(2)
                } else {
                    Text(item.displayLabel.isEmpty ? String(localized: "Media") : item.displayLabel)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    if item.isMirror {
                        Text("Mirror").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let state { DownloadStatusLine(item: state) }
            }
            Spacer()
            if let state {
                DownloadBadge(item: state) { tap(existing: state) }
            } else {
                Button {
                    start()
                } label: {
                    Image(systemName: "arrow.down.circle.fill").font(.title2)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Download")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let state { tap(existing: state) } else { start() }
        }
    }

    private func start() {
        downloads.start(DownloadRequest(item: item, title: result.itemTitle(for: item),
                                        sourceURL: result.sourceUrl, platform: platform))
    }

    private func tap(existing: DownloadItem) {
        switch existing.status {
        case .failed, .cancelled: downloads.retry(existing)
        case .completed, .skipped: start()
        default: downloads.cancel(existing)
        }
    }
}

struct DownloadStatusLine: View {
    @ObservedObject var item: DownloadItem

    var body: some View {
        if item.status.isActive {
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: item.progress).tint(.accentColor)
                Text(item.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        } else if case .failed(let msg) = item.status {
            Text(msg).font(.caption2).foregroundStyle(.red).lineLimit(2)
        } else if !item.detail.isEmpty {
            Text(item.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

struct DownloadBadge: View {
    @ObservedObject var item: DownloadItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch item.status {
            case .queued:
                Image(systemName: "clock").font(.title3).foregroundStyle(.secondary)
            case .resolving, .downloading, .saving:
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 3)
                    Circle().trim(from: 0, to: item.progress)
                        .stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "stop.fill").font(.system(size: 8))
                }
                .frame(width: 24, height: 24)
            case .completed, .skipped:
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
            case .failed:
                Image(systemName: "arrow.clockwise.circle.fill").font(.title2).foregroundStyle(.red)
            case .cancelled:
                Image(systemName: "arrow.down.circle").font(.title2)
            }
        }
        .buttonStyle(.borderless)
    }
}
