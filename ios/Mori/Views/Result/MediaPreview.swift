import AVKit
import SwiftUI

struct PhotoViewerState: Identifiable {
    let id = UUID()
    let items: [MediaDownload]
    let start: Int
}

struct VideoPlayerState: Identifiable {
    let id = UUID()
    let item: MediaDownload
}

/// Header preview: photo carousel, video poster with play button, or a single thumbnail.
struct MediaPreview: View {
    let result: MediaResult
    let platform: Platform?
    let previewItems: [MediaDownload]
    let isSinglePreview: Bool
    let onOpenPhoto: (Int) -> Void
    let onPlayVideo: (MediaDownload) -> Void

    @State private var page = 0

    var body: some View {
        Group {
            if !isSinglePreview, previewItems.count > 1, previewItems.allSatisfy(\.isPhoto) {
                carousel
            } else if !isSinglePreview, let first = previewItems.first, first.isPhoto, !first.isVideo {
                photo(first, index: 0)
            } else {
                poster
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .background(Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var carousel: some View {
        TabView(selection: $page) {
            ForEach(Array(previewItems.enumerated()), id: \.element.id) { index, item in
                photo(item, index: index).tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .overlay(alignment: .topTrailing) {
            Text("\(page + 1) / \(previewItems.count)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
        }
    }

    private func photo(_ item: MediaDownload, index: Int) -> some View {
        RemoteImage(url: item.thumbnail ?? item.url, sourceURL: result.sourceUrl, maxPixel: 900, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { onOpenPhoto(index) }
    }

    private var poster: some View {
        let video = previewItems.first(where: \.isVideo)
        let playable = video.map { !ScraperEngine.shared.needsResolving($0.url) && !$0.url.contains("_resolve:") } ?? false
        return ZStack {
            RemoteImage(url: result.thumbnail ?? previewItems.first?.thumbnail, sourceURL: result.sourceUrl,
                        maxPixel: 900, contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            if playable, let video {
                Button { onPlayVideo(video) } label: {
                    Image(systemName: "play.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(.ultraThinMaterial.opacity(0.9), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play preview")
            }
        }
    }
}

/// Full-screen swipeable photo viewer with pinch-to-zoom and per-photo download.
struct PhotoViewer: View {
    let state: PhotoViewerState
    let result: MediaResult
    let platform: Platform?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var downloads: DownloadManager
    @State private var index = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $index) {
                ForEach(Array(state.items.enumerated()), id: \.element.id) { i, item in
                    ZoomableRemoteImage(url: item.url, sourceURL: result.sourceUrl).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("\(index + 1) / \(state.items.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar, .bottomBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        let item = state.items[index]
                        downloads.start(DownloadRequest(item: item, title: result.itemTitle(for: item),
                                                        sourceURL: result.sourceUrl, platform: platform))
                        Haptics.tap()
                    } label: {
                        Label("Download this photo", systemImage: "arrow.down.circle")
                    }
                }
            }
        }
        .onAppear { index = state.start }
    }
}

private struct ZoomableRemoteImage: View {
    let url: String
    let sourceURL: String
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        RemoteImage(url: url, sourceURL: sourceURL, maxPixel: nil, contentMode: .fit)
            .scaleEffect(scale)
            .gesture(MagnificationGesture()
                .onChanged { scale = max(1, min(5, lastScale * $0)) }
                .onEnded { _ in lastScale = scale })
            .onTapGesture(count: 2) {
                withAnimation(.spring()) {
                    scale = scale > 1 ? 1 : 2.5
                    lastScale = scale
                }
            }
    }
}

/// Streams a remote video with the headers its CDN requires.
struct VideoPlayerScreen: View {
    let item: MediaDownload
    let sourceURL: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player).ignoresSafeArea()
            } else {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding()
        }
        .onAppear {
            let cleaned = DownloadHeaders.cleanDownloadURL(item.url)
            guard let url = URL(string: cleaned) else { return }
            let headers = DownloadHeaders.preview(for: cleaned, sourceURL: sourceURL, extra: item.headers)
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            let p = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            player = p
            p.play()
        }
        .onDisappear { player?.pause() }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
