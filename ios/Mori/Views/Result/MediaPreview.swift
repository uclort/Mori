import SwiftUI

/// Header preview for video / audio results: poster with a play button (system player).
struct MediaPreview: View {
    let result: MediaResult
    let video: MediaDownload?

    var body: some View {
        let playable = video.map { !ScraperEngine.shared.needsResolving($0.url) && !$0.url.contains("_resolve:") } ?? false
        ZStack {
            RemoteImage(url: result.thumbnail ?? video?.thumbnail, sourceURL: result.sourceUrl, maxPixel: 900, contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            if playable, let video {
                Button {
                    SystemVideoPlayer.play(item: video, sourceURL: result.sourceUrl)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play preview")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .background(Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// One photo in the result grid: tap the image to preview, tap the corner button to download.
struct PhotoGridCell: View {
    let index: Int
    let item: MediaDownload
    let result: MediaResult
    let onPreview: () -> Void
    let onDownload: () -> Void

    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        Color.clear
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay(
                // UIKit-backed so the photo browser zooms out of / back into this exact view.
                ZoomThumbnail(key: item.url, url: item.thumbnail ?? item.url,
                              sourceURL: result.sourceUrl, headers: item.headers,
                              maxPixel: 400, cornerRadius: 12)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture(perform: onPreview)
            .accessibilityElement()
            .accessibilityLabel(Text("Photo \(index + 1)"))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("photo-\(index)")
            .overlay(alignment: .topLeading) {
                Text("\(index + 1)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(6)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                Group {
                    if let state = downloads.item(for: item.url) {
                        PhotoDownloadControl(item: state,
                                             onDownload: onDownload,
                                             onRetry: { downloads.retry(state) },
                                             onCancel: { downloads.cancel(state) })
                    } else {
                        PhotoDownloadButton(action: onDownload)
                    }
                }
                .accessibilityIdentifier("photo-download")
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .padding(6)
            }
    }
}

/// 30pt corner download button for a grid thumbnail.
struct PhotoDownloadButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.accentColor, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Download")
    }
}

/// Download state for one thumbnail. A finished download shows a check for a
/// moment (not tappable), then animates back into a normal download button.
private struct PhotoDownloadControl: View {
    @ObservedObject var item: DownloadItem
    let onDownload: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void

    @State private var showingSuccess = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            switch item.status {
            case .completed, .skipped:
                if showingSuccess {
                    badge("checkmark", .green)
                        .highPriorityGesture(TapGesture().onEnded {})
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else {
                    PhotoDownloadButton(action: onDownload)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            case .failed:
                Button(action: onRetry) { badge("arrow.clockwise", .red) }
                    .buttonStyle(.plain)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            case .cancelled:
                PhotoDownloadButton(action: onDownload)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            case .queued, .resolving, .downloading, .saving:
                Button(action: onCancel) {
                    ZStack {
                        Circle().fill(.black.opacity(0.55))
                        Circle().stroke(.white.opacity(0.3), lineWidth: 3)
                        Circle().trim(from: 0, to: item.progress)
                            .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "stop.fill").font(.system(size: 7)).foregroundStyle(.white)
                    }
                    .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel")
            }
        }
        .onChange(of: item.status) { status in
            switch status {
            case .completed, .skipped:
                celebrate()
            default:
                resetTask?.cancel()
                withAnimation(.easeInOut(duration: 0.2)) { showingSuccess = false }
            }
        }
        .onDisappear { resetTask?.cancel() }
    }

    private func badge(_ symbol: String, _ color: Color) -> some View {
        ZStack {
            Circle().fill(color)
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: 30, height: 30)
    }

    private func celebrate() {
        resetTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.62)) { showingSuccess = true }
        Haptics.success()
        resetTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.28)) { showingSuccess = false }
        }
    }
}
