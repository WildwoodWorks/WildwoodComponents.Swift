// URLProtocol stub for view-model tests that need a real (mocked) HTTP
// round-trip — the WildwoodSwiftUITests twin of WildwoodCoreTests'
// MockBackend. Each test creates a TestBackend with a unique host, so suites
// can run in parallel without clobbering each other's stubs.

import Foundation
import Synchronization

struct TestStubResponse {
    var statusCode: Int
    var body: Data
    var headers: [String: String]

    init(statusCode: Int = 200, body: Data = Data(), headers: [String: String] = ["Content-Type": "application/json"]) {
        self.statusCode = statusCode
        self.body = body
        self.headers = headers
    }

    init(statusCode: Int = 200, json: String) {
        self.init(statusCode: statusCode, body: Data(json.utf8))
    }

    init(sse text: String) {
        self.init(statusCode: 200, body: Data(text.utf8), headers: ["Content-Type": "text/event-stream"])
    }
}

/// One request the stub saw. Recorded so a test can assert that a call was NOT made — which is
/// the only way to pin "a registration token's plan is never subscribed over".
struct TestRecordedRequest: Sendable {
    var method: String
    var host: String
    /// Percent-DECODED, because `URL.path` is.
    var path: String
    var body: Data?
    /// The query string without the leading `?`; stubs are keyed by path alone, so this is where
    /// a test asserts a flag such as `?immediate=false` went up.
    var query: String?
}

/// Per-test stub registry bound to a unique host.
final class TestBackend: Sendable {
    let host: String

    var baseUrl: String { "https://\(host)" }

    init() {
        host = "test-\(UUID().uuidString.lowercased()).local"
    }

    func stub(_ method: String, _ path: String, _ response: TestStubResponse) {
        TestURLProtocol.handlers.withLock { $0["\(method) \(host) \(path)"] = response }
    }

    func requests() -> [TestRecordedRequest] {
        TestURLProtocol.recorded.withLock { $0.filter { $0.host == host } }
    }

    func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TestURLProtocol.self]
        return URLSession(configuration: config)
    }
}

final class TestURLProtocol: URLProtocol {
    static let handlers = Mutex<[String: TestStubResponse]>([:])
    static let recorded = Mutex<[TestRecordedRequest]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let host = request.url?.host() ?? ""
        let path = request.url?.path ?? ""

        var bodyData = request.httpBody
        if bodyData == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            bodyData = data
        }

        Self.recorded.withLock {
            $0.append(
                TestRecordedRequest(
                    method: method,
                    host: host,
                    path: path,
                    body: bodyData,
                    query: request.url?.query
                )
            )
        }

        let stub = Self.handlers.withLock { $0["\(method) \(host) \(path)"] }
            ?? TestStubResponse(statusCode: 404, json: #"{"message":"no stub registered"}"#)

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
