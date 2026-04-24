/**
 HTTP MCP transport implementing the Streamable HTTP style.

 Port of `packages/mcp/src/tool/mcp-http-transport.ts`.
 Upstream commit: f3a72bc2a
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public actor HttpMCPTransport: MCPTransport {
    private struct ReconnectionOptions: Sendable {
        let initialReconnectionDelay: TimeInterval = 1.0
        let maxReconnectionDelay: TimeInterval = 30.0
        let reconnectionDelayGrowFactor: Double = 1.5
        let maxRetries: Int = 2
    }

    nonisolated private let url: URL
    nonisolated private let session: URLSession
    nonisolated private let headers: [String: String]?
    nonisolated private let authProvider: OAuthClientProvider?

    private var resourceMetadataUrl: URL?
    private var sessionId: String?
    private var started = false
    private var isClosed = false
    private var inboundSseTask: Task<Void, Never>?
    private var inboundSseConnectionActive = false
    private var lastInboundEventId: String?
    private var inboundReconnectAttempts = 0
    private var reconnectionTask: Task<Void, Never>?
    private var activeTasks: [Task<Void, Never>] = []
    private var eventHandler: MCPTransportEventHandler?

    private let reconnectionOptions = ReconnectionOptions()

    public init(config: MCPTransportConfig) throws {
        try self.init(config: config, session: .shared)
    }

    internal init(config: MCPTransportConfig, session: URLSession) throws {
        guard let parsed = URL(string: config.url) else {
            throw MCPClientError(message: "Invalid URL: \(config.url)")
        }

        self.url = parsed
        self.session = session
        self.headers = config.headers
        self.authProvider = config.authProvider
    }

    public init(
        url: String,
        headers: [String: String]? = nil,
        authProvider: OAuthClientProvider? = nil
    ) throws {
        try self.init(url: url, headers: headers, authProvider: authProvider, session: .shared)
    }

    internal init(
        url: String,
        headers: [String: String]? = nil,
        authProvider: OAuthClientProvider? = nil,
        session: URLSession
    ) throws {
        guard let parsed = URL(string: url) else {
            throw MCPClientError(message: "Invalid URL: \(url)")
        }

        self.url = parsed
        self.session = session
        self.headers = headers
        self.authProvider = authProvider
    }

    public func setEventHandler(_ handler: MCPTransportEventHandler?) async {
        eventHandler = handler
    }

    public func start() async throws {
        if started {
            throw MCPClientError(
                message: "MCP HTTP Transport Error: Transport already started. Note: client.connect() calls start() automatically."
            )
        }

        started = true
        isClosed = false
        await launchInboundSse(resumeToken: nil)

        await Task.yield()
    }

    public func close() async throws {
        let wasClosed = isClosed
        isClosed = true
        inboundSseConnectionActive = false

        let sessionId = self.sessionId
        let inboundTask = inboundSseTask
        let reconnectionTask = self.reconnectionTask
        let activeTasks = self.activeTasks

        inboundSseTask = nil
        self.reconnectionTask = nil
        self.activeTasks.removeAll()

        if wasClosed {
            await emit(.close)
            return
        }

        inboundTask?.cancel()
        reconnectionTask?.cancel()
        for task in activeTasks {
            task.cancel()
        }

        if let inboundTask {
            _ = await inboundTask.result
        }
        if let reconnectionTask {
            _ = await reconnectionTask.result
        }
        for task in activeTasks {
            _ = await task.result
        }

        do {
            if sessionId != nil {
                let headers = await commonHeaders(base: [:], includeSessionId: true)
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                _ = try await session.data(for: request)
            }
        } catch {
            _ = error
        }

        await emit(.close)
    }

    public func send(message: JSONRPCMessage) async throws {
        try await attemptSend(message: message, triedAuth: false)
    }

    // MARK: - Private

    private func emit(_ event: MCPTransportEvent) async {
        guard let eventHandler else { return }
        await eventHandler(event)
    }

    private func commonHeaders(base: [String: String], includeSessionId: Bool) async -> [String: String] {
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

        if includeSessionId, let sessionId {
            merged["mcp-session-id"] = sessionId
        }

        if let authProvider, let tokens = try? await authProvider.tokens() {
            merged["Authorization"] = "Bearer \(tokens.accessToken)"
        }

        return withUserAgentSuffix(
            merged,
            "ai-sdk/\(VERSION)",
            getRuntimeEnvironmentUserAgent()
        )
    }

    private func attemptSend(message: JSONRPCMessage, triedAuth: Bool) async throws {
        do {
            let headers = await commonHeaders(
                base: [
                    "Content-Type": "application/json",
                    "Accept": "application/json, text/event-stream",
                ],
                includeSessionId: true
            )

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }

            request.httpBody = try JSONEncoder().encode(message)

            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MCPClientError(message: "MCP HTTP Transport Error: Invalid response type")
            }

            if let sessionIdHeader = httpResponse.value(forHTTPHeaderField: "mcp-session-id") {
                sessionId = sessionIdHeader
            }

            if httpResponse.statusCode == 401, let authProvider, !triedAuth {
                resourceMetadataUrl = extractResourceMetadataUrl(httpResponse)
                do {
                    let result = try await auth(
                        authProvider,
                        serverUrl: url,
                        authorizationCode: nil,
                        scope: nil,
                        resourceMetadataUrl: resourceMetadataUrl
                    )
                    guard result == .authorized else {
                        let error = UnauthorizedError()
                        await emit(.error(MCPTransportEventError(error)))
                        throw error
                    }
                } catch {
                    await emit(.error(MCPTransportEventError(error)))
                    throw error
                }

                try await attemptSend(message: message, triedAuth: true)
                return
            }

            if httpResponse.statusCode == 202 {
                if !inboundSseConnectionActive {
                    inboundSseTask?.cancel()
                    await launchInboundSse(resumeToken: nil)
                }

                Task { _ = try? await Self.collectData(from: bytes) }
                return
            }

            if !(200...299).contains(httpResponse.statusCode) {
                let data = try await Self.collectData(from: bytes)
                let text = String(data: data, encoding: .utf8) ?? "null"
                var errorMessage = "MCP HTTP Transport Error: POSTing to endpoint (HTTP \(httpResponse.statusCode)): \(text)"

                if httpResponse.statusCode == 404 {
                    errorMessage += ". This server does not support HTTP transport. Try using `sse` transport instead"
                }

                let error = MCPClientError(message: errorMessage)
                await emit(.error(MCPTransportEventError(error)))
                throw error
            }

            let isNotification: Bool = {
                if case .notification = message { return true }
                return false
            }()

            if isNotification {
                Task { _ = try? await Self.collectData(from: bytes) }
                return
            }

            let contentType = httpResponse.value(forHTTPHeaderField: "content-type") ?? ""

            if contentType.contains("application/json") {
                let data = try await Self.collectData(from: bytes)
                let decodedMessages = try Self.decodeMessages(from: data)

                for message in decodedMessages {
                    await emit(.message(message))
                }
                return
            }

            if contentType.contains("text/event-stream") {
                let task = Task { [weak self] in
                    guard let self else { return }
                    await self.processEventStreamBytes(bytes)
                }
                activeTasks.append(task)
                return
            }

            Task { _ = try? await Self.collectData(from: bytes) }

            let error = MCPClientError(message: "MCP HTTP Transport Error: Unexpected content type: \(contentType)")
            await emit(.error(MCPTransportEventError(error)))
            throw error
        } catch {
            await emit(.error(MCPTransportEventError(error)))
            throw error
        }
    }

    private func processEventStreamBytes(_ bytes: URLSession.AsyncBytes) async {
        let stream = Self.dataStream(from: bytes)
        let eventStream = makeServerSentEventStream(from: stream)

        do {
            for try await event in eventStream {
                if Task.isCancelled { return }

                if event.event == "message" {
                    do {
                        let data = Data(event.data.utf8)
                        let message = try JSONDecoder().decode(JSONRPCMessage.self, from: data)
                        await emit(.message(message))
                    } catch {
                        await emit(.error(MCPTransportEventError(
                            MCPClientError(
                                message: "MCP HTTP Transport Error: Failed to parse message",
                                cause: error
                            )
                        )))
                    }
                }
            }
        } catch is CancellationError {
            return
        } catch {
            await emit(.error(MCPTransportEventError(error)))
        }
    }

    private func getNextReconnectionDelay(attempt: Int) -> TimeInterval {
        let delay = reconnectionOptions.initialReconnectionDelay * pow(reconnectionOptions.reconnectionDelayGrowFactor, Double(attempt))
        return min(delay, reconnectionOptions.maxReconnectionDelay)
    }

    private func scheduleInboundSseReconnection() async {
        if isClosed { return }

        if reconnectionOptions.maxRetries > 0 && inboundReconnectAttempts >= reconnectionOptions.maxRetries {
            await emit(.error(MCPTransportEventError(
                MCPClientError(
                    message: "MCP HTTP Transport Error: Maximum reconnection attempts (\(reconnectionOptions.maxRetries)) exceeded."
                )
            )))
            return
        }

        let delay = getNextReconnectionDelay(attempt: inboundReconnectAttempts)
        inboundReconnectAttempts += 1

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }

            let (isClosed, resumeToken) = await self.reconnectionContext()
            if isClosed { return }
            await self.launchInboundSse(resumeToken: resumeToken)
        }

        reconnectionTask = task
    }

    private func reconnectionContext() -> (Bool, String?) {
        (isClosed, lastInboundEventId)
    }

    private func launchInboundSse(resumeToken: String?) async {
        let task = Task { [weak self] in
            guard let self else { return }
            await self.openInboundSse(triedAuth: false, resumeToken: resumeToken)
        }
        inboundSseTask = task
    }

    private func openInboundSse(triedAuth: Bool, resumeToken: String?) async {
        defer {
            inboundSseTask = nil
            inboundSseConnectionActive = false
        }

        do {
            var baseHeaders: [String: String] = ["Accept": "text/event-stream"]
            if let resumeToken {
                baseHeaders["last-event-id"] = resumeToken
            }

            let headers = await commonHeaders(base: baseHeaders, includeSessionId: true)

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }

            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                await emit(.error(MCPTransportEventError(
                    MCPClientError(message: "MCP HTTP Transport Error: Invalid response type")
                )))
                return
            }

            if let sessionIdHeader = httpResponse.value(forHTTPHeaderField: "mcp-session-id") {
                sessionId = sessionIdHeader
            }

            if httpResponse.statusCode == 401, let authProvider, !triedAuth {
                resourceMetadataUrl = extractResourceMetadataUrl(httpResponse)
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

                await openInboundSse(triedAuth: true, resumeToken: resumeToken)
                return
            }

            if httpResponse.statusCode == 405 {
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                await emit(.error(MCPTransportEventError(
                    MCPClientError(
                        message: "MCP HTTP Transport Error: GET SSE failed: \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"
                    )
                )))
                return
            }

            inboundSseConnectionActive = true
            inboundReconnectAttempts = 0

            let eventStream = makeServerSentEventStream(from: Self.dataStream(from: bytes))

            for try await event in eventStream {
                if Task.isCancelled { return }

                switch event.event {
                case "message":
                    if let id = event.id {
                        lastInboundEventId = id
                    }
                    do {
                        let data = Data(event.data.utf8)
                        let message = try JSONDecoder().decode(JSONRPCMessage.self, from: data)
                        await emit(.message(message))
                    } catch {
                        await emit(.error(MCPTransportEventError(
                            MCPClientError(
                                message: "MCP HTTP Transport Error: Failed to parse inbound SSE message",
                                cause: error
                            )
                        )))
                    }

                default:
                    continue
                }
            }

            if !isClosed {
                await scheduleInboundSseReconnection()
            }
        } catch is CancellationError {
            return
        } catch {
            await emit(.error(MCPTransportEventError(error)))
            if !isClosed {
                await scheduleInboundSseReconnection()
            }
        }
    }

    private nonisolated static func decodeMessages(from data: Data) throws -> [JSONRPCMessage] {
        if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
            if let array = json as? [Any] {
                return try array.map { element in
                    let elementData = try JSONSerialization.data(withJSONObject: element, options: [])
                    return try JSONDecoder().decode(JSONRPCMessage.self, from: elementData)
                }
            } else {
                return [try JSONDecoder().decode(JSONRPCMessage.self, from: data)]
            }
        }

        return [try JSONDecoder().decode(JSONRPCMessage.self, from: data)]
    }

    private nonisolated static func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        data.reserveCapacity(16_384)
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    private nonisolated static func dataStream(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var buffer = Data()
                buffer.reserveCapacity(16_384)

                do {
                    for try await byte in bytes {
                        buffer.append(byte)

                        if buffer.count >= 1024 || byte == UInt8(ascii: "\n") {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }

                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
