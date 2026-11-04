import AVKit
import JXPhotoBrowser
import Kingfisher
import SwiftUI
import UIKit

/// One page in the photo browser.
struct BrowserPhoto {
    var url: String
    var sourceURL: String?
    var headers: [String: String]?

    static func local(_ file: URL) -> BrowserPhoto { BrowserPhoto(url: file.absoluteString) }
}

/// Presents JXPhotoBrowser (zoom, swipe, pull-to-dismiss) with Kingfisher-backed loading.
@MainActor
final class PhotoBrowserPresenter: NSObject, JXPhotoBrowserDelegate {
    /// The browser only keeps a weak delegate — retain the active presenter here.
    private static var active: PhotoBrowserPresenter?

    private let photos: [BrowserPhoto]
    private let onDownload: ((Int) -> Void)?

    private init(photos: [BrowserPhoto], onDownload: ((Int) -> Void)?) {
        self.photos = photos
        self.onDownload = onDownload
    }

    static func present(_ photos: [BrowserPhoto], startAt index: Int, onDownload: ((Int) -> Void)? = nil) {
        guard !photos.isEmpty, let top = UIApplication.topViewController() else { return }
        let presenter = PhotoBrowserPresenter(photos: photos, onDownload: onDownload)
        active = presenter

        let browser = JXPhotoBrowserViewController()
        browser.delegate = presenter
        browser.initialIndex = min(max(0, index), photos.count - 1)
        browser.transitionType = .fade
        browser.isLoopingEnabled = false
        browser.itemSpacing = 20
        if photos.count > 1 { browser.addOverlay(JXPageIndicatorOverlay()) }
        if let onDownload { browser.addOverlay(DownloadOverlay(action: onDownload)) }
        browser.present(from: top)
    }

    nonisolated func numberOfItems(in browser: JXPhotoBrowserViewController) -> Int {
        MainActor.assumeIsolated { photos.count }
    }

    nonisolated func photoBrowser(_ browser: JXPhotoBrowserViewController, cellForItemAt index: Int,
                                  at indexPath: IndexPath) -> JXPhotoBrowserAnyCell {
        MainActor.assumeIsolated {
            browser.dequeueReusableCell(withReuseIdentifier: JXZoomImageCell.reuseIdentifier, for: indexPath)
        }
    }

    nonisolated func photoBrowser(_ browser: JXPhotoBrowserViewController, willDisplay cell: JXPhotoBrowserAnyCell, at index: Int) {
        MainActor.assumeIsolated {
            guard let cell = cell as? JXZoomImageCell, photos.indices.contains(index) else { return }
            let photo = photos[index]
            guard let source = ImageLoader.source(for: photo.url) else { return }
            cell.imageView.kf.indicatorType = .activity
            cell.imageView.kf.setImage(
                with: source,
                options: [.requestModifier(ImageLoader.modifier(for: photo.url, sourceURL: photo.sourceURL, headers: photo.headers))]
            ) { [weak cell] result in
                if case .failure = result, let proxy = ImageLoader.proxyURL(for: photo.url) {
                    cell?.imageView.kf.setImage(with: proxy) { [weak cell] _ in cell?.setNeedsLayout() }
                }
                cell?.setNeedsLayout()
            }
        }
    }
}

/// Bottom-trailing "download this photo" button shown inside the photo browser.
private final class DownloadOverlay: UIView, JXPhotoBrowserOverlay {
    private let action: (Int) -> Void
    private var pageIndex = 0
    private let button = UIButton(type: .system)

    init(action: @escaping (Int) -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setup(with browser: JXPhotoBrowserViewController) {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "arrow.down.to.line")
        config.title = String(localized: "Download")
        config.imagePadding = 6
        config.cornerStyle = .capsule
        config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.18)
        config.baseForegroundColor = .white
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
            return a
        }
        button.configuration = config
        button.addAction(UIAction { [weak self] _ in self?.tapped() }, for: .touchUpInside)

        translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        guard let host = superview else { return }
        NSLayoutConstraint.activate([
            trailingAnchor.constraint(equalTo: host.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    func reloadData(numberOfItems: Int, pageIndex: Int) { self.pageIndex = pageIndex }

    func didChangedPageIndex(_ index: Int) {
        pageIndex = index
        reset()
    }

    private func tapped() {
        action(pageIndex)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        button.configuration?.image = UIImage(systemName: "checkmark")
        button.configuration?.title = String(localized: "Added to downloads")
    }

    private func reset() {
        button.configuration?.image = UIImage(systemName: "arrow.down.to.line")
        button.configuration?.title = String(localized: "Download")
    }
}

/// System video player (AVPlayerViewController) for remote streams or local files.
enum SystemVideoPlayer {
    @MainActor
    static func play(_ url: URL, headers: [String: String] = [:]) {
        guard let top = UIApplication.topViewController() else { return }
        let asset = headers.isEmpty ? AVURLAsset(url: url) : AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        let vc = AVPlayerViewController()
        vc.player = player
        vc.modalPresentationStyle = .fullScreen
        top.present(vc, animated: true) { player.play() }
    }

    @MainActor
    static func play(item: MediaDownload, sourceURL: String) {
        let cleaned = DownloadHeaders.cleanDownloadURL(item.url)
        guard let url = URL(string: cleaned) else { return }
        play(url, headers: DownloadHeaders.preview(for: cleaned, sourceURL: sourceURL, extra: item.headers))
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

extension UIApplication {
    static func topViewController() -> UIViewController? {
        let scene = shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController ?? scene?.windows.first?.rootViewController else {
            return nil
        }
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
