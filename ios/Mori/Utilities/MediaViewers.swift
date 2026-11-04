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
/// Opening zooms out of the tapped thumbnail, closing flies back into it.
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
        // .zoom also makes the library hide the matching grid thumbnail while browsing.
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
            let cell = browser.dequeueReusableCell(withReuseIdentifier: JXZoomImageCell.reuseIdentifier, for: indexPath)
            // Seed synchronously with the best image we already have (full image from
            // memory cache, else the on-screen thumbnail). The zoom transition reads
            // this image's aspect for its end frame, so it lands exactly.
            if let zoom = cell as? JXZoomImageCell, photos.indices.contains(index) {
                zoom.imageView.image = cachedImage(at: index)
            }
            return cell
        }
    }

    nonisolated func photoBrowser(_ browser: JXPhotoBrowserViewController, willDisplay cell: JXPhotoBrowserAnyCell, at index: Int) {
        MainActor.assumeIsolated {
            guard let cell = cell as? JXZoomImageCell, photos.indices.contains(index) else { return }
            let photo = photos[index]
            guard let source = ImageLoader.source(for: photo.url) else { return }
            if cell.imageView.image == nil { cell.imageView.image = cachedImage(at: index) }
            cell.imageView.kf.indicatorType = cell.imageView.image == nil ? .activity : .none
            cell.imageView.kf.setImage(
                with: source,
                options: [
                    .requestModifier(ImageLoader.modifier(for: photo.url, sourceURL: photo.sourceURL, headers: photo.headers)),
                    // Never blank the seeded image while the full one loads.
                    .keepCurrentImageWhileLoading,
                    .backgroundDecode,
                ]
            ) { [weak cell] result in
                if case .failure(let error) = result, !error.isTaskCancelled,
                   let proxy = ImageLoader.proxyURL(for: photo.url) {
                    cell?.imageView.kf.setImage(with: proxy, options: [.keepCurrentImageWhileLoading]) { [weak cell] _ in
                        cell?.setNeedsLayout()
                    }
                }
                cell?.setNeedsLayout()
            }
        }
    }

    nonisolated func photoBrowser(_ browser: JXPhotoBrowserViewController, thumbnailViewAt index: Int) -> UIView? {
        MainActor.assumeIsolated {
            guard photos.indices.contains(index) else { return nil }
            return ZoomThumbnailRegistry.shared.view(for: photos[index].url)
        }
    }

    private func cachedImage(at index: Int) -> UIImage? {
        let photo = photos[index]
        if let key = ImageLoader.source(for: photo.url)?.cacheKey,
           let full = ImageCache.default.retrieveImageInMemoryCache(forKey: key) {
            return full
        }
        return ZoomThumbnailRegistry.shared.view(for: photo.url)?.image
    }
}

// MARK: - Zoom transition

private final class MoriPhotoBrowserViewController: JXPhotoBrowserViewController {
    override func animationController(forPresented presented: UIViewController, presenting: UIViewController,
                                      source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        transitionType == .zoom ? PhotoZoomPresentAnimator()
            : super.animationController(forPresented: presented, presenting: presenting, source: source)
    }

    override func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        transitionType == .zoom ? PhotoZoomDismissAnimator()
            : super.animationController(forDismissed: dismissed)
    }
}

private extension JXPhotoBrowserViewController {
    /// The on-screen grid thumbnail for the current page, if it is actually visible.
    func visibleThumbnail(in container: UIView) -> UIImageView? {
        guard let thumb = delegate?.photoBrowser(self, thumbnailViewAt: pageIndex) as? UIImageView,
              thumb.window != nil, thumb.image != nil, thumb.bounds.size != .zero else { return nil }
        let frame = thumb.convert(thumb.bounds, to: container)
        return container.bounds.intersects(frame) ? thumb : nil
    }

    var overlayViews: [UIView] { view.subviews.filter { $0 is JXPhotoBrowserOverlay } }
}

