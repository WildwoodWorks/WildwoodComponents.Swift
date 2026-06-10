// URLProtocol stub for HttpClient/service tests — requests never leave the
// process; handlers are registered per-path.

import Foundation
import Synchronization
@testable import WildwoodCore

final class MockURLProtocol: URLProtocol {
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
        var path: String
        var headers: [String: String]
        var body: Data?
    }

    // Handlers keyed by "METHOD path" (path without query); a default handler key of "*" catches everything else.
    nonisolated(unsafe) static let handlers = Mutex<[String: StubResponse]>([:])
    nonisolated(unsafe) static let recorded = Mutex<[RecordedRequest]>([])

    static func reset() {
        handlers.withLock { $0 = [:] }
        recorded.withLock { $0 = [] }
    }

    static func stub(_ method: String, _ path: String, _ response: StubResponse) {
        handlers.withLock { $0["\(method) \(path)"] = response }
    }

    static func requests() -> [RecordedRequest] {
        recorded.withLock { $0 }
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
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
            $0.append(RecordedRequest(method: method, path: path, headers: headers, body: bodyData))
        }

        let stub = Self.handlers.withLock { $0["\(method) \(path)"] ?? $0["*"] }
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
