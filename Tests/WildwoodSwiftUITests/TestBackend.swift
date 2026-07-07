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

    func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TestURLProtocol.self]
        return URLSession(configuration: config)
    }
}

final class TestURLProtocol: URLProtocol {
    static let handlers = Mutex<[String: TestStubResponse]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let host = request.url?.host() ?? ""
        let path = request.url?.path ?? ""

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
