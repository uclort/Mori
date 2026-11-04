import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var model: AnalyzeModel
    @Binding var selectedTab: RootView.Tab
    @State private var search = ""
    @State private var confirmClear = false

    private var visible: [HistoryEntry] {
        guard !search.isEmpty else { return history.entries }
        return history.entries.filter {
            $0.result.title.localizedCaseInsensitiveContains(search)
                || ($0.result.author ?? "").localizedCaseInsensitiveContains(search)
                || $0.url.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    EmptyStateView(systemImage: "clock.arrow.circlepath", title: "No history",
                                   message: AppSettings.shared.incognito
                                   ? "Incognito mode is on — analyzed links are not recorded."
                                   : "Links you analyze will appear here.")
                } else {
                    List {
                        ForEach(visible) { entry in
                            NavigationLink(value: entry) {
                                HistoryRow(entry: entry)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { history.delete([entry.id]) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    selectedTab = .home
                                    model.path.removeAll()
                                    model.analyze(url: entry.url)
                                } label: {
                                    Label("Re-analyze", systemImage: "arrow.clockwise")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .searchable(text: $search, prompt: "Search history")
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: HistoryEntry.self) { entry in
                ResultView(url: entry.url, platform: entry.platform, result: entry.result)
            }
            .toolbar {
                if !history.entries.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear", role: .destructive) { confirmClear = true }
                            .confirmationDialog("Clear all history?", isPresented: $confirmClear, titleVisibility: .visible) {
                                Button("Clear history", role: .destructive) { history.clear() }
                                Button("Cancel", role: .cancel) {}
                            }
                    }
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: entry.result.thumbnail ?? entry.result.downloads.first(where: \.isPhoto)?.url,
                        sourceURL: entry.result.sourceUrl, maxPixel: 120)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.result.displayTitle.isEmpty ? String(localized: "Untitled") : entry.result.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let p = entry.platform {
                        Image(systemName: p.systemImage).foregroundStyle(p.tint)
                        Text(p.displayName)
                    }
                    Text(entry.date, style: .date)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
