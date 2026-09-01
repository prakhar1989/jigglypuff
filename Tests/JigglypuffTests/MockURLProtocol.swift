import Foundation

/// A mock URLProtocol to intercept and mock HTTP requests in integration tests without hitting live Gemini servers.
public final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    public typealias RequestHandler = (URLRequest) throws -> (HTTPURLResponse, Data)
    
    private nonisolated(unsafe) static var lock = os_unfair_lock_s()
    public nonisolated(unsafe) static var requestHandler: RequestHandler?
    public nonisolated(unsafe) static var recordedRequests: [URLRequest] = []

    public static func reset() {
        os_unfair_lock_lock(&lock)
        requestHandler = nil
        recordedRequests.removeAll()
        os_unfair_lock_unlock(&lock)
    }

    public static func getRecordedRequests() -> [URLRequest] {
        os_unfair_lock_lock(&lock)
        let requests = recordedRequests
        os_unfair_lock_unlock(&lock)
        return requests
    }

    private static func recordRequest(_ request: URLRequest) {
        os_unfair_lock_lock(&lock)
        recordedRequests.append(request)
        os_unfair_lock_unlock(&lock)
    }

    public override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    public override func startLoading() {
        MockURLProtocol.recordRequest(request)

        guard let handler = MockURLProtocol.requestHandler else {
            let error = NSError(domain: "MockURLProtocol", code: 404, userInfo: [NSLocalizedDescriptionKey: "No mock handler configured"])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    public override func stopLoading() {}
}
