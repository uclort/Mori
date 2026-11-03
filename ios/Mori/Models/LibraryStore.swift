import SwiftUI
import QuickLookThumbnailing

struct LibraryFile: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let size: Int64
    let date: Date
    let kind: MediaKind
    let folder: String

    static func kind(for url: URL) -> MediaKind {
        let ext = url.pathExtension.lowercased()
        if FileNaming.videoExtensions.contains(ext) { return .video }
        if FileNaming.imageExtensions.contains(ext) { return .photo }
        if FileNaming.audioExtensions.contains(ext) { return .audio }
        if ext == "pdf" { return .pdf }
        return .other
    }
}

/// Everything saved in the app's Documents folder.
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var files: [LibraryFile] = []
    @Published private(set) var isLoading = false

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .moriLibraryChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let scanned = Self.scan()
            await MainActor.run {
                self.files = scanned
                self.isLoading = false
            }
        }
    }

    nonisolated static func scan() -> [LibraryFile] {
        let root = StorageLocations.documents
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [LibraryFile] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            // Only media and PDFs — skip temp files, logs and anything else lying around
            let kind = LibraryFile.kind(for: url)
            if kind == .other { continue }
            out.append(LibraryFile(url: url,
                                   name: url.lastPathComponent,
                                   size: Int64(values.fileSize ?? 0),
                                   date: values.creationDate ?? values.contentModificationDate ?? .distantPast,
                                   kind: kind,
                                   folder: url.deletingLastPathComponent().lastPathComponent))
        }
        return out.sorted { $0.date > $1.date }
    }

    func delete(_ targets: [LibraryFile]) {
        for f in targets { try? FileManager.default.removeItem(at: f.url) }
        let removed = Set(targets.map(\.url))
        files.removeAll { removed.contains($0.url) }
    }

    func deleteAll() {
        delete(files)
        for dir in [StorageLocations.media, StorageLocations.music] {
            try? FileManager.default.removeItem(at: dir)
        }
        refresh()
    }

    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }

    func stats() -> [(kind: MediaKind, count: Int, size: Int64)] {
        MediaKind.allCases.compactMap { kind in
            let list = files.filter { $0.kind == kind }
            return list.isEmpty ? nil : (kind, list.count, list.reduce(0) { $0 + $1.size })
        }
    }
}

/// QuickLook-generated thumbnails for local files.
struct FileThumbnail: View {
    let file: LibraryFile
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: file.kind.systemImage).font(.title2).foregroundStyle(.secondary))
            }
        }
        .task(id: file.url) {
            let req = QLThumbnailGenerator.Request(fileAt: file.url, size: CGSize(width: 240, height: 240),
                                                   scale: 2, representationTypes: .thumbnail)
            if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req) {
                image = rep.uiImage
            }
        }
    }
}
