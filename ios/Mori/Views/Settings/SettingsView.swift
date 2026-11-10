import LocalAuthentication
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject private var engine: ScraperEngine
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var history: HistoryStore

    @State private var engineStatus: String?
    @State private var checkingEngine = false
    @State private var confirmClearFiles = false
    @State private var confirmClearHistory = false
    @State private var lockError: String?
    @State private var cacheSize: UInt?
    @State private var clearingCache = false
    @State private var folderError: String?

    var body: some View {
        NavigationStack {
            Form {
                downloadSection
                parsingSection
                privacySection
                appearanceSection
                engineSection
                storageSection
                aboutSection
            }
            .navigationTitle("Settings")
            .task { cacheSize = await ImageLoader.diskCacheSize() }
            .alert("Face ID", isPresented: Binding(get: { lockError != nil }, set: { if !$0 { lockError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(lockError ?? "") }
        }
    }

    private var downloadSection: some View {
        Section {
            Picker("Save location", selection: $settings.saveTarget) {
                ForEach(SaveTarget.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Sort into platform folders", isOn: $settings.autoPlatformFolder)
            Picker("File name", selection: $settings.filenameTemplate) {
                ForEach(FilenameTemplate.allCases) { Text($0.label).tag($0) }
            }
            Picker("If file exists", selection: $settings.overwriteMode) {
                ForEach(OverwriteMode.allCases) { Text($0.label).tag($0) }
            }
            Stepper(value: $settings.concurrentDownloads, in: 1...5) {
                LabeledContent("Simultaneous downloads", value: "\(settings.concurrentDownloads)")
            }
            Picker("Batch media format", selection: $settings.batchFormat) {
                ForEach(BatchFormat.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Auto-download first option", isOn: $settings.autoDownload)
            Button(action: openDownloadFolder) {
                Label("Open in Files", systemImage: "folder")
            }
            .alert("Error", isPresented: Binding(get: { folderError != nil }, set: { if !$0 { folderError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(folderError ?? "")
            }
        } header: {
            Text("Download")
        } footer: {
            Text("PDFs and audio always stay in Files. Files are visible in the Files app under On My iPhone › Mori.")
        }
    }

    /// iOS has no public deep link to a specific folder, so this is the closest
    /// we get: open the Files app, where the download folder lives.
    private func openDownloadFolder() {
        guard let url = URL(string: "shareddocuments://") else { return }
        UIApplication.shared.open(url, options: [:]) { opened in
            guard !opened else { return }
            DispatchQueue.main.async {
                folderError = String(localized: "The Files app could not be opened. Open it manually and look under On My iPhone › Mori.")
            }
        }
    }

    private var parsingSection: some View {
        Section {
            Picker("Preferred server", selection: $settings.preferServer) {
                ForEach(PreferServer.allCases) { Text($0.label).tag($0) }
            }
            Stepper(value: $settings.requestTimeout, in: 5...180, step: 5) {
                LabeledContent("Request timeout", value: "\(settings.requestTimeout) s")
            }
            Picker("User-Agent", selection: $settings.userAgent) {
                ForEach(UserAgentPreset.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Header spoofing", isOn: $settings.headerSpoofing)
            Toggle("Bypass SSL validation", isOn: $settings.bypassSSL)
        } header: {
            Text("Parsing")
        } footer: {
            Text("Server choice applies to TikTok, Instagram, YouTube, X and Spotify. Only bypass SSL validation on networks you trust.")
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            Toggle("Incognito (don't save history)", isOn: $settings.incognito)
            Toggle("Detect links in clipboard", isOn: $settings.clipboardDetection)
            Toggle(isOn: Binding(get: { settings.appLock }, set: { setLock($0) })) {
                Label("Lock with Face ID / passcode", systemImage: "faceid")
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $settings.appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Haptic feedback", isOn: $settings.haptics)
            Toggle("Hide Gallery tab", isOn: $settings.hideGalleryTab)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: url) {
                    LabeledContent("Language", value: Locale.current.localizedString(forIdentifier: Locale.preferredLanguages.first ?? "en") ?? "")
                }
            }
        }
    }

    private var engineSection: some View {
        Section {
            LabeledContent("Scraper core") {
                switch engine.state {
                case .ready:
                    Text("v\(engine.activeVersion) · \(engine.isOTA ? String(localized: "OTA") : String(localized: "Bundled"))")
                case .loading:
                    ProgressView()
                case .failed:
                    Text("Error").foregroundStyle(.red)
                }
            }
            Button {
                checkEngine()
            } label: {
                HStack {
                    Text("Check for engine update")
                    Spacer()
                    if checkingEngine { ProgressView() }
                }
            }
            .disabled(checkingEngine)
            if engine.isOTA {
                Button("Reset to bundled engine", role: .destructive) {
                    EngineStore.removeOTA()
                    engine.reload()
                    engineStatus = nil
                }
            }
        } header: {
            Text("Engine")
        } footer: {
            if let engineStatus { Text(engineStatus) } else {
                Text("Scraper fixes are hot-patched over the air without reinstalling the app.")
            }
        }
    }

    private var storageSection: some View {
        Section("Storage") {
            ForEach(library.stats(), id: \.kind) { stat in
                LabeledContent {
                    Text("\(stat.count) · \(ByteCountFormatter.string(fromByteCount: stat.size, countStyle: .file))")
                } label: {
                    Label(kindName(stat.kind), systemImage: stat.kind.systemImage)
                }
            }
            LabeledContent("Total", value: ByteCountFormatter.string(fromByteCount: library.totalSize, countStyle: .file))
            Button("Delete all downloaded files", role: .destructive) { confirmClearFiles = true }
                .disabled(library.files.isEmpty)
                .confirmationDialog("Delete all downloaded files?", isPresented: $confirmClearFiles, titleVisibility: .visible) {
                    Button("Delete all files", role: .destructive) { library.deleteAll() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Files saved to Photos are not affected.")
                }
            Button("Clear history", role: .destructive) { confirmClearHistory = true }
                .disabled(history.entries.isEmpty)
                .confirmationDialog("Clear all history?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
                    Button("Clear history", role: .destructive) { history.clear() }
                    Button("Cancel", role: .cancel) {}
                }
            Button {
                clearingCache = true
                Task {
                    await ImageLoader.clearAllCaches()
                    cacheSize = await ImageLoader.diskCacheSize()
                    clearingCache = false
                    Haptics.success()
                }
            } label: {
                HStack {
                    Text("Clear image cache")
                    Spacer()
                    if clearingCache {
                        ProgressView()
                    } else if let cacheSize {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(cacheSize), countStyle: .file))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(clearingCache)
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.appVersion)
            Link(destination: URL(string: "https://github.com/uclort/Mori")!) {
                Label("Source code", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Link(destination: URL(string: "https://github.com/uclort/Mori/releases")!) {
                Label("Releases", systemImage: "shippingbox")
            }
        } header: {
            Text("About")
        } footer: {
            Text("Mori is free software licensed under GPL-3.0. Scraper engines by coflyn and contributors. Only download content you have the right to save.")
        }
    }

    private func kindName(_ kind: MediaKind) -> LocalizedStringKey {
        switch kind {
        case .video: return "Videos"
        case .photo: return "Photos"
        case .audio: return "Audio"
        case .pdf: return "PDF"
        case .other: return "Other"
        }
    }

    private func checkEngine() {
        checkingEngine = true
        engineStatus = nil
        Task {
            defer { checkingEngine = false }
            do {
                switch try await EngineStore.checkForUpdate() {
                case .upToDate(let v):
                    engineStatus = String(localized: "Engine is up to date (v\(v)).")
                case .updated(let v, let log):
                    engine.reload()
                    engineStatus = String(localized: "Updated to v\(v).") + (log.map { " \($0)" } ?? "")
                }
            } catch {
                engineStatus = error.localizedDescription
            }
        }
    }

    private func setLock(_ enabled: Bool) {
        guard enabled else {
            settings.appLock = false
            return
        }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            lockError = err?.localizedDescription ?? String(localized: "Authentication is not available on this device.")
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Enable app lock")) { ok, _ in
            DispatchQueue.main.async { settings.appLock = ok }
        }
    }
}

extension Bundle {
    var appVersion: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
