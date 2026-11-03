import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var model: AnalyzeModel
    @EnvironmentObject private var downloads: DownloadManager
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var inputFocused: Bool
    @State private var clipboardHasURL = false
    @State private var showDownloads = false

    var body: some View {
        NavigationStack(path: $model.path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    inputCard
                    if clipboardHasURL && model.input.isEmpty && !model.isAnalyzing {
                        clipboardBanner
                    }
                    statusView
                    PlatformGrid()
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Mori")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    DownloadsToolbarButton { showDownloads = true }
                }
            }
            .navigationDestination(for: ResultRoute.self) { route in
                ResultView(url: route.url, platform: route.platform, result: route.result)
            }
        }
        .sheet(isPresented: $showDownloads) { DownloadsView() }
        .sheet(item: $model.batch) { BatchView(session: $0) }
        .confirmationDialog("Choose Server",
                            isPresented: Binding(get: { model.serverPrompt != nil },
                                                 set: { if !$0 { model.serverPrompt = nil } }),
                            titleVisibility: .visible,
                            presenting: model.serverPrompt) { prompt in
            if prompt.sources.count >= 2 {
                Button("Server 1") { model.choose(source: prompt.sources[0], for: prompt) }
                Button("Server 2") { model.choose(source: prompt.sources[1], for: prompt) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { prompt in
            Text(prompt.platform?.serverDescription ?? "")
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { detectClipboard() }
        }
        .onAppear { detectClipboard() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Save anything, from anywhere.")
                .font(.title2.weight(.bold))
            Text("Videos, photos and music from 16 platforms. No watermarks, no accounts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var inputCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
                TextField("Paste a link — or several for batch mode", text: $model.input, axis: .vertical)
                    .lineLimit(1...6)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($inputFocused)
                    .submitLabel(.go)
                    .onSubmit(startAnalyze)
                if !model.input.isEmpty {
                    Button {
                        model.input = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
            }
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))

            HStack(spacing: 12) {
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    Task { @MainActor in
                        model.input = text
                        clipboardHasURL = false
                        if URLExtractor.urls(in: text).count == 1 { model.analyze() }
                    }
                }
                .buttonBorderShape(.capsule)
                .labelStyle(.titleAndIcon)

                Spacer(minLength: 0)

                if model.isAnalyzing {
                    Button(role: .cancel) {
                        model.cancel()
                    } label: {
                        Label("Cancel", systemImage: "stop.fill")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                } else {
                    Button(action: startAnalyze) {
                        Label(batchCount > 1 ? "Analyze \(batchCount)" : "Analyze", systemImage: "sparkle.magnifyingglass")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var batchCount: Int { URLExtractor.urls(in: model.input).count }

    private var clipboardBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Link detected in clipboard").font(.subheadline.weight(.semibold))
                Text("Tap Paste to analyze it").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in
                    clipboardHasURL = false
                    model.input = text
                    model.analyze()
                }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.capsule)
        }
        .padding(12)
        .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.phase {
        case .analyzing:
            HStack(spacing: 12) {
                ProgressView()
                Text(platformHint).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .failed(let message):
            Label {
                Text(message).font(.subheadline)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture { model.phase = .idle }
        case .idle:
            EmptyView()
        }
    }

    private var platformHint: String {
        if let p = Platform.detect(model.input) {
            return String(localized: "Analyzing \(p.displayName) link…")
        }
        return String(localized: "Analyzing link…")
    }

    private func startAnalyze() {
        inputFocused = false
        model.analyze()
    }

    private func detectClipboard() {
        guard settings.clipboardDetection else {
            clipboardHasURL = false
            return
        }
        // Pattern detection does not trigger the paste permission prompt
        UIPasteboard.general.detectPatterns(for: [\.probableWebURL]) { result in
            let has = (try? result.get())?.contains(\.probableWebURL) ?? false
            DispatchQueue.main.async {
                withAnimation { clipboardHasURL = has }
            }
        }
    }
}

private struct PlatformGrid: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Supported platforms")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(Platform.allCases) { p in
                    HStack(spacing: 6) {
                        Image(systemName: p.systemImage)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(p.tint)
                            .frame(width: 18)
                        Text(p.displayName)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                }
            }
        }
    }
}

struct DownloadsToolbarButton: View {
    @EnvironmentObject private var downloads: DownloadManager
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if downloads.hasActive {
                    Circle().stroke(.quaternary, lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: downloads.overallProgress)
                        .stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: downloads.overallProgress)
                    Text("\(downloads.activeItems.count)")
                        .font(.caption2.weight(.bold))
                } else {
                    Image(systemName: "arrow.down.circle")
                }
            }
            .frame(width: 26, height: 26)
        }
        .accessibilityLabel("Downloads")
    }
}
