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
                RemoteImage(url: item.thumbnail ?? item.url, sourceURL: result.sourceUrl, headers: item.headers, maxPixel: 400)
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
                        DownloadBadge(item: state, compact: true) {
                            switch state.status {
                            case .failed, .cancelled: downloads.retry(state)
                            case .completed, .skipped: onDownload()
                            default: downloads.cancel(state)
                            }
                        }
                    } else {
                        Button(action: onDownload) {
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
                .accessibilityIdentifier("photo-download")
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .padding(6)
            }
    }
}
