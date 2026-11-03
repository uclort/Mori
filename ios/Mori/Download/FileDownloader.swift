import Foundation

/// URLSession download task wrapper with byte-level progress and cooperative cancellation.
final class FileDownloader: NSObject, URLSessionDownloadDelegate {
    static let shared = FileDownloader()

    struct DownloadError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Response {
        let fileURL: URL
        let mimeType: String?
        let suggestedFilename: String?
        let expectedLength: Int64
    }

    private final class Job {
        let progress: (Int64, Int64) -> Void
        let continuation: CheckedContinuation<Response, Error>
        var movedFile: URL?
        var response: HTTPURLResponse?
        init(progress: @escaping (Int64, Int64) -> Void, continuation: CheckedContinuation<Response, Error>) {
            self.progress = progress
            self.continuation = continuation
        }
    }

    private let lock = NSLock()
    private var jobs: [Int: Job] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60 * 6
        config.httpMaximumConnectionsPerHost = 6
        config.httpCookieStorage = .shared
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func download(_ request: URLRequest, progress: @escaping (Int64, Int64) -> Void) async throws -> Response {
        let holder = TaskHolder()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Response, Error>) in
                let task = session.downloadTask(with: request)
                lock.lock()
                jobs[task.taskIdentifier] = Job(progress: progress, continuation: cont)
                lock.unlock()
                holder.task = task
                if Task.isCancelled { task.cancel() } else { task.resume() }
            }
        } onCancel: {
            holder.task?.cancel()
        }
    }

    private final class TaskHolder: @unchecked Sendable {
        var task: URLSessionTask?
    }

    private func job(for task: URLSessionTask) -> Job? {
        lock.lock(); defer { lock.unlock() }
        return jobs[task.taskIdentifier]
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        job(for: downloadTask)?.progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let job = job(for: downloadTask) else { return }
        // The temporary file disappears when this method returns — move it now
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("mori-\(UUID().uuidString).part")
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            job.movedFile = dest
        } catch {
            job.movedFile = nil
        }
        job.response = downloadTask.response as? HTTPURLResponse
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let job = jobs.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        guard let job else { return }

        if let error {
            if let f = job.movedFile { try? FileManager.default.removeItem(at: f) }
            if (error as NSError).code == NSURLErrorCancelled {
                job.continuation.resume(throwing: CancellationError())
            } else {
                job.continuation.resume(throwing: error)
            }
            return
        }
        let http = job.response ?? (task.response as? HTTPURLResponse)
        if let http, !(200..<400).contains(http.statusCode) {
            if let f = job.movedFile { try? FileManager.default.removeItem(at: f) }
            job.continuation.resume(throwing: DownloadError(message: "HTTP \(http.statusCode)"))
            return
        }
        guard let file = job.movedFile else {
            job.continuation.resume(throwing: DownloadError(message: String(localized: "Download failed")))
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
        if size == 0 {
            try? FileManager.default.removeItem(at: file)
            job.continuation.resume(throwing: DownloadError(message: String(localized: "The server returned an empty file.")))
            return
        }
        job.continuation.resume(returning: Response(fileURL: file,
                                                    mimeType: http?.mimeType,
                                                    suggestedFilename: http?.suggestedFilename,
                                                    expectedLength: http?.expectedContentLength ?? -1))
    }
}
