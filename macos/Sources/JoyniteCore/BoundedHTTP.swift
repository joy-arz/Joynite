import Foundation

public enum BoundedHTTP {
    public static func data(for request: URLRequest, maximumBytes: Int, session: URLSession = .shared,
                            acceptsURL: @escaping @Sendable (URL) -> Bool = { $0.scheme == "https" && $0.host != nil }) async throws -> (Data, HTTPURLResponse) {
        guard maximumBytes > 0, let url = request.url, acceptsURL(url) else { throw LibraryError.invalid("Unsupported download URL.") }
        let transfer = Transfer(configuration: session.configuration, request: request, limit: maximumBytes, acceptsURL: acceptsURL)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { transfer.start($0) }
        } onCancel: { transfer.cancel() }
    }
}

private final class Transfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let configuration: URLSessionConfiguration
    private let request: URLRequest
    private let limit: Int
    private let acceptsURL: @Sendable (URL) -> Bool
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var response: HTTPURLResponse?
    private var received = Data()
    private var ended = false

    init(configuration: URLSessionConfiguration, request: URLRequest, limit: Int, acceptsURL: @escaping @Sendable (URL) -> Bool) {
        self.configuration = configuration
        self.request = request
        self.limit = limit
        self.acceptsURL = acceptsURL
        configuration.timeoutIntervalForResource = min(configuration.timeoutIntervalForResource, 45)
    }
    func start(_ continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) {
        lock.lock()
        guard !ended else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        lock.unlock()
        task.resume()
    }
    func cancel() { finish(.failure(CancellationError())) }
    private func finish(_ result: Result<(Data, HTTPURLResponse), Error>) {
        lock.lock()
        guard !ended else { lock.unlock(); return }
        ended = true
        let continuation = self.continuation
        self.continuation = nil
        let session = self.session
        self.session = nil
        let task = self.task
        self.task = nil
        received = Data()
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, let url = http.url, acceptsURL(url), (200..<300).contains(http.statusCode) else {
            completionHandler(.cancel)
            finish(.failure(LibraryError.invalid("The remote service did not provide a supported response.")))
            return
        }
        guard response.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel)
            finish(.failure(LibraryError.invalid("Download exceeds the \(limit)-byte limit.")))
            return
        }
        lock.lock(); self.response = http; let active = !ended; lock.unlock()
        completionHandler(active ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !ended else { lock.unlock(); return }
        guard data.count <= limit - received.count else {
            lock.unlock()
            finish(.failure(LibraryError.invalid("Download exceeds the \(limit)-byte limit.")))
            return
        }
        received.append(data)
        lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, acceptsURL(url) else {
            completionHandler(nil)
            finish(.failure(LibraryError.invalid("Unsupported download redirect.")))
            return
        }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)); return }
        lock.lock(); let data = received; let response = self.response; lock.unlock()
        guard let response else { finish(.failure(LibraryError.invalid("The remote service returned no response."))); return }
        finish(.success((data, response)))
    }
}
