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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !isPhotoPost {
                    MediaPreview(result: result, video: result.downloads.first(where: { !$0.isMirror && $0.isVideo }))
                }
                info
                if result.isMultiItem || galleryImages.count >= 2 { actionsCard }
                if !photos.isEmpty { photoGrid }
                if !otherItems.isEmpty { optionsList }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
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
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Sections

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var actionsCard: some View {
        VStack(spacing: 0) {
            if result.isMultiItem {
                actionRow(title: allTitle,
                          systemImage: downloadingAll ? "stop.circle" : "arrow.down.circle.fill",
                          trailing: downloadingAll ? nil : allCountText,
                          busy: downloadingAll,
                          action: downloadAll)
                if let allSummary {
                    Text(allSummary)
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.bottom, 10)
                }
            }
            if result.isMultiItem && galleryImages.count >= 2 { Divider().padding(.leading, 50) }
            if galleryImages.count >= 2 {
                actionRow(title: String(localized: "Export as PDF"), systemImage: "doc.richtext",
                          trailing: pdfProgress == nil ? String(localized: "\(galleryImages.count) pages") : nil,
                          busy: pdfProgress != nil, action: exportPDF)
                    .disabled(pdfProgress != nil)
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func actionRow(title: String, systemImage: String, trailing: String?, busy: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage).font(.title3).frame(width: 24)
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                if busy { ProgressView() }
                if let trailing {
                    Text(trailing).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }

    private var photoGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "\(photos.count) photos"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, item in
                    PhotoGridCell(index: index, item: item, result: result,
                                  onPreview: { preview(at: index) },
                                  onDownload: { start(item) })
                }
            }
        }
    }

    private var optionsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(result.isPlaylistOrAlbum ? String(localized: "Tracks")
                          : (photos.isEmpty ? String(localized: "Download options") : String(localized: "Other formats")))
            VStack(spacing: 0) {
                ForEach(Array(otherItems.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading, 54) }
                    DownloadOptionRow(item: item) { start(item) }
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    // MARK: Data

    /// Posts made only of photos get the grid layout without a big header preview.
    private var isPhotoPost: Bool {
        !photos.isEmpty && !result.downloads.contains { !$0.isMirror && $0.isVideo }
    }

    private var isSinglePreview: Bool {
        [.youtube, .spotify, .applemusic, .bandcamp, .bilibili].contains(platform)
    }

    private var photos: [MediaDownload] {
        isSinglePreview ? [] : result.downloads.filter { $0.isPhoto && !$0.isVideo }
    }

    private var otherItems: [MediaDownload] {
        let photoIDs = Set(photos.map(\.id))
        return result.downloads.filter { !photoIDs.contains($0.id) }
    }

    private var galleryImages: [MediaDownload] { isSinglePreview ? [] : result.galleryImages }

    private var downloadableItems: [MediaDownload] { result.downloads.filter { !$0.isMirror } }

    private var allTitle: String {
        if downloadingAll { return String(localized: "Cancel") }
        return result.isMultiPhoto && !result.isPlaylistOrAlbum
            ? String(localized: "Download all photos") : String(localized: "Download all")
    }

    private var allCountText: String {
        result.isMultiPhoto && !result.isPlaylistOrAlbum
            ? String(localized: "\(downloadableItems.count) photos")
            : String(localized: "\(downloadableItems.count) items")
    }

    // MARK: Actions

    private func start(_ item: MediaDownload) {
        downloads.start(DownloadRequest(item: item, title: result.itemTitle(for: item),
                                        sourceURL: result.sourceUrl, platform: platform))
    }

    private func preview(at index: Int) {
        let pages = photos.map { BrowserPhoto(url: $0.url, sourceURL: result.sourceUrl, headers: $0.headers) }
        let items = photos
        PhotoBrowserPresenter.present(pages, startAt: index) { i in
            if items.indices.contains(i) { start(items[i]) }
        }
    }

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
            DownloadRequest(item: $0, title: result.itemTitle(for: $0), sourceURL: result.sourceUrl, platform: platform)
        }
        Task {
            let (ok, failed) = await downloads.startAll(requests)
            downloadingAll = false
            allSummary = failed == 0
                ? String(localized: "All \(ok) items downloaded")
                : String(localized: "Downloaded \(ok)/\(requests.count) items (\(failed) failed) — tap failed rows to retry")
        }
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
}

struct IdentifiableURL: Identifiable {
    let url: URL
    var id: URL { url }
}

// MARK: - Rows

/// Video quality / audio / track row. Only the trailing button starts a download.
struct DownloadOptionRow: View {
    let item: MediaDownload
    let onDownload: () -> Void

    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        let state = downloads.item(for: item.url)
        HStack(spacing: 12) {
            Image(systemName: item.kind == .audio ? "music.note" : item.kind == .photo ? "photo" : "film")
                .foregroundStyle(.tint)
                .frame(width: 28)
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
                DownloadBadge(item: state) {
                    switch state.status {
                    case .failed, .cancelled: downloads.retry(state)
                    case .completed, .skipped: onDownload()
                    default: downloads.cancel(state)
                    }
                }
            } else {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle.fill").font(.title2)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Download")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if compact { compactBody } else { regularBody }
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var regularBody: some View {
        switch item.status {
        case .queued:
            Image(systemName: "clock").font(.title3).foregroundStyle(.secondary)
        case .resolving, .downloading, .saving:
            ring(color: AnyShapeStyle(.tint)).frame(width: 24, height: 24)
        case .completed, .skipped:
            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
        case .failed:
            Image(systemName: "arrow.clockwise.circle.fill").font(.title2).foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "arrow.down.circle").font(.title2)
        }
    }

    /// 30pt circle for overlaying on thumbnails.
    private var compactBody: some View {
        let symbol: String?
        let color: Color
        switch item.status {
        case .queued: (symbol, color) = ("clock", .gray)
        case .resolving, .downloading, .saving: (symbol, color) = (nil, .black.opacity(0.55))
        case .completed, .skipped: (symbol, color) = ("checkmark", .green)
        case .failed: (symbol, color) = ("arrow.clockwise", .red)
        case .cancelled: (symbol, color) = ("arrow.down", .accentColor)
        }
        return ZStack {
            Circle().fill(color)
            if let symbol {
                Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            } else {
                ring(color: AnyShapeStyle(.white)).padding(5).foregroundStyle(.white)
            }
        }
        .frame(width: 30, height: 30)
    }

    private func ring(color: AnyShapeStyle) -> some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 3)
            Circle().trim(from: 0, to: item.progress)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "stop.fill").font(.system(size: 7))
        }
    }
}
