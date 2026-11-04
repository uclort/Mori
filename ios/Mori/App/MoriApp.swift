import LocalAuthentication
import SwiftUI

@main
struct MoriApp: App {
    @StateObject private var engine = ScraperEngine.shared
    @StateObject private var downloads = DownloadManager.shared
    @StateObject private var history = HistoryStore.shared
    @StateObject private var library = LibraryStore.shared
    @StateObject private var model = AnalyzeModel()
    @ObservedObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .environmentObject(downloads)
                .environmentObject(history)
                .environmentObject(library)
                .environmentObject(model)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(Color("AccentColor"))
                .onOpenURL(perform: handle)
                .task {
                    #if DEBUG
                    // xcrun simctl launch <udid> com.mori.downloader -moriTestURL <link>
                    if let link = UserDefaults.standard.string(forKey: "moriTestURL") {
                        if link == "demo:photos" { model.showDemoPhotos() } else { model.analyze(url: link) }
                    }
                    #endif
                }
        }
    }

    /// mori://analyze?url=<link>  — also accepts mori://<link> and shared http(s) URLs.
    private func handle(_ url: URL) {
        var target: String?
        if url.scheme == "mori" {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            target = comps?.queryItems?.first(where: { $0.name == "url" || $0.name == "text" })?.value
            if target == nil {
                let rest = url.absoluteString.replacingOccurrences(of: "mori://", with: "")
                target = URLExtractor.firstURL(in: rest.removingPercentEncoding ?? rest)
            }
        } else if url.scheme?.hasPrefix("http") == true {
            target = url.absoluteString
        }
        guard let link = target.flatMap(URLExtractor.firstURL(in:)) else { return }
        model.path.removeAll()
        model.analyze(url: link)
    }
}

struct RootView: View {
    enum Tab: Hashable { case home, gallery, history, settings }

    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: Tab = .home
    @State private var locked = AppSettings.shared.appLock
    @State private var authenticating = false

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                HomeView()
                    .tabItem { Label("Home", systemImage: "arrow.down.circle") }
                    .tag(Tab.home)
                if !settings.hideGalleryTab {
                    GalleryView()
                        .tabItem { Label("Gallery", systemImage: "photo.on.rectangle") }
                        .tag(Tab.gallery)
                }
                HistoryView(selectedTab: $tab)
                    .tabItem { Label("History", systemImage: "clock") }
                    .tag(Tab.history)
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(Tab.settings)
            }

            if locked { lockScreen }
        }
        .background(EngineHostView().frame(width: 1, height: 1).allowsHitTesting(false))
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                if settings.appLock { locked = true }
            case .active:
                if locked { unlock() }
            default: break
            }
        }
        .onAppear {
            if locked { unlock() }
            #if DEBUG
            switch UserDefaults.standard.string(forKey: "moriTab") {
            case "gallery": tab = .gallery
            case "history": tab = .history
            case "settings": tab = .settings
            default: break
            }
            #endif
        }
    }

    private var lockScreen: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("Mori is locked").font(.headline)
                Button("Unlock") { unlock() }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
        .transition(.opacity)
    }

    private func unlock() {
        guard settings.appLock else {
            locked = false
            return
        }
        guard !authenticating else { return }
        authenticating = true
        let ctx = LAContext()
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Unlock Mori")) { ok, _ in
            DispatchQueue.main.async {
                authenticating = false
                if ok { withAnimation { locked = false } }
            }
        }
    }
}
