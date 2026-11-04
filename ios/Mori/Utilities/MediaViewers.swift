import AVKit
import JXPhotoBrowser
import Kingfisher
import QuickLookThumbnailing
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

        let browser = MoriPhotoBrowserViewController()
        browser.delegate = presenter
        browser.initialIndex = min(max(0, index), photos.count - 1)
        // Zoom out of / back into the tapped thumbnail (fades to black underneath).
        browser.transitionType = .zoom
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

    /// View the zoom transition starts from and returns to: the SwiftUI
    /// thumbnail registered by the grid cell for this photo.
    nonisolated func photoBrowser(_ browser: JXPhotoBrowserViewController, thumbnailViewAt index: Int) -> UIView? {
        MainActor.assumeIsolated {
            guard photos.indices.contains(index) else { return nil }
            return ThumbnailAnchorRegistry.shared.view(for: photos[index].url)
        }
    }
}

/// Zoom transition with a slightly longer, softer curve than the library default.
private final class MoriZoomPresentAnimator: JXZoomPresentAnimator {
    override func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval { 0.32 }
}

private final class MoriZoomDismissAnimator: JXZoomDismissAnimator {
    override func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval { 0.32 }
}

private final class MoriPhotoBrowserViewController: JXPhotoBrowserViewController {
    override func animationController(forPresented presented: UIViewController, presenting: UIViewController,
                                      source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard transitionType == .zoom else {
            return super.animationController(forPresented: presented, presenting: presenting, source: source)
        }
        return MoriZoomPresentAnimator()
    }

    override func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard transitionType == .zoom else {
            return super.animationController(forDismissed: dismissed)
        }
        return MoriZoomDismissAnimator()
    }
}

// MARK: - Thumbnail anchors

/// Keeps the live thumbnail views so JXPhotoBrowser can compute the zoom
/// transition's start/end frames from the actual grid cell.
@MainActor
final class ThumbnailAnchorRegistry {
    static let shared = ThumbnailAnchorRegistry()

    private struct WeakView { weak var view: UIView? }
    private var views: [String: WeakView] = [:]

    func register(_ view: UIView, for key: String) { views[key] = WeakView(view: view) }

    func unregister(_ view: UIView, for key: String) {
        if views[key]?.view === view { views.removeValue(forKey: key) }
    }

    func view(for key: String) -> UIView? { views[key]?.view }
}

/// Invisible-in-place copy of a cell's thumbnail. It sits behind the SwiftUI
/// image (which always stays visible, so nothing flashes while the zoom
/// transition restores), and gives the browser a real UIView with a ready image.
struct ThumbnailAnchor: UIViewRepresentable {
    let key: String
    var url: String?
    var localFile: URL?
    var sourceURL: String?
    var headers: [String: String]?
    var maxPixel: CGFloat = 400
    var cornerRadius: CGFloat = 12

    func makeUIView(context: Context) -> ThumbnailAnchorView {
        let view = ThumbnailAnchorView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerCurve = .continuous
        view.isUserInteractionEnabled = false
        view.registryKey = key
        ThumbnailAnchorRegistry.shared.register(view, for: key)
        return view
    }

    func updateUIView(_ view: ThumbnailAnchorView, context: Context) {
        view.registryKey = key
        ThumbnailAnchorRegistry.shared.register(view, for: key)
        view.layer.cornerRadius = cornerRadius
        view.load(url: url, localFile: localFile, sourceURL: sourceURL, headers: headers, maxPixel: maxPixel)
    }

    static func dismantleUIView(_ view: ThumbnailAnchorView, coordinator: ()) {
        ThumbnailAnchorRegistry.shared.unregister(view, for: view.registryKey)
    }
}

final class ThumbnailAnchorView: UIImageView {
    var registryKey = ""
    private var loadedKey = ""

    func load(url: String?, localFile: URL?, sourceURL: String?, headers: [String: String]?, maxPixel: CGFloat) {
        let key: String
        if let localFile {
            key = "file:\(localFile.absoluteString)"
        } else if let url, !url.isEmpty {
            key = "net:\(url)#\(Int(maxPixel))"
        } else {
            return
        }
        guard key != loadedKey else { return }
        loadedKey = key

        if let localFile {
            Task { @MainActor [weak self] in
                let request = QLThumbnailGenerator.Request(fileAt: localFile, size: CGSize(width: 240, height: 240),
                                                           scale: 2, representationTypes: .thumbnail)
                if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                    self?.image = rep.uiImage
                }
            }
            return
        }

        guard let url, let source = ImageLoader.source(for: url) else { return }
        kf.setImage(
            with: source,
            options: [
                .requestModifier(ImageLoader.modifier(for: url, sourceURL: sourceURL, headers: headers)),
                .processor(DownsamplingImageProcessor(size: CGSize(width: maxPixel, height: maxPixel))),
                .scaleFactor(UIScreen.main.scale),
                .cacheOriginalImage,
            ]
        ) { [weak self] result in
            if case .failure = result, let proxy = ImageLoader.proxyURL(for: url) {
                self?.kf.setImage(with: proxy)
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
