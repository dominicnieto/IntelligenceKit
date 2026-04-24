/**
 Server-Sent Events (SSE) transport implementation for MCP.

 Port of `packages/mcp/src/tool/mcp-sse-transport.ts`.
 Upstream commit: f3a72bc2a

 This transport uses SSE for receiving messages and HTTP POST for sending messages,
 following the MCP specification.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

// MARK: - URL Extensions

extension URL {
    /// Returns the origin of the URL (scheme + host + port)
    /// Matches TypeScript's URL.origin behavior
    var origin: String {
        guard let scheme = scheme?.lowercased(),
              let host = host?.lowercased()
        else {
            var components: [String] = []

            if let scheme = scheme {
                components.append("\(scheme)://")
            }

            if let host = host {
                components.append(host)
            }

            if let port = port {
                components.append(":\(port)")
            }

            return components.joined()
        }

        var origin = "\(scheme)://\(host)"

        if let port = port {
            let defaultPort: Int? = switch scheme {
            case "http": 80
            case "https": 443
            default: nil
            }

            if port != defaultPort {
                origin.append(":\(port)")
            }
        }

        return origin
    }
}

/**
 SSE-based transport for MCP communication.

 The transport:
 1. Connects via SSE to receive an endpoint URL
 2. Receives messages via SSE events
 3. Sends messages via HTTP POST to the endpoint URL

 - Note: Requires macOS 12.0+ for streaming bytes API
 */
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public actor SseMCPTransport: MCPTransport {
    nonisolated private let url: URL
    nonisolated private let session: URLSession
    nonisolated private let headers: [String: String]?
    nonisolated private let authProvider: (any OAuthClientProvider)?

    private var endpoint: URL?
    private var streamTask: Task<Void, Never>?
    private var connected = false
    private var resourceMetadataUrl: URL?
    private var eventHandler: MCPTransportEventHandler?

    public init(config: MCPTransportConfig) throws {
        try self.init(config: config, session: .shared)
    }

    internal init(config: MCPTransportConfig, session: URLSession) throws {
        guard let parsedUrl = URL(string: config.url) else {
            throw MCPClientError(message: "Invalid URL: \(config.url)")
        }
        self.url = parsedUrl
        self.session = session
        self.headers = config.headers
        self.authProvider = config.authProvider
    }

    public init(
        url: String,
        headers: [String: String]? = nil,
        authProvider: (any OAuthClientProvider)? = nil
    ) throws {
        try self.init(url: url, headers: headers, authProvider: authProvider, session: .shared)
    }

    internal init(
        url: String,
        headers: [String: String]? = nil,
        authProvider: (any OAuthClientProvider)? = nil,
        session: URLSession
    ) throws {
        guard let parsedUrl = URL(string: url) else {
            throw MCPClientError(message: "Invalid URL: \(url)")
        }
        self.url = parsedUrl
        self.session = session
        self.headers = headers
        self.authProvider = authProvider
    }

    public func setEventHandler(_ handler: MCPTransportEventHandler?) async {
        eventHandler = handler
    }

    public func start() async throws {
        if connected {
            return
        }

        try await establishConnection(triedAuth: false)
    }

    public func close() async throws {
        connected = false
        let taskToAwait = streamTask
        streamTask = nil

        taskToAwait?.cancel()
        if let taskToAwait {
            _ = await taskToAwait.result
        }

        await emit(.close)
    }

    public func send(message: JSONRPCMessage) async throws {
        guard let endpoint, connected else {
            throw MCPClientError(message: "MCP SSE Transport Error: Not connected")
        }

        await attemptSend(endpoint: endpoint, message: message, triedAuth: false)
    }

    // MARK: - Private Methods

    private func emit(_ event: MCPTransportEvent) async {
        guard let eventHandler else { return }
        await eventHandler(event)
    }

    private func commonHeaders(base: [String: String]) async -> [String: String] {
        var merged: [String: String?] = [:]

        if let headers {
            for (k, v) in headers {
                merged[k] = v
            }
        }

        for (k, v) in base {
            merged[k] = v
        }

        merged["mcp-protocol-version"] = LATEST_PROTOCOL_VERSION

        if let authProvider, let tokens = try? await authProvider.tokens() {
            merged["Authorization"] = "Bearer \(tokens.accessToken)"
        }

        return withUserAgentSuffix(
            merged,
            "ai-sdk/\(VERSION)",
            getRuntimeEnvironmentUserAgent()
        )
    }

    private func attemptSend(endpoint: URL, message: JSONRPCMessage, triedAuth: Bool) async {
        do {
            let headers = await commonHeaders(base: [
                "Content-Type": "application/json"
            ])

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }

            request.httpBody = try JSONEncoder().encode(message)

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                await emit(.error(MCPTransportEventError(
                    MCPClientError(message: "MCP SSE Transport Error: Invalid response type")
                )))
                return
            }

            if http.statusCode == 401, let authProvider, !triedAuth {
                resourceMetadataUrl = extractResourceMetadataUrl(http)
                do {
                    let result = try await auth(
                        authProvider,
                        serverUrl: url,
                        authorizationCode: nil,
                        scope: nil,
                        resourceMetadataUrl: resourceMetadataUrl
                    )
                    guard result == .authorized else {
                        await emit(.error(MCPTransportEventError(UnauthorizedError())))
                        return
                    }
                } catch {
                    await emit(.error(MCPTransportEventError(error)))
                    return
                }

                await attemptSend(endpoint: endpoint, message: message, triedAuth: true)
                return
            }

            guard (200...299).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? "null"
                await emit(.error(MCPTransportEventError(
                    MCPClientError(
                        message: "MCP SSE Transport Error: POSTing to endpoint (HTTP \(http.statusCode)): \(text)"
                    )
                )))
                return
            }
        } catch is CancellationError {
            return
        } catch {
            await emit(.error(MCPTransportEventError(error)))
        }
    }

    private func establishConnection(triedAuth: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var didResolve = false

            let task = Task { [weak self] in
                guard let self else {
                    if !didResolve {
                        didResolve = true
                        continuation.resume(throwing: MCPClientError(message: "MCP SSE Transport Error: Transport deallocated"))
                    }
                    return
                }

                do {
                    var triedAuthLocal = triedAuth
                    var asyncBytes: URLSession.AsyncBytes?

                    while true {
                        var request = URLRequest(url: self.url)
                        request.httpMethod = "GET"

                        let headers = await self.commonHeaders(base: [
                            "Accept": "text/event-stream"
                        ])
                        for (key, value) in headers {
                            request.setValue(value, forHTTPHeaderField: key)
                        }

                        let (bytes, response) = try await self.session.bytes(for: request)
                        guard let httpResponse = response as? HTTPURLResponse else {
                            throw MCPClientError(message: "MCP SSE Transport Error: Invalid response type")
                        }

                        if httpResponse.statusCode == 401, let authProvider = self.authProvider, !triedAuthLocal {
                            await self.setResourceMetadataUrl(extractResourceMetadataUrl(httpResponse))
                            do {
                                let result = try await auth(
                                    authProvider,
                                    serverUrl: self.url,
                                    authorizationCode: nil,
                                    scope: nil,
                                    resourceMetadataUrl: await self.resourceMetadataUrlValue()
                                )
                                guard result == .authorized else {
                                    let error = UnauthorizedError()
                                    await self.emit(.error(MCPTransportEventError(error)))
                                    if !didResolve {
                                        didResolve = true
                                        continuation.resume(throwing: error)
                                    }
                                    return
                                }
                            } catch {
                                await self.emit(.error(MCPTransportEventError(error)))
                                if !didResolve {
                                    didResolve = true
                                    continuation.resume(throwing: error)
                                }
                                return
                            }

                            triedAuthLocal = true
                            continue
                        }

                        guard (200...299).contains(httpResponse.statusCode) else {
                            var errorMessage = "MCP SSE Transport Error: \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"
                            if httpResponse.statusCode == 405 {
                                errorMessage += ". This server does not support SSE transport. Try using `http` transport instead"
                            }
                            let error = MCPClientError(message: errorMessage)
                            await self.emit(.error(MCPTransportEventError(error)))
                            if !didResolve {
                                didResolve = true
                                continuation.resume(throwing: error)
                            }
                            return
                        }

                        asyncBytes = bytes
                        break
                    }

                    guard let asyncBytes else { return }

                    let eventStream = makeServerSentEventStream(from: Self.dataStream(from: asyncBytes))

                    for try await event in eventStream {
                        if Task.isCancelled {
                            return
                        }

                        switch event.event {
                        case "endpoint":
                            guard let endpointUrl = URL(string: event.data, relativeTo: self.url) else {
                                throw MCPClientError(
                                    message: "MCP SSE Transport Error: Invalid endpoint URL: \(event.data)"
                                )
                            }

                            if endpointUrl.origin != self.url.origin {
                                throw MCPClientError(
                                    message: "MCP SSE Transport Error: Endpoint origin does not match connection origin: \(endpointUrl.origin)"
                                )
                            }

                            await self.setConnectedEndpoint(endpointUrl)
                            if !didResolve {
                                didResolve = true
                                continuation.resume()
                            }

                        case "message":
                            guard let data = event.data.data(using: .utf8) else {
                                await self.emit(.error(MCPTransportEventError(
                                    MCPClientError(
                                        message: "MCP SSE Transport Error: Failed to decode message data"
                                    )
                                )))
                                continue
                            }

                            do {
                                let message = try JSONDecoder().decode(JSONRPCMessage.self, from: data)
                                await self.emit(.message(message))
                            } catch {
                                await self.emit(.error(MCPTransportEventError(
                                    MCPClientError(
                                        message: "MCP SSE Transport Error: Failed to parse message",
                                        cause: error
                                    )
                                )))
                            }

                        default:
                            break
                        }
                    }

                    let wasConnected = await self.markConnectionClosed()
                    if wasConnected {
                        throw MCPClientError(
                            message: "MCP SSE Transport Error: Connection closed unexpectedly"
                        )
                    } else if !didResolve {
                        let error = MCPClientError(
                            message: "MCP SSE Transport Error: Connection closed unexpectedly"
                        )
                        didResolve = true
                        continuation.resume(throwing: error)
                    }
                } catch is CancellationError {
                    if !didResolve {
                        didResolve = true
                        continuation.resume(throwing: CancellationError())
                    }
                } catch {
                    await self.emit(.error(MCPTransportEventError(error)))
                    if !didResolve {
                        didResolve = true
                        continuation.resume(throwing: error)
                    }
                }
            }

            streamTask = task
        }
    }

    private func setConnectedEndpoint(_ endpoint: URL) {
        self.endpoint = endpoint
        self.connected = true
    }

    private func markConnectionClosed() -> Bool {
        let wasConnected = connected
        connected = false
        return wasConnected
    }

    private func setResourceMetadataUrl(_ url: URL?) {
        resourceMetadataUrl = url
    }

    private func resourceMetadataUrlValue() -> URL? {
        resourceMetadataUrl
    }

    private nonisolated static func dataStream(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { streamContinuation in
            Task {
                do {
                    var buffer = Data()
                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= 1024 || byte == UInt8(ascii: "\n") {
                            streamContinuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty {
                        streamContinuation.yield(buffer)
                    }
                    streamContinuation.finish()
                } catch {
                    streamContinuation.finish(throwing: error)
                }
            }
        }
    }
}

/**
 Deserialize a line of text as a JSON-RPC message.

 - Parameter line: The line to deserialize
 - Returns: The deserialized JSON-RPC message
 - Throws: DecodingError if the line is not a valid JSON-RPC message
 */
public func deserializeMessage(_ line: String) throws -> JSONRPCMessage {
    guard let data = line.data(using: .utf8) else {
        throw MCPClientError(message: "Failed to encode line as UTF-8")
    }
    let decoder = JSONDecoder()
    return try decoder.decode(JSONRPCMessage.self, from: data)
}
