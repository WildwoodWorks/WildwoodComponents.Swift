// URLProtocol stub for HttpClient/service tests — requests never leave the
// process. Each test creates a MockBackend with a unique host, so suites can
// run in parallel without clobbering each other's stubs.

import Foundation
import Synchronization
@testable import WildwoodCore

struct StubResponse {
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
}

struct RecordedRequest: Sendable {
    var method: String
    var host: String
    var path: String
    var headers: [String: String]
    var body: Data?
}

/// Per-test stub registry bound to a unique host.
final class MockBackend: Sendable {
    let host: String

    var baseUrl: String { "https://\(host)" }

    init() {
        host = "test-\(UUID().uuidString.lowercased()).local"
    }

    func stub(_ method: String, _ path: String, _ response: StubResponse) {
        MockURLProtocol.handlers.withLock { $0["\(method) \(host) \(path)"] = response }
    }

    /// Stub a transport-level failure (timeout, connection refused, cancellation)
    /// rather than an HTTP response — the path `WildwoodHttpClient` funnels through
    /// `mapTransportError`. Takes precedence over a `stub` for the same route.
    func stubError(_ method: String, _ path: String, _ code: URLError.Code) {
        MockURLProtocol.errors.withLock { $0["\(method) \(host) \(path)"] = code }
    }

    func requests() -> [RecordedRequest] {
        MockURLProtocol.recorded.withLock { $0.filter { $0.host == host } }
    }

    func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

final class MockURLProtocol: URLProtocol {
    static let handlers = Mutex<[String: StubResponse]>([:])
    static let errors = Mutex<[String: URLError.Code]>([:])
    static let recorded = Mutex<[RecordedRequest]>([])

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

        var headers: [String: String] = [:]
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            headers[key] = value
        }
        Self.recorded.withLock {
            $0.append(RecordedRequest(method: method, host: host, path: path, headers: headers, body: bodyData))
        }

        if let code = Self.errors.withLock({ $0["\(method) \(host) \(path)"] }) {
            client?.urlProtocol(self, didFailWithError: URLError(code))
            return
        }

        let stub = Self.handlers.withLock { $0["\(method) \(host) \(path)"] }
            ?? StubResponse(statusCode: 404, json: #"{"message":"no stub registered"}"#)

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
