import Foundation
import SwiftUI
import WebKit

/// Hosts the shared JavaScript scraper core in an invisible WKWebView.
/// The web view only provides a JS runtime (DOMParser, URL, timers…); all I/O is native.
@MainActor
final class ScraperEngine: NSObject, ObservableObject {
    static let shared = ScraperEngine()

    enum State: Equatable {
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var activeVersion: Int = 0
    @Published private(set) var isOTA = false

    let webView: WKWebView
    private var readyWaiters: [CheckedContinuation<Void, Error>] = []
    private var progressHandlers: [String: (Double, String) -> Void] = [:]

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let controller = WKUserContentController()
        config.userContentController = controller
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        super.init()

        controller.addScriptMessageHandler(EngineHTTPBridge(), contentWorld: .page, name: "moriHttp")
        controller.add(WeakMessageHandler(self), name: "moriProgress")
        controller.add(WeakMessageHandler(self), name: "moriLog")
        if let hostURL = Bundle.main.url(forResource: "EngineHost", withExtension: "js"),
           let hostJS = try? String(contentsOf: hostURL, encoding: .utf8) {
            controller.addUserScript(WKUserScript(source: hostJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        webView.navigationDelegate = self
        reload()
    }

    // MARK: Lifecycle

    func reload() {
        state = .loading
        webView.loadHTMLString("<!doctype html><html><head><meta charset=\"utf-8\"></head><body></body></html>",
                               baseURL: URL(string: "https://engine.mori.local/"))
    }

    private func boot() async {
        let source = EngineStore.activeBundle()
        do {
            _ = try await webView.callAsyncJavaScript("return MoriEngine.boot(bundle)",
                                                      arguments: ["bundle": source.text],
                                                      contentWorld: .page)
            activeVersion = source.version
            isOTA = source.isOTA
            state = .ready
            readyWaiters.forEach { $0.resume() }
            readyWaiters.removeAll()
        } catch {
            if source.isOTA {
                // Corrupted OTA patch → fall back to the bundled core
                EngineStore.removeOTA()
                reload()
                return
            }
            state = .failed(error.localizedDescription)
            readyWaiters.forEach { $0.resume(throwing: error) }
            readyWaiters.removeAll()
        }
    }

    private func waitUntilReady() async throws {
        switch state {
        case .ready: return
        case .failed:
            reload()
            try await withCheckedThrowingContinuation { readyWaiters.append($0) }
        case .loading:
            try await withCheckedThrowingContinuation { readyWaiters.append($0) }
        }
    }

    // MARK: API

    func analyze(url: String, source: String? = nil, prefer: String? = nil) async throws -> AnalyzeOutcome {
        try await waitUntilReady()
        let opts: [String: Any] = [
            "source": source ?? "",
            "prefer": prefer ?? AppSettings.shared.preferServer.rawValue,
            "config": AppSettings.shared.engineConfig,
        ]
        let raw = try await webView.callAsyncJavaScript(
            "const r = await MoriEngine.analyze(url, opts); return JSON.stringify(r);",
            arguments: ["url": url, "opts": opts],
            contentWorld: .page)
        guard let json = raw as? String,
              let data = json.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(message: "Unknown error occurred.")
        }
        return AnalyzeOutcome(json: obj)
    }

    /// Converts tokenized / indirect links (YouTube, Spotify, SnapSave…) into direct media URLs.
    func resolve(url: String, taskID: String, progress: @escaping (Double, String) -> Void) async throws -> String? {
        try await waitUntilReady()
        progressHandlers[taskID] = progress
        defer { progressHandlers[taskID] = nil }
        let raw = try await withTaskCancellationHandler {
            try await webView.callAsyncJavaScript(
                "const r = await MoriEngine.resolve(url, id, opts); return JSON.stringify(r);",
                arguments: ["url": url, "id": taskID, "opts": ["config": AppSettings.shared.engineConfig]],
                contentWorld: .page)
        } onCancel: {
            Task { @MainActor in self.cancelResolve(taskID: taskID) }
        }
        guard let json = raw as? String,
              let data = json.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return url }
        if (obj["cancelled"] as? Bool) == true { return nil }
        return (obj["url"] as? String) ?? url
    }

    func cancelResolve(taskID: String) {
        webView.evaluateJavaScript("MoriEngine.cancel(\(jsString(taskID)))", completionHandler: nil)
    }

    func needsResolving(_ url: String) -> Bool {
        let lower = url.lowercased()
        let markers = ["ytdown", "worker", "youtube_resolve:", "ytmp3gg_resolve:", "soundloaders_resolve:",
                       "spotidown_resolve:", "applemusic_resolve:"]
        let tokenized = markers.contains { url.contains($0) } || (url.contains("token=") && url.contains("snapsave"))
        let direct = lower.range(of: #"\.(mp4|mp3|m4a|zip|pdf|jpg|jpeg|png|webp)(\?|$)"#, options: .regularExpression) != nil
        return tokenized && !direct
    }

    private func jsString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        let arr = String(decoding: data, as: UTF8.self)
        return String(arr.dropFirst().dropLast())
    }

    fileprivate func handle(message: WKScriptMessage) {
        switch message.name {
        case "moriProgress":
            guard let body = message.body as? [String: Any], let id = body["id"] as? String else { return }
            let pct = (body["pct"] as? NSNumber)?.doubleValue ?? 0
            progressHandlers[id]?(pct, body["text"] as? String ?? "")
        case "moriLog":
            #if DEBUG
            print("[MoriEngine]", message.body)
            #endif
        default: break
        }
    }
}

struct EngineError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension ScraperEngine: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in await self.boot() }
    }

    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor in self.reload() }
    }
}

private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var engine: ScraperEngine?
    init(_ engine: ScraperEngine) { self.engine = engine }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { engine?.handle(message: message) }
    }
}

/// Keeps the engine's web view inside the window hierarchy so WebKit never throttles its timers.
struct EngineHostView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        container.isUserInteractionEnabled = false
        container.alpha = 0.01
        let web = ScraperEngine.shared.webView
        web.removeFromSuperview()
        web.frame = container.bounds
        container.addSubview(web)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
