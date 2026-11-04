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
    @State private var pasteButtonWidth: CGFloat?

    var body: some View {
        NavigationStack(path: $model.path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    inputCard
                    statusView
                    PlatformList()
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

    // MARK: Input

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if model.input.isEmpty {
                        Text("Paste or type a link")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $model.input)
                        .scrollContentBackground(.hidden)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($inputFocused)
                        .frame(minHeight: 72, maxHeight: 150)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)

                HStack(spacing: 6) {
                    Image(systemName: batchCount > 1 ? "square.stack.3d.up.fill" : "info.circle")
                    Text(hintText)
                    Spacer(minLength: 0)
                    if !model.input.isEmpty {
                        Button {
                            model.input = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.body)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Clear")
                    }
                }
                .font(.caption)
                .foregroundStyle(batchCount > 1 || clipboardHint ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .padding(.top, 6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
            .onTapGesture { inputFocused = true }

            HStack(spacing: 10) {
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    Task { @MainActor in append(text) }
                }
                .buttonBorderShape(.capsule)
                .labelStyle(.titleAndIcon)
                .controlSize(.regular)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: WidthKey.self, value: proxy.size.width)
                })
                .onPreferenceChange(WidthKey.self) { pasteButtonWidth = $0 }

                Spacer(minLength: 0)

                analyzeButton
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Same size, style and font as the system paste button.
    @ViewBuilder
    private var analyzeButton: some View {
        Group {
            if model.isAnalyzing {
                Button(role: .cancel) {
                    model.cancel()
                } label: {
                    Label("Cancel", systemImage: "stop.fill").frame(minWidth: pasteButtonWidth.map { $0 - 28 })
                }
                .buttonStyle(.bordered)
            } else {
                Button(action: startAnalyze) {
                    Label("Analyze", systemImage: "sparkle.magnifyingglass")
                        .frame(minWidth: pasteButtonWidth.map { $0 - 28 })
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        // Server choice anchors to the button that started the analysis
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
    }

    private var batchCount: Int { URLExtractor.urls(in: model.input).count }

    private var clipboardHint: Bool { clipboardHasURL && model.input.isEmpty }

    private var hintText: String {
        if batchCount > 1 { return String(localized: "\(batchCount) links — they will be analyzed in batch") }
        if clipboardHint { return String(localized: "Link detected in clipboard — tap Paste") }
        return String(localized: "One link per line. Several links are analyzed in batch.")
    }

    /// Pasting never starts analysis, so several links can be collected first (one per line).
    private func append(_ text: String) {
        let incoming = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incoming.isEmpty else { return }
        let current = model.input.trimmingCharacters(in: .whitespacesAndNewlines)
        model.input = current.isEmpty ? incoming : current + "\n" + incoming
        clipboardHasURL = false
        Haptics.tap()
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

private struct WidthKey: PreferenceKey {
    static var defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
}

/// Display-only list of supported platforms (no button-like chrome).
private struct PlatformList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Supported platforms")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 16) {
                ForEach(Platform.allCases) { p in
                    VStack(spacing: 6) {
                        Image(systemName: p.systemImage)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(p.tint)
                            .frame(height: 22)
                        Text(p.shortName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .allowsHitTesting(false)
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
