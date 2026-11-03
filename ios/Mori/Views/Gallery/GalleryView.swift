import QuickLook
import SwiftUI

struct GalleryView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all, video, photo, audio, pdf
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .all: return "All"
            case .video: return "Videos"
            case .photo: return "Photos"
            case .audio: return "Audio"
            case .pdf: return "PDF"
            }
        }
    }

    @EnvironmentObject private var library: LibraryStore
    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var selecting = false
    @State private var selection = Set<URL>()
    @State private var preview: URL?
    @State private var shareItems: [URL]?
    @State private var confirmDelete: [LibraryFile]?
    @State private var toast: String?

    private var visible: [LibraryFile] {
        library.files.filter { f in
            let kindOK: Bool
            switch filter {
            case .all: kindOK = true
            case .video: kindOK = f.kind == .video
            case .photo: kindOK = f.kind == .photo
            case .audio: kindOK = f.kind == .audio
            case .pdf: kindOK = f.kind == .pdf
            }
            return kindOK && (search.isEmpty || f.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("\(visible.count) files · \(ByteCountFormatter.string(fromByteCount: visible.reduce(0) { $0 + $1.size }, countStyle: .file))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    if visible.isEmpty && !library.isLoading {
                        EmptyStateView(systemImage: "photo.on.rectangle.angled", title: "Nothing here yet",
                                       message: "Downloaded files appear here. They are also available in the Files app under On My iPhone › Mori.")
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 4)], spacing: 4) {
                        ForEach(visible) { file in
                            GalleryCell(file: file, selecting: selecting, selected: selection.contains(file.url))
                                .onTapGesture { tap(file) }
                                .contextMenu { contextMenu(for: file) }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .refreshable { library.refresh() }
            .searchable(text: $search, prompt: "Search files")
            .navigationTitle("Gallery")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(selecting ? "Done" : "Select") {
                        selecting.toggle()
                        selection.removeAll()
                    }
                    .disabled(visible.isEmpty && !selecting)
                }
                if selecting {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(selection.count == visible.count ? "Deselect all" : "Select all") {
                            selection = selection.count == visible.count ? [] : Set(visible.map(\.url))
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting { selectionBar }
            }
            .quickLookPreview($preview, in: visible.map(\.url))
            .sheet(item: Binding(get: { shareItems.map(ShareItems.init) }, set: { shareItems = $0?.urls })) {
                ShareSheet(items: $0.urls)
            }
            .confirmationDialog("Delete files?", isPresented: Binding(get: { confirmDelete != nil },
                                                                     set: { if !$0 { confirmDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete \(confirmDelete?.count ?? 0) files", role: .destructive) {
                    if let targets = confirmDelete {
                        library.delete(targets)
                        selection.subtract(targets.map(\.url))
                    }
                }
            } message: {
                Text("This permanently removes the files from your device.")
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, selecting ? 80 : 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private var selectedFiles: [LibraryFile] { visible.filter { selection.contains($0.url) } }

    private var selectionBar: some View {
        HStack {
            Button { saveToPhotos(selectedFiles) } label: {
                Label("Save to Photos", systemImage: "photo.badge.plus")
            }
            .disabled(!selectedFiles.contains { PhotoSaver.canSave($0.url) })
            Spacer()
            Button { shareItems = selectedFiles.map(\.url) } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(selection.isEmpty)
            Spacer()
            Button(role: .destructive) { confirmDelete = selectedFiles } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selection.isEmpty)
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .padding(.horizontal, 40)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private func contextMenu(for file: LibraryFile) -> some View {
        Button { preview = file.url } label: { Label("Open", systemImage: "eye") }
        ShareLink(item: file.url) { Label("Share", systemImage: "square.and.arrow.up") }
        if PhotoSaver.canSave(file.url) {
            Button { saveToPhotos([file]) } label: { Label("Save to Photos", systemImage: "photo.badge.plus") }
        }
        Button {
            selecting = true
            selection = [file.url]
        } label: { Label("Select", systemImage: "checkmark.circle") }
        Button(role: .destructive) { confirmDelete = [file] } label: { Label("Delete", systemImage: "trash") }
    }

    private func tap(_ file: LibraryFile) {
        if selecting {
            if selection.contains(file.url) { selection.remove(file.url) } else { selection.insert(file.url) }
        } else {
            preview = file.url
        }
    }

    private func saveToPhotos(_ files: [LibraryFile]) {
        let targets = files.filter { PhotoSaver.canSave($0.url) }
        guard !targets.isEmpty else { return }
        Task {
            var ok = 0
            var lastError: String?
            for f in targets {
                do {
                    try await PhotoSaver.save(f.url)
                    ok += 1
                } catch {
                    lastError = error.localizedDescription
                }
            }
            show(ok > 0 ? String(localized: "Saved \(ok) to Photos") : (lastError ?? String(localized: "Save failed")))
            if ok > 0 { Haptics.success() }
        }
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toast = nil }
        }
    }
}

private struct ShareItems: Identifiable {
    let id = UUID()
    let urls: [URL]
}

private struct GalleryCell: View {
    let file: LibraryFile
    let selecting: Bool
    let selected: Bool

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(FileThumbnail(file: file))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if file.kind != .photo {
                    Image(systemName: file.kind.systemImage)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if selecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, selected ? Color.accentColor : .black.opacity(0.3))
                        .padding(6)
                }
            }
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }
            .contentShape(Rectangle())
            .accessibilityLabel(file.name)
    }
}
