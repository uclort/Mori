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
    /// Single file whose delete confirmation is showing (anchored to its cell).
    @State private var deleteTarget: URL?
    /// Delete confirmation for the current selection (anchored to the floating menu).
    @State private var confirmDeleteSelection = false
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
                                .confirmationDialog("Delete files?",
                                                    isPresented: Binding(get: { deleteTarget == file.url },
                                                                         set: { if !$0 { deleteTarget = nil } }),
                                                    titleVisibility: .visible) {
                                    Button("Delete", role: .destructive) { delete([file]) }
                                    Button("Cancel", role: .cancel) {}
                                } message: {
                                    Text("This permanently removes the files from your device.")
                                }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, selecting ? 80 : 12)
            }
            .refreshable { library.refresh() }
            .searchable(text: $search, prompt: "Search files")
            .navigationTitle("Gallery")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(selecting ? "Done" : "Select") {
                        withAnimation { selecting.toggle() }
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
            .overlay(alignment: .bottomTrailing) {
                if selecting {
                    selectionMenu
                        .padding(.trailing, 20)
                        .padding(.bottom, 16)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, selecting ? 84 : 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .quickLookPreview($preview, in: visible.filter { $0.kind == .audio || $0.kind == .pdf || $0.kind == .other }.map(\.url))
            .sheet(item: Binding(get: { shareItems.map(ShareItems.init) }, set: { shareItems = $0?.urls })) {
                ShareSheet(items: $0.urls)
            }
        }
    }

    private var selectedFiles: [LibraryFile] { visible.filter { selection.contains($0.url) } }

    /// Floating "…" button; actions open from it and the delete confirmation anchors to it.
    private var selectionMenu: some View {
        Menu {
            Section(selection.isEmpty ? String(localized: "No files selected")
                    : String(localized: "\(selection.count) selected")) {
                Button { saveToPhotos(selectedFiles) } label: {
                    Label("Save to Photos", systemImage: "photo.badge.plus")
                }
                .disabled(!selectedFiles.contains { PhotoSaver.canSave($0.url) })
                Button { shareItems = selectedFiles.map(\.url) } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(selection.isEmpty)
                Button(role: .destructive) { confirmDeleteSelection = true } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selection.isEmpty)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Color.accentColor, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                .overlay(alignment: .topTrailing) {
                    if !selection.isEmpty {
                        Text("\(selection.count)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.red, in: Capsule())
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Actions")
        .accessibilityIdentifier("gallery-actions")
        .confirmationDialog("Delete files?", isPresented: $confirmDeleteSelection, titleVisibility: .visible) {
            Button("Delete \(selection.count) files", role: .destructive) { delete(selectedFiles) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the files from your device.")
        }
    }

    @ViewBuilder
    private func contextMenu(for file: LibraryFile) -> some View {
        Button { open(file) } label: { Label("Open", systemImage: "eye") }
        ShareLink(item: file.url) { Label("Share", systemImage: "square.and.arrow.up") }
        if PhotoSaver.canSave(file.url) {
            Button { saveToPhotos([file]) } label: { Label("Save to Photos", systemImage: "photo.badge.plus") }
        }
        Button {
            withAnimation { selecting = true }
            selection = [file.url]
        } label: { Label("Select", systemImage: "checkmark.circle") }
        Button(role: .destructive) {
            // Let the context menu finish dismissing before anchoring the confirmation to the cell
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { deleteTarget = file.url }
        } label: { Label("Delete", systemImage: "trash") }
    }

    private func tap(_ file: LibraryFile) {
        if selecting {
            if selection.contains(file.url) { selection.remove(file.url) } else { selection.insert(file.url) }
        } else {
            open(file)
        }
    }

    private func open(_ file: LibraryFile) {
        switch file.kind {
        case .photo:
            let photos = visible.filter { $0.kind == .photo }
            let index = photos.firstIndex(of: file) ?? 0
            PhotoBrowserPresenter.present(photos.map { .local($0.url) }, startAt: index)
        case .video:
            SystemVideoPlayer.play(file.url)
        default:
            preview = file.url
        }
    }

    private func delete(_ targets: [LibraryFile]) {
        library.delete(targets)
        selection.subtract(targets.map(\.url))
        deleteTarget = nil
        if selecting && library.files.isEmpty { selecting = false }
        Haptics.success()
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
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel(file.name)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("gallery-cell")
    }
}
