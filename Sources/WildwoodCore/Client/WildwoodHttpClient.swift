// HTTP client mirroring @wildwood/core's HttpClient: auth header injection,
// retry with exponential backoff on 5xx/network errors, request timeout, and
// reactive 401 handling (refresh token once, then replay the request).
//
// Retry is limited to idempotent methods (GET/HEAD/OPTIONS/PUT/DELETE) and never
// covers timeouts or cancellation — see the guards in `request()` for why.
//
// PARITY: services must pass endpoint paths as double-quoted string literals
// to these verb methods — the Sync parity script extracts them by regex.

import Foundation

/// HTTP methods that may be replayed without changing the outcome (RFC 9110 §9.2.2).
///
/// PUT and DELETE qualify: both describe an end state, so applying them twice lands where
/// applying them once did. POST and PATCH do not — each is a fresh instruction to the server.
private let idempotentMethods: Set<String> = ["GET", "HEAD", "OPTIONS", "PUT", "DELETE"]

private func isIdempotent(_ method: String) -> Bool {
    idempotentMethods.contains(method.uppercased())
}

public actor WildwoodHttpClient {
    private let config: WildwoodConfig
    private let urlSession: URLSession
    private var tokenProvider: (@Sendable () async -> String?)?
    private var on401Refresh: (@Sendable () async -> Bool)?

    public init(config: WildwoodConfig, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
    }

    /// Set the function that provides the current access token.
    public func setTokenProvider(_ provider: @escaping @Sendable () async -> String?) {
        tokenProvider = provider
    }

    /// Set the function that handles 401 retry (refreshes token, returns true if refreshed).
    public func setOn401Refresh(_ handler: @escaping @Sendable () async -> Bool) {
        on401Refresh = handler
    }

    // MARK: - Verb methods (endpoint paths must be string literals — see header)
    // `timeout` overrides the config-level request timeout (seconds), mirroring
    // the JS RequestOptions.timeout for long-running calls (e.g. AI generation).

    public func get<T: Decodable & Sendable>(_ path: String, skipAuth: Bool = false, timeout: TimeInterval? = nil) async throws -> T {
        try decode(await request(method: "GET", path: path, bodyData: nil, skipAuth: skipAuth, timeout: timeout))
    }

    public func post<T: Decodable & Sendable>(_ path: String, body: some Encodable & Sendable, skipAuth: Bool = false, timeout: TimeInterval? = nil) async throws -> T {
        try decode(await request(method: "POST", path: path, bodyData: encode(body), skipAuth: skipAuth, timeout: timeout))
    }

    public func post<T: Decodable & Sendable>(_ path: String, skipAuth: Bool = false, timeout: TimeInterval? = nil) async throws -> T {
        try decode(await request(method: "POST", path: path, bodyData: nil, skipAuth: skipAuth, timeout: timeout))
    }

    public func postVoid(_ path: String, body: some Encodable & Sendable, skipAuth: Bool = false, timeout: TimeInterval? = nil) async throws {
        _ = try await request(method: "POST", path: path, bodyData: encode(body), skipAuth: skipAuth, timeout: timeout)
    }

    public func postVoid(_ path: String, skipAuth: Bool = false, timeout: TimeInterval? = nil) async throws {
        _ = try await request(method: "POST", path: path, bodyData: nil, skipAuth: skipAuth, timeout: timeout)
    }

    public func put<T: Decodable & Sendable>(_ path: String, body: some Encodable & Sendable, skipAuth: Bool = false, timeout: TimeInterval? = nil) async throws -> T {
        try decode(await request(method: "PUT", path: path, bodyData: encode(body), skipAuth: skipAuth, timeout: timeout))
    }

    public func putVoid(_ path: String, body: some Encodable & Sendable, skipAuth: Bool = false, timeout: TimeInterval? = nil) async throws {
        _ = try await request(method: "PUT", path: path, bodyData: encode(body), skipAuth: skipAuth, timeout: timeout)
    }

    public func delete<T: Decodable & Sendable>(_ path: String, skipAuth: Bool = false, timeout: TimeInterval? = nil) async throws -> T {
        try decode(await request(method: "DELETE", path: path, bodyData: nil, skipAuth: skipAuth, timeout: timeout))
    }

    public func deleteVoid(_ path: String, skipAuth: Bool = false, timeout: TimeInterval? = nil) async throws {
        _ = try await request(method: "DELETE", path: path, bodyData: nil, skipAuth: skipAuth, timeout: timeout)
    }

    public func patch<T: Decodable & Sendable>(_ path: String, body: some Encodable & Sendable, skipAuth: Bool = false, timeout: TimeInterval? = nil) async throws -> T {
        try decode(await request(method: "PATCH", path: path, bodyData: encode(body), skipAuth: skipAuth, timeout: timeout))
    }

    /// Raw-body GET for binary downloads (audio, images).
    public func getData(_ path: String, skipAuth: Bool = false, timeout: TimeInterval? = nil) async throws -> Data {
        try await request(method: "GET", path: path, bodyData: nil, skipAuth: skipAuth, timeout: timeout)
    }

    /// Raw-body POST for binary downloads (e.g. TTS audio).
    public func postData(_ path: String, body: some Encodable & Sendable, skipAuth: Bool = false, timeout: TimeInterval? = nil) async throws -> Data {
        try await request(method: "POST", path: path, bodyData: encode(body), skipAuth: skipAuth, timeout: timeout)
    }

    /// Server-sent-events POST for streaming endpoints (AI flow runs). Sends
    /// the request, then feeds each response body line (newline-delimited,
    /// CR stripped, empty lines included — SSE frame delimiters matter) to
    /// `onLine`; return false from the handler to stop reading early (e.g.
    /// after a terminal SSE event). A trailing unterminated line is delivered
    /// too. Non-2xx responses throw WildwoodError, with a single refresh +
    /// replay on 401 like the JSON verbs (a still-failing 401 means the
    /// refresh flow already emitted its session-expired signal). Returns the
    /// response Content-Type so callers can detect a plain-JSON (non-SSE)
    /// resolution body; for non-SSE responses the body is not read and
    /// `onLine` is never invoked.
    ///
    /// `timeout` is URLSession's idle timeout between chunks — flow nodes can
    /// work for a long time between events, so callers pass a generous value.
    public func post(
        _ path: String,
        body: some Encodable & Sendable,
        skipAuth: Bool = false,
        timeout: TimeInterval? = nil,
        onLine: @Sendable (String) async -> Bool
    ) async throws -> String {
        let bodyData = try encode(body)
        let url = try joinUrl(base: config.baseUrl, path: path)

        for attempt in 0..<2 {
            let urlRequest = await buildRequest(
                method: "POST",
                url: url,
                bodyData: bodyData,
                skipAuth: skipAuth,
                timeout: timeout,
                contentType: "application/json",
                accept: "text/event-stream"
            )

            let bytes: URLSession.AsyncBytes
            let response: URLResponse
            do {
                (bytes, response) = try await urlSession.bytes(for: urlRequest)
            } catch {
                throw Self.mapTransportError(error)
            }

            guard let http = response as? HTTPURLResponse else {
                throw WildwoodError(message: "Invalid response", status: 0, code: .networkError)
            }

            // Reactive 401 handling: refresh token and replay once, mirroring request().
            if await shouldRetryAfter401(status: http.statusCode, skipAuth: skipAuth, attempt: attempt) {
                continue
            }

            guard (200..<300).contains(http.statusCode) else {
                var errorBody = Data()
                do {
                    for try await byte in bytes {
                        errorBody.append(byte)
                        if errorBody.count >= 64_000 { break }
                    }
                } catch {
                    // Body read failed — report the status alone.
                }
                throw WildwoodError.fromResponse(
                    status: http.statusCode,
                    body: errorBody.isEmpty ? nil : errorBody,
                    fallbackMessage: HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                )
            }

            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
            guard contentType.lowercased().hasPrefix("text/event-stream") else {
                return contentType
            }

            // Manual line splitting: AsyncLineSequence-style helpers can drop
            // the empty lines that delimit SSE frames, so split on \n (safe —
            // UTF-8 continuation bytes are always >= 0x80) and strip a
            // trailing \r ourselves.
            //
            // Deliberately per-byte: AsyncBytes has no chunk API, and bridging
            // a delegate-based chunk reader would bypass the injected session.
            // The cost is one buffer append per byte, softened by the reserved
            // capacity below; correctness (empty-line preservation, partial
            // tail carry, early stop) beats raw throughput here.
            do {
                var lineBuffer: [UInt8] = []
                lineBuffer.reserveCapacity(4096)
                var stopped = false
                for try await byte in bytes {
                    if byte == 0x0A {
                        if lineBuffer.last == 0x0D { lineBuffer.removeLast() }
                        let line = String(decoding: lineBuffer, as: UTF8.self)
                        lineBuffer.removeAll(keepingCapacity: true)
                        if await onLine(line) == false {
                            stopped = true
                            break
                        }
                    } else {
                        lineBuffer.append(byte)
                    }
                }
                if !stopped, !lineBuffer.isEmpty {
                    _ = await onLine(String(decoding: lineBuffer, as: UTF8.self))
                }
            } catch {
                throw Self.mapTransportError(error)
            }
            return contentType
        }

        // Only reachable when the 401 replay came back 401 again without a
        // refresh attempt left; surface it like any other auth failure.
        throw WildwoodError(message: "Not authorized", status: 401)
    }

    /// Multipart/form-data POST for file uploads.
    public func postMultipart<T: Decodable & Sendable>(
        _ path: String,
        fileField: String,
        fileName: String,
        fileData: Data,
        mimeType: String,
        fields: [String: String] = [:],
        skipAuth: Bool = false,
        timeout: TimeInterval? = nil
    ) async throws -> T {
        let boundary = "WildwoodBoundary-\(UUID().uuidString)"
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let data = try await request(
            method: "POST",
            path: path,
            bodyData: body,
            skipAuth: skipAuth,
            timeout: timeout,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        return try decode(data)
    }

    // MARK: - Core request pipeline

    private func request(
        method: String,
        path: String,
        bodyData: Data?,
        skipAuth: Bool,
        timeout: TimeInterval? = nil,
        contentType: String = "application/json"
    ) async throws -> Data {
        let url = try joinUrl(base: config.baseUrl, path: path)
        let maxAttempts = config.enableRetry ? max(1, config.maxRetryAttempts) : 1

        var lastError = WildwoodError(message: "Request failed", status: 0, code: .networkError)

        for attempt in 0..<maxAttempts {
            do {
                return try await executeRequest(
                    method: method,
                    url: url,
                    bodyData: bodyData,
                    skipAuth: skipAuth,
                    timeout: timeout,
                    contentType: contentType
                )
            } catch let error as WildwoodError {
                lastError = error

                // Reactive 401 handling: refresh token and retry once.
                // Safe for every method, unlike the retries below: a 401 is refused by auth
                // middleware before the handler runs, so the request provably had no effect.
                if await shouldRetryAfter401(status: error.status, skipAuth: skipAuth, attempt: attempt) {
                    continue
                }

                // Never retried, for any method. A timeout says nothing about whether the server
                // processed the request — only that we stopped waiting for the answer. (Caller
                // cancellation is handled by never reaching here: mapTransportError returns a
                // CancellationError, which this catch clause does not match.)
                if error.code == .timeout {
                    throw error
                }

                // Only retry on 5xx or network errors, not 4xx.
                if error.status > 0, error.status < 500 {
                    throw error
                }

                // ...and only for methods that are safe to replay. Neither a network error nor a
                // 5xx tells us whether the server already applied the request, so replaying a POST
                // can duplicate the effect. That is not hypothetical: with the default timeout and
                // 3 attempts, one slow feedback submit filed the feedback three times, because the
                // row commits server-side before the response is produced.
                //
                // Callers who know a specific POST is safe to replay can retry it themselves; the
                // client cannot know that on their behalf.
                if !isIdempotent(method) {
                    throw error
                }

                if attempt < maxAttempts - 1 {
                    // Propagates CancellationError, aborting the retry loop.
                    let backoff = min(1.0 * pow(2.0, Double(attempt)), 10.0)
                    try await Task.sleep(for: .seconds(backoff))
                }
            }
            // Non-WildwoodError errors (e.g. CancellationError) propagate immediately.
        }

        throw lastError
    }

    private func executeRequest(
        method: String,
        url: URL,
        bodyData: Data?,
        skipAuth: Bool,
        timeout: TimeInterval?,
        contentType: String
    ) async throws -> Data {
        let urlRequest = await buildRequest(
            method: method,
            url: url,
            bodyData: bodyData,
            skipAuth: skipAuth,
            timeout: timeout,
            contentType: contentType
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: urlRequest)
        } catch {
            throw Self.mapTransportError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw WildwoodError(message: "Invalid response", status: 0, code: .networkError)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw WildwoodError.fromResponse(
                status: http.statusCode,
                body: data.isEmpty ? nil : data,
                fallbackMessage: HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }

        return data
    }

    // MARK: - Helpers

    /// Header/body assembly shared by the JSON pipeline and the SSE post:
    /// Content-Type, optional Accept, X-API-Key, and Bearer-token injection
    /// (skipped when `skipAuth`), plus the per-request timeout override.
    private func buildRequest(
        method: String,
        url: URL,
        bodyData: Data?,
        skipAuth: Bool,
        timeout: TimeInterval?,
        contentType: String,
        accept: String? = nil
    ) async -> URLRequest {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.timeoutInterval = timeout ?? config.requestTimeoutSeconds
        urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let accept {
            urlRequest.setValue(accept, forHTTPHeaderField: "Accept")
        }
        if let apiKey = config.apiKey {
            urlRequest.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        if !skipAuth, let tokenProvider, let token = await tokenProvider() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = bodyData
        return urlRequest
    }

    /// Single reactive refresh + replay, shared by request() and the SSE
    /// post: true only for a first-attempt 401 on an authenticated call whose
    /// token refresh succeeded — the caller then replays the request once.
    private func shouldRetryAfter401(status: Int, skipAuth: Bool, attempt: Int) async -> Bool {
        guard status == 401, !skipAuth, attempt == 0, let on401Refresh else { return false }
        return await on401Refresh()
    }

    /// Transport-error mapping shared by every URLSession call site: task
    /// cancellation must never be swallowed into a retryable network error,
    /// timeouts get the typed .timeout code, everything else is .networkError.
    private static func mapTransportError(_ error: any Error) -> any Error {
        if error is CancellationError {
            return CancellationError()
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled: return CancellationError()
            case .timedOut: return WildwoodError(message: "Request timed out", status: 0, code: .timeout)
            default: break
            }
        }
        return WildwoodError(message: error.localizedDescription, status: 0, code: .networkError)
    }

    private func joinUrl(base: String, path: String) throws -> URL {
        let normalizedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: normalizedBase + normalizedPath) else {
            throw WildwoodError(message: "Invalid URL: \(normalizedBase + normalizedPath)", status: 0, code: .unknown)
        }
        return url
    }

    private func encode(_ body: some Encodable) throws -> Data {
        try WildwoodJSON.encoder().encode(body)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        // Tolerate empty bodies (204 / no content) the way the JS client
        // yields undefined: optional-typed targets decode to nil, and the
        // EmptyBody marker type decodes to itself.
        if data.isEmpty {
            if let nilLiteralType = T.self as? any ExpressibleByNilLiteral.Type {
                return nilLiteralType.init(nilLiteral: ()) as! T
            }
            if let empty = EmptyBody() as? T {
                return empty
            }
        }
        do {
            return try WildwoodJSON.decoder().decode(T.self, from: data)
        } catch {
            throw WildwoodError(
                message: "Failed to decode response: \(error)",
                status: 0,
                code: .unknown,
                details: data
            )
        }
    }
}

/// Placeholder decode target for endpoints whose body is ignored.
public struct EmptyBody: Codable, Sendable {
    public init() {}
}