/// Grows a copy of the tapped thumbnail into the photo's real on-screen frame
/// while the black backdrop fades in. Corners un-round on the way.
private final class PhotoZoomPresentAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval { 0.36 }

    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        guard let browser = ctx.viewController(forKey: .to) as? JXPhotoBrowserViewController else {
            ctx.completeTransition(false)
            return
        }
        let container = ctx.containerView
        let toView = ctx.view(forKey: .to) ?? browser.view!
        let duration = transitionDuration(using: ctx)
        container.addSubview(toView)
        toView.frame = ctx.finalFrame(for: browser)
        toView.layoutIfNeeded()
        browser.scrollToInitialIndexIfNeeded()
        browser.collectionView.layoutIfNeeded()
        (browser.visibleCell() as? UIView)?.layoutIfNeeded()

        let overlays = browser.overlayViews
        guard let thumb = browser.visibleThumbnail(in: container),
              let target = browser.visibleCell()?.transitionImageView,
              let image = target.image ?? thumb.image else {
            toView.alpha = 0
            UIView.animate(withDuration: 0.25, animations: { toView.alpha = 1 }) { _ in
                ctx.completeTransition(!ctx.transitionWasCancelled)
            }
            return
        }

        let startFrame = thumb.convert(thumb.bounds, to: container)
        let endFrame: CGRect
        if target.bounds.size != .zero {
            endFrame = target.convert(target.bounds, to: container)
        } else {
            endFrame = AVMakeRect(aspectRatio: image.size, insideRect: container.bounds)
        }

        let zoom = UIImageView(image: image)
        zoom.contentMode = .scaleAspectFill
        zoom.clipsToBounds = true
        zoom.layer.cornerCurve = .continuous
        zoom.layer.cornerRadius = thumb.layer.cornerRadius
        zoom.frame = startFrame
        container.addSubview(zoom)

        // The real thumbnail vanishes so only one image is moving.
        thumb.alpha = 0
        target.isHidden = true
        let backdrop = toView.backgroundColor ?? .black
        toView.backgroundColor = backdrop.withAlphaComponent(0)
        overlays.forEach { $0.alpha = 0 }

        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0,
                       options: [.allowUserInteraction]) {
            zoom.frame = endFrame
            zoom.layer.cornerRadius = 0
        } completion: { _ in
            target.isHidden = false
            zoom.removeFromSuperview()
            // Covered by the opaque browser now; the library hides it via isHidden in viewDidAppear.
            thumb.alpha = 1
            ctx.completeTransition(!ctx.transitionWasCancelled)
        }
        UIView.animate(withDuration: duration * 0.8, delay: 0, options: [.curveEaseOut]) {
            toView.backgroundColor = backdrop
        }
        UIView.animate(withDuration: duration * 0.6, delay: duration * 0.4, options: [.curveEaseOut]) {
            overlays.forEach { $0.alpha = 1 }
        }
    }
}

/// Flies the current photo back into its grid thumbnail. Over the last 40% the
/// flying copy cross-fades into the real thumbnail, so nothing pops at the end.
private final class PhotoZoomDismissAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval { 0.32 }

    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        guard let browser = ctx.viewController(forKey: .from) as? JXPhotoBrowserViewController,
              let fromView = ctx.view(forKey: .from) ?? browser.view else {
            ctx.completeTransition(false)
            return
        }
        let container = ctx.containerView
        let duration = transitionDuration(using: ctx)
        if let toView = ctx.view(forKey: .to) {
            container.insertSubview(toView, belowSubview: fromView)
            toView.layoutIfNeeded()
        }

        guard let source = browser.visibleCell()?.transitionImageView, source.image != nil,
              source.bounds.size != .zero,
              let thumb = browser.visibleThumbnail(in: container) else {
            UIView.animate(withDuration: 0.25, animations: { fromView.alpha = 0 }) { _ in
                let finished = !ctx.transitionWasCancelled
                if finished { fromView.removeFromSuperview() } else { fromView.alpha = 1 }
                ctx.completeTransition(finished)
            }
            return
        }

        // Includes the pull-down drag transform, so the flight starts where the finger left it.
        let startFrame = source.convert(source.bounds, to: container)
        let endFrame = thumb.convert(thumb.bounds, to: container)
        let zoom = UIImageView(image: source.image)
        zoom.contentMode = .scaleAspectFill
        zoom.clipsToBounds = true
        zoom.layer.cornerCurve = .continuous
        zoom.frame = startFrame
        container.addSubview(zoom)

        source.isHidden = true
        thumb.alpha = 0
        thumb.isHidden = false

        UIView.animateKeyframes(
            withDuration: duration, delay: 0,
            options: UIView.KeyframeAnimationOptions(rawValue: UIView.AnimationOptions.curveEaseOut.rawValue)
        ) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1) {
                zoom.frame = endFrame
                zoom.layer.cornerRadius = thumb.layer.cornerRadius
                fromView.alpha = 0
            }
            UIView.addKeyframe(withRelativeStartTime: 0.6, relativeDuration: 0.4) {
                zoom.alpha = 0
                thumb.alpha = 1
            }
        } completion: { _ in
            zoom.removeFromSuperview()
            source.isHidden = false
            thumb.alpha = 1
            let finished = !ctx.transitionWasCancelled
            if finished { fromView.removeFromSuperview() } else { fromView.alpha = 1 }
            ctx.completeTransition(finished)
        }
    }
}

// MARK: - Zoomable thumbnails

/// Live grid thumbnails keyed by photo URL, so the browser can find the exact
/// view the user tapped (and hide it / fly back into it).
@MainActor
final class ZoomThumbnailRegistry {
    static let shared = ZoomThumbnailRegistry()

