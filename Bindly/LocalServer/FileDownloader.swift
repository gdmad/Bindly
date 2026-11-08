import Foundation

/// One file download with progress and cancellation. A delegate session rather than
/// `URLSession.download(for:)`, which reports no progress: the LanguageTool archive is 250 MB.
final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let expectedSize: Int64
    private let onProgress: @Sendable (Double) -> Void

    private let lock = NSLock()
    private var continuation: CheckedContinuation<HTTPURLResponse, Error>?
    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private var moveError: Error?
    private var cancelled = false

    private init(destination: URL, expectedSize: Int64, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.expectedSize = expectedSize
        self.onProgress = onProgress
    }

    /// Downloads `url` to `destination` and returns the final response (headers included).
    /// `expectedSize` stands in for the server's length when it sends none.
    static func download(_ url: URL, to destination: URL, expectedSize: Int64 = 0,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> HTTPURLResponse {
        let downloader = FileDownloader(destination: destination, expectedSize: expectedSize, onProgress: progress)
        return try await withTaskCancellationHandler {
            try await downloader.run(url)
        } onCancel: {
            downloader.cancel()
        }
    }

    private func run(_ url: URL) async throws -> HTTPURLResponse {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if cancelled {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
            let task = session.downloadTask(with: url)
            self.session = session
            self.task = task
            lock.unlock()
            task.resume()
        }
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    private func finish(_ result: Result<HTTPURLResponse, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let session = self.session
        self.session = nil
        lock.unlock()
        session?.finishTasksAndInvalidate()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        guard total > 0 else { return }
        onProgress(min(1, Double(totalBytesWritten) / Double(total)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file is deleted as soon as this returns, so it is moved here.
        guard let http = downloadTask.response as? HTTPURLResponse, http.statusCode == 200 else { return }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            lock.lock(); moveError = error; lock.unlock()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let wasCancelled = cancelled
        let moveError = self.moveError
        lock.unlock()
        if wasCancelled { return finish(.failure(CancellationError())) }
        if let error { return finish(.failure(error)) }
        guard let http = task.response as? HTTPURLResponse else { return finish(.failure(URLError(.badServerResponse))) }
        guard http.statusCode == 200 else { return finish(.failure(LocalServerError.badResponse(http.statusCode))) }
        if let moveError { return finish(.failure(moveError)) }
        finish(.success(http))
    }
}