    private struct WeakView { weak var view: ZoomThumbnailImageView? }
    private var views: [String: WeakView] = [:]

    func register(_ view: ZoomThumbnailImageView, for key: String) { views[key] = WeakView(view: view) }

    func unregister(_ view: ZoomThumbnailImageView, for key: String) {
        if views[key]?.view === view { views.removeValue(forKey: key) }
    }

    /// Only returns thumbnails that actually show a photo.
    func view(for key: String) -> ZoomThumbnailImageView? {
        guard let view = views[key]?.view, view.hasPhoto else { return nil }
        return view
    }
}

final class ZoomThumbnailImageView: UIImageView {
    var hasPhoto = false
}

/// A grid thumbnail drawn by a real UIImageView (Kingfisher). This is the very
/// view the user sees, so the photo browser zooms out of it, hides it while
/// browsing and flies back into it — exactly like the Photos app.
struct ZoomThumbnail: UIViewRepresentable {
    /// Must equal `BrowserPhoto.url` of the page this thumbnail represents.
    let key: String
    /// Image to display (may be a dedicated thumbnail URL).
    let url: String
    var sourceURL: String?
    var headers: [String: String]?
    var maxPixel: CGFloat = 400
    var cornerRadius: CGFloat = 12

    func makeUIView(context: Context) -> ZoomThumbnailContainer { ZoomThumbnailContainer() }

    func updateUIView(_ view: ZoomThumbnailContainer, context: Context) {
        view.configure(key: key, url: url, sourceURL: sourceURL, headers: headers,
                       maxPixel: maxPixel, cornerRadius: cornerRadius)
    }

    static func dismantleUIView(_ view: ZoomThumbnailContainer, coordinator: ()) {
        ZoomThumbnailRegistry.shared.unregister(view.imageView, for: view.key)
        view.imageView.kf.cancelDownloadTask()
    }
}

final class ZoomThumbnailContainer: UIView {
    let imageView = ZoomThumbnailImageView()
    private let placeholderIcon = UIImageView(image: UIImage(systemName: "photo"))
    private(set) var key = ""
    private var loadedURL = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerCurve = .continuous
        backgroundColor = .tertiarySystemFill
        placeholderIcon.tintColor = .secondaryLabel
        placeholderIcon.contentMode = .center
        placeholderIcon.isHidden = true
        placeholderIcon.frame = bounds
        placeholderIcon.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(placeholderIcon)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerCurve = .continuous
        imageView.isUserInteractionEnabled = false
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(key: String, url: String, sourceURL: String?, headers: [String: String]?,
                   maxPixel: CGFloat, cornerRadius: CGFloat) {
        layer.cornerRadius = cornerRadius
        imageView.layer.cornerRadius = cornerRadius
        if key != self.key {
            ZoomThumbnailRegistry.shared.unregister(imageView, for: self.key)
            self.key = key
        }
        ZoomThumbnailRegistry.shared.register(imageView, for: key)
        guard url != loadedURL else { return }
        loadedURL = url
        imageView.hasPhoto = false
        imageView.image = nil
        placeholderIcon.isHidden = true
        backgroundColor = .tertiarySystemFill
        guard let source = ImageLoader.source(for: url) else { return failed() }

        imageView.kf.indicatorType = .activity
        imageView.kf.setImage(
            with: source,
            options: [
                .requestModifier(ImageLoader.modifier(for: url, sourceURL: sourceURL, headers: headers)),
                .processor(DownsamplingImageProcessor(size: CGSize(width: maxPixel, height: maxPixel))),
                .scaleFactor(UIScreen.main.scale),
                .cacheOriginalImage,
                .backgroundDecode,
                .transition(.fade(0.2)),
            ]
        ) { [weak self] result in
            guard let self, self.loadedURL == url else { return }
            switch result {
            case .success:
                self.loaded()
            case .failure(let error):
                guard !error.isTaskCancelled else { return }
                guard let proxy = ImageLoader.proxyURL(for: url) else { return self.failed() }
                self.imageView.kf.setImage(with: proxy, options: [
                    .processor(DownsamplingImageProcessor(size: CGSize(width: maxPixel, height: maxPixel))),
                    .scaleFactor(UIScreen.main.scale),
                    .transition(.fade(0.2)),
                ]) { [weak self] result in
                    guard let self, self.loadedURL == url else { return }
                    if case .success = result { self.loaded() } else { self.failed() }
                }
            }
        }
    }

    private func loaded() {
        imageView.hasPhoto = true
        // While the browser shows this photo the image view is hidden: leave an
        // empty slot (like Photos), not a grey box.
        backgroundColor = .clear
        placeholderIcon.isHidden = true
    }

    private func failed() {
        imageView.hasPhoto = false
        placeholderIcon.isHidden = false
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

