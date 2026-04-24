import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Streaming helpers for building UI messages from streamed chunks.

 Port of `@ai-sdk/ai/src/ui/process-ui-message-stream.ts`.

 **Adaptations**:
 - Streams are represented as `AsyncThrowingStream` instead of Web `ReadableStream`.
 - Tool input/output payloads remain type-erased via `JSONValue`.
 - `onToolCall` receives the raw chunk (typed as `AnyUIMessageChunk`) since Swift lacks
   the higher-kinded generic inference used by the TypeScript version.
 */

public struct StreamingUIMessageJobContext<Message: UIMessageConvertible>: Sendable {
    public let state: StreamingUIMessageState<Message>
    public let write: @Sendable () async -> Void

    public init(
        state: StreamingUIMessageState<Message>,
        write: @escaping @Sendable () async -> Void
    ) {
        self.state = state
        self.write = write
    }
}

public typealias StreamingUIMessageJob<Message: UIMessageConvertible> =
    @Sendable (StreamingUIMessageJobContext<Message>) async throws -> Void

public actor StreamingUIMessageState<Message: UIMessageConvertible> {
    private var storage: Storage<Message>

    init(
        message: Message,
        activeTextPartIndices: [String: Int] = [:],
        activeReasoningPartIndices: [String: Int] = [:],
        partialToolCalls: [String: PartialToolCall] = [:]
    ) {
        storage = Storage(
            message: message,
            activeTextPartIndices: activeTextPartIndices,
            activeReasoningPartIndices: activeReasoningPartIndices,
            partialToolCalls: partialToolCalls
        )
    }

    fileprivate func withMutableState<R: Sendable>(
        _ body: @Sendable (inout Storage<Message>) throws -> R
    ) rethrows -> R {
        try body(&storage)
    }

    func messageSnapshot() -> Message {
        storage.message.clone()
    }

    func snapshot() -> StreamingUIMessageSnapshot<Message> {
        StreamingUIMessageSnapshot(
            message: storage.message.clone(),
            finishReason: storage.finishReason
        )
    }
}

public struct StreamingUIMessageSnapshot<Message: UIMessageConvertible>: Sendable {
    public let message: Message
    public let finishReason: FinishReason?
}

private struct Storage<Message: UIMessageConvertible>: Sendable {
    var message: Message
    var activeTextPartIndices: [String: Int]
    var activeReasoningPartIndices: [String: Int]
    var partialToolCalls: [String: PartialToolCall]
    var finishReason: FinishReason? = nil

    @discardableResult
    mutating func appendPart(_ part: UIMessagePart) -> Int {
        message.parts.append(part)
        return message.parts.count - 1
    }
}

public struct PartialToolCall: Sendable {
    public var text: String
    public var toolName: String
    public var dynamic: Bool
    public var title: String?

    public init(text: String, toolName: String, dynamic: Bool, title: String? = nil) {
        self.text = text
        self.toolName = toolName
        self.dynamic = dynamic
        self.title = title
    }
}

public func createStreamingUIMessageState<Message: UIMessageConvertible>(
    lastMessage: Message?,
    messageId: String
) -> StreamingUIMessageState<Message> {
    if let lastMessage, lastMessage.role == .assistant {
        return StreamingUIMessageState(message: lastMessage.clone())
    }

    let message = Message(id: messageId, role: .assistant, metadata: nil, parts: [])
    return StreamingUIMessageState(message: message)
}

public typealias UIMessageToolCallHandler = @Sendable (AnyUIMessageChunk) async -> Void

/// Processes a UI message stream and yields the original chunks while updating UI message state.
///
/// Port of `@ai-sdk/ai/src/ui/process-ui-message-stream.ts`.
public func processUIMessageStream<Message: UIMessageConvertible>(
    stream: AsyncThrowingStream<AnyUIMessageChunk, Error>,
    runUpdateMessageJob: @escaping @Sendable (_ job: @escaping StreamingUIMessageJob<Message>) async throws -> Void,
    onError: (@Sendable (Error) async throws -> Void)?,
    messageMetadataSchema: FlexibleSchema<JSONValue>? = nil,
    dataPartSchemas: [String: FlexibleSchema<JSONValue>]? = nil,
    onToolCall: UIMessageToolCallHandler? = nil,
    onData: (@Sendable (DataUIPart) -> Void)? = nil
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    processUIMessageStreamImpl(
        stream: stream,
        runUpdateMessageJob: runUpdateMessageJob,
        onError: onError,
        messageMetadataSchema: messageMetadataSchema,
        dataPartSchemas: dataPartSchemas,
        onToolCall: onToolCall,
        onData: onData,
        onChunk: nil
    )
}

// Internal-only hook used by stream wrappers that need to run side effects in the
// processing task (e.g. to preserve upstream backpressure semantics).
func processUIMessageStreamInternal<Message: UIMessageConvertible>(
    stream: AsyncThrowingStream<AnyUIMessageChunk, Error>,
    runUpdateMessageJob: @escaping @Sendable (_ job: @escaping StreamingUIMessageJob<Message>) async throws -> Void,
    onError: (@Sendable (Error) async throws -> Void)?,
    messageMetadataSchema: FlexibleSchema<JSONValue>? = nil,
    dataPartSchemas: [String: FlexibleSchema<JSONValue>]? = nil,
    onToolCall: UIMessageToolCallHandler? = nil,
    onData: (@Sendable (DataUIPart) -> Void)? = nil,
    onChunk: (@Sendable (AnyUIMessageChunk) async -> Void)?
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    processUIMessageStreamImpl(
        stream: stream,
        runUpdateMessageJob: runUpdateMessageJob,
        onError: onError,
        messageMetadataSchema: messageMetadataSchema,
        dataPartSchemas: dataPartSchemas,
        onToolCall: onToolCall,
        onData: onData,
        onChunk: onChunk
    )
}

private func processUIMessageStreamImpl<Message: UIMessageConvertible>(
    stream: AsyncThrowingStream<AnyUIMessageChunk, Error>,
    runUpdateMessageJob: @escaping @Sendable (_ job: @escaping StreamingUIMessageJob<Message>) async throws -> Void,
    onError: (@Sendable (Error) async throws -> Void)?,
    messageMetadataSchema: FlexibleSchema<JSONValue>?,
    dataPartSchemas: [String: FlexibleSchema<JSONValue>]?,
    onToolCall: UIMessageToolCallHandler?,
    onData: (@Sendable (DataUIPart) -> Void)?,
    onChunk: (@Sendable (AnyUIMessageChunk) async -> Void)?
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    return AsyncThrowingStream { continuation in
        let task = Task {
            do {
                for try await chunk in stream {
                    try await runUpdateMessageJob { context in
                        try await handleChunk(
                            chunk,
                            context: context,
                            onError: onError,
                            messageMetadataSchema: messageMetadataSchema,
                            dataPartSchemas: dataPartSchemas,
                            onToolCall: onToolCall,
                            onData: onData
                        )
                    }

                    if let onChunk {
                        await onChunk(chunk)
                    }

                    continuation.yield(chunk)
                }

                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        // Ensure upstream processing halts promptly when the consumer cancels.
        continuation.onTermination = { termination in
            if case .cancelled = termination {
                task.cancel()
            }
        }
    }
}

// MARK: - Chunk Handling

private func handleChunk<Message: UIMessageConvertible>(
    _ chunk: AnyUIMessageChunk,
    context: StreamingUIMessageJobContext<Message>,
    onError: (@Sendable (Error) async throws -> Void)?,
    messageMetadataSchema: FlexibleSchema<JSONValue>?,
    dataPartSchemas: [String: FlexibleSchema<JSONValue>]?,
    onToolCall: UIMessageToolCallHandler?,
    onData: (@Sendable (DataUIPart) -> Void)?
) async throws {
    switch chunk {
    case .textStart(let id, let providerMetadata):
        let part = TextUIPart(text: "", state: .streaming, providerMetadata: providerMetadata)
        _ = await context.state.withMutableState { state in
            let index = state.appendPart(UIMessagePart.text(part))
            state.activeTextPartIndices[id] = index
        }
        await context.write()

    case .textDelta(let id, let delta, let providerMetadata):
        guard let index = await context.state.withMutableState({ $0.activeTextPartIndices[id] }) else {
            throw UIMessageStreamError(
                chunkType: "text-delta",
                chunkId: id,
                message: "Received text-delta for missing text part with ID \"\(id)\". Ensure a \"text-start\" chunk is sent before any \"text-delta\" chunks."
            )
        }

        _ = await context.state.withMutableState { state in
            state.updateTextPart(at: index) { textPart in
                textPart.text += delta
                if let metadata = providerMetadata {
                    textPart.providerMetadata = metadata
                }
            }
        }
        await context.write()

    case .textEnd(let id, let providerMetadata):
        guard let index = await context.state.withMutableState({ $0.activeTextPartIndices.removeValue(forKey: id) }) else {
            throw UIMessageStreamError(
                chunkType: "text-end",
                chunkId: id,
                message: "Received text-end for missing text part with ID \"\(id)\". Ensure a \"text-start\" chunk is sent before any \"text-end\" chunks."
            )
        }

        _ = await context.state.withMutableState { state in
            state.updateTextPart(at: index) { textPart in
                textPart.state = TextUIPart.State.done
                if let metadata = providerMetadata {
                    textPart.providerMetadata = metadata
                }
            }
        }
        await context.write()

    case .reasoningStart(let id, let providerMetadata):
        let part = ReasoningUIPart(text: "", state: .streaming, providerMetadata: providerMetadata)
        _ = await context.state.withMutableState { state in
            let index = state.appendPart(UIMessagePart.reasoning(part))
            state.activeReasoningPartIndices[id] = index
        }
        await context.write()

    case .reasoningDelta(let id, let delta, let providerMetadata):
        guard let index = await context.state.withMutableState({ $0.activeReasoningPartIndices[id] }) else {
            throw UIMessageStreamError(
                chunkType: "reasoning-delta",
                chunkId: id,
                message: "Received reasoning-delta for missing reasoning part with ID \"\(id)\". Ensure a \"reasoning-start\" chunk is sent before any \"reasoning-delta\" chunks."
            )
        }

        _ = await context.state.withMutableState { state in
            state.updateReasoningPart(at: index) { reasoningPart in
                reasoningPart.text += delta
                if let metadata = providerMetadata {
                    reasoningPart.providerMetadata = metadata
                }
            }
        }
        await context.write()

    case .reasoningEnd(let id, let providerMetadata):
        guard let index = await context.state.withMutableState({ $0.activeReasoningPartIndices.removeValue(forKey: id) }) else {
            throw UIMessageStreamError(
                chunkType: "reasoning-end",
                chunkId: id,
                message: "Received reasoning-end for missing reasoning part with ID \"\(id)\". Ensure a \"reasoning-start\" chunk is sent before any \"reasoning-end\" chunks."
            )
        }

        _ = await context.state.withMutableState { state in
            state.updateReasoningPart(at: index) { reasoningPart in
                reasoningPart.state = ReasoningUIPart.State.done
                if let metadata = providerMetadata {
                    reasoningPart.providerMetadata = metadata
                }
            }
        }
        await context.write()

    case .file(let url, let mediaType, let providerMetadata):
        let part = FileUIPart(mediaType: mediaType, filename: nil, url: url, providerMetadata: providerMetadata)
        _ = await context.state.withMutableState { $0.appendPart(UIMessagePart.file(part)) }
        await context.write()

    case .sourceUrl(let sourceId, let url, let title, let providerMetadata):
        let part = SourceUrlUIPart(
            sourceId: sourceId,
            url: url,
            title: title,
            providerMetadata: providerMetadata
        )
        _ = await context.state.withMutableState { $0.appendPart(UIMessagePart.sourceURL(part)) }
        await context.write()

    case .sourceDocument(let sourceId, let mediaType, let title, let filename, let providerMetadata):
        let part = SourceDocumentUIPart(
            sourceId: sourceId,
            mediaType: mediaType,
            title: title,
            filename: filename,
            providerMetadata: providerMetadata
        )
        _ = await context.state.withMutableState { $0.appendPart(UIMessagePart.sourceDocument(part)) }
        await context.write()

    case .startStep:
        _ = await context.state.withMutableState { $0.appendPart(UIMessagePart.stepStart) }

    case .finishStep:
        _ = await context.state.withMutableState { state in
            state.activeTextPartIndices.removeAll()
            state.activeReasoningPartIndices.removeAll()
        }

    case .toolInputStart(let toolCallId, let toolName, let providerExecuted, let providerMetadata, let dynamic, let title):
        let isDynamic = dynamic ?? false
        _ = await context.state.withMutableState { state in
            state.partialToolCalls[toolCallId] = PartialToolCall(
                text: "",
                toolName: toolName,
                dynamic: isDynamic,
                title: title
            )

            if isDynamic {
                state.upsertDynamicToolPart(
                    toolCallId: toolCallId,
                    toolName: toolName,
                    state: .inputStreaming,
                    input: nil,
                    output: nil,
                    errorText: nil,
                    providerExecuted: providerExecuted,
                    providerMetadata: providerMetadata,
                    preliminary: nil,
                    approval: nil,
                    title: title
                )
            } else {
                state.upsertToolPart(
                    toolCallId: toolCallId,
                    toolName: toolName,
                    state: .inputStreaming,
                    input: nil,
                    output: nil,
                    rawInput: nil,
                    errorText: nil,
                    providerExecuted: providerExecuted,
                    providerMetadata: providerMetadata,
                    preliminary: nil,
                    approval: nil,
                    title: title
                )
            }
        }

        await context.write()

    case .toolInputDelta(let toolCallId, let inputTextDelta):
        guard let partial = await context.state.withMutableState({ state -> PartialToolCall? in
            guard var partial = state.partialToolCalls[toolCallId] else {
                return nil
            }
            partial.text += inputTextDelta
            state.partialToolCalls[toolCallId] = partial
            return partial
        }) else {
            throw UIMessageStreamError(
                chunkType: "tool-input-delta",
                chunkId: toolCallId,
                message: "Received tool-input-delta for missing tool call with ID \"\(toolCallId)\". Ensure a \"tool-input-start\" chunk is sent before any \"tool-input-delta\" chunks."
            )
        }

        let parsed = await parsePartialJson(partial.text)
        let partialInput = parsed.value

        _ = await context.state.withMutableState { state in
            if partial.dynamic {
                state.upsertDynamicToolPart(
                    toolCallId: toolCallId,
                    toolName: partial.toolName,
                    state: .inputStreaming,
                    input: partialInput,
                    output: nil,
                    errorText: nil,
                    providerExecuted: nil,
                    providerMetadata: nil,
                    preliminary: nil,
                    approval: nil,
                    title: partial.title
                )
            } else {
                state.upsertToolPart(
                    toolCallId: toolCallId,
                    toolName: partial.toolName,
                    state: .inputStreaming,
                    input: partialInput,
                    output: nil,
                    rawInput: nil,
                    errorText: nil,
                    providerExecuted: nil,
                    providerMetadata: nil,
                    preliminary: nil,
                    approval: nil,
                    title: partial.title
                )
            }
        }

        await context.write()

    case .toolInputAvailable(
        let toolCallId,
        let toolName,
        let input,
        let providerExecuted,
        let providerMetadata,
        let dynamic,
        let title
    ):
        let isDynamic = dynamic ?? false
        _ = await context.state.withMutableState { state in
            if isDynamic {
                state.upsertDynamicToolPart(
                    toolCallId: toolCallId,
                    toolName: toolName,
                    state: .inputAvailable,
                    input: input,
                    output: nil,
                    errorText: nil,
                    providerExecuted: providerExecuted,
                    providerMetadata: providerMetadata,
                    preliminary: nil,
                    approval: nil,
                    title: title
                )
            } else {
                state.upsertToolPart(
                    toolCallId: toolCallId,
                    toolName: toolName,
                    state: .inputAvailable,
                    input: input,
                    output: nil,
                    rawInput: nil,
                    errorText: nil,
                    providerExecuted: providerExecuted,
                    providerMetadata: providerMetadata,
                    preliminary: nil,
                    approval: nil,
                    title: title
                )
            }
        }

        await context.write()

        if let onToolCall, providerExecuted != true {
            await onToolCall(chunk)
        }

    case .toolInputError(
        let toolCallId,
        let toolName,
        let input,
        let providerExecuted,
        let providerMetadata,
        let dynamic,
        let errorText,
        _
    ):
        let invocationKind = await context.state.withMutableState { $0.toolInvocationKind(for: toolCallId) }
        let isDynamic = invocationKind == .dynamic ? true : invocationKind == .tool ? false : (dynamic ?? false)
        _ = await context.state.withMutableState { state in
            if isDynamic {
                state.upsertDynamicToolPart(
                    toolCallId: toolCallId,
                    toolName: toolName,
                    state: .outputError,
                    input: input,
                    output: nil,
                    errorText: errorText,
                    providerExecuted: providerExecuted,
                    providerMetadata: providerMetadata,
                    preliminary: nil,
                    approval: nil,
                    title: nil
                )
            } else {
                state.upsertToolPart(
                    toolCallId: toolCallId,
                    toolName: toolName,
                    state: .outputError,
                    input: nil,
                    output: nil,
                    rawInput: input,
                    errorText: errorText,
                    providerExecuted: providerExecuted,
                    providerMetadata: providerMetadata,
                    preliminary: nil,
                    approval: nil,
                    title: nil
                )
            }
        }

        await context.write()

    case .toolApprovalRequest(let approvalId, let toolCallId):
        guard let invocationKind = await context.state.withMutableState({ $0.toolInvocationKind(for: toolCallId) }) else {
            throw UIMessageStreamError(
                chunkType: "tool-invocation",
                chunkId: toolCallId,
                message: "No tool invocation found for tool call ID \"\(toolCallId)\"."
            )
        }

        _ = await context.state.withMutableState { state in
            switch invocationKind {
            case .tool:
                state.updateToolPart(with: toolCallId) { part in
                    part.state = .approvalRequested
                    part.approval = UIToolApproval(id: approvalId)
                }
            case .dynamic:
                state.updateDynamicToolPart(with: toolCallId) { part in
                    part.state = .approvalRequested
                    part.approval = UIToolApproval(id: approvalId)
                }
            }
        }
        await context.write()

    case .toolOutputAvailable(
        let toolCallId,
        let output,
        let providerExecuted,
        let providerMetadata,
        _,
        let preliminary
    ):
        guard let invocationKind = await context.state.withMutableState({ $0.toolInvocationKind(for: toolCallId) }) else {
            throw UIMessageStreamError(
                chunkType: "tool-invocation",
                chunkId: toolCallId,
                message: "No tool invocation found for tool call ID \"\(toolCallId)\"."
            )
        }

        try await context.state.withMutableState { state in
            switch invocationKind {
            case .dynamic:
                guard let toolPart = state.dynamicToolPart(for: toolCallId) else {
                    throw UIMessageStreamError(
                        chunkType: "tool-invocation",
                        chunkId: toolCallId,
                        message: "No tool invocation found for tool call ID \"\(toolCallId)\"."
                    )
                }
                state.upsertDynamicToolPart(
                    toolCallId: toolCallId,
                    toolName: toolPart.toolName,
                    state: .outputAvailable,
                    input: toolPart.input,
                    output: output,
                    errorText: nil,
                    providerExecuted: providerExecuted,
                    providerMetadata: providerMetadata,
                    preliminary: preliminary,
                    approval: toolPart.approval,
                    title: toolPart.title
                )
            case .tool:
                guard let toolPart = state.toolPart(for: toolCallId) else {
                    throw UIMessageStreamError(
                        chunkType: "tool-invocation",
                        chunkId: toolCallId,
                        message: "No tool invocation found for tool call ID \"\(toolCallId)\"."
                    )
                }
                state.upsertToolPart(
                    toolCallId: toolCallId,
                    toolName: toolPart.toolName,
                    state: .outputAvailable,
                    input: toolPart.input,
                    output: output,
                    rawInput: nil,
                    errorText: nil,
                    providerExecuted: providerExecuted ?? toolPart.providerExecuted,
                    providerMetadata: providerMetadata,
                    preliminary: preliminary,
                    approval: toolPart.approval,
                    title: toolPart.title
                )
            }
        }

        await context.write()

    case .toolOutputError(let toolCallId, let errorText, let providerExecuted, let providerMetadata, _):
        guard let invocationKind = await context.state.withMutableState({ $0.toolInvocationKind(for: toolCallId) }) else {
            throw UIMessageStreamError(
                chunkType: "tool-invocation",
                chunkId: toolCallId,
                message: "No tool invocation found for tool call ID \"\(toolCallId)\"."
            )
        }

        try await context.state.withMutableState { state in
            switch invocationKind {
            case .dynamic:
                guard let toolPart = state.dynamicToolPart(for: toolCallId) else {
                    throw UIMessageStreamError(
                        chunkType: "tool-invocation",
                        chunkId: toolCallId,
                        message: "No tool invocation found for tool call ID \"\(toolCallId)\"."
                    )
                }
                state.upsertDynamicToolPart(
                    toolCallId: toolCallId,
                    toolName: toolPart.toolName,
                    state: .outputError,
                    input: toolPart.input,
                    output: nil,
                    errorText: errorText,
                    providerExecuted: providerExecuted,
                    providerMetadata: providerMetadata,
                    preliminary: toolPart.preliminary,
                    approval: toolPart.approval,
                    title: toolPart.title
                )
            case .tool:
                guard let toolPart = state.toolPart(for: toolCallId) else {
                    throw UIMessageStreamError(
                        chunkType: "tool-invocation",
                        chunkId: toolCallId,
                        message: "No tool invocation found for tool call ID \"\(toolCallId)\"."
                    )
                }
                state.upsertToolPart(
                    toolCallId: toolCallId,
                    toolName: toolPart.toolName,
                    state: .outputError,
                    input: toolPart.input,
                    output: nil,
                    rawInput: toolPart.rawInput,
                    errorText: errorText,
                    providerExecuted: providerExecuted ?? toolPart.providerExecuted,
                    providerMetadata: providerMetadata,
                    preliminary: toolPart.preliminary,
                    approval: toolPart.approval,
                    title: toolPart.title
                )
            }
        }

        await context.write()

    case .toolOutputDenied(let toolCallId):
        guard let invocationKind = await context.state.withMutableState({ $0.toolInvocationKind(for: toolCallId) }) else {
            throw UIMessageStreamError(
                chunkType: "tool-invocation",
                chunkId: toolCallId,
                message: "No tool invocation found for tool call ID \"\(toolCallId)\"."
            )
        }

        _ = await context.state.withMutableState { state in
            switch invocationKind {
            case .tool:
                state.updateToolPart(with: toolCallId) { part in
                    part.state = .outputDenied
                }
            case .dynamic:
                state.updateDynamicToolPart(with: toolCallId) { part in
                    part.state = .outputDenied
                }
            }
        }
        await context.write()

    case .start(let messageId, let messageMetadata):
        if let metadata = messageMetadata {
            let existing = await context.state.withMutableState { $0.message.metadata }
            if let merged = try await mergeMetadata(
                existing: existing,
                incoming: metadata,
                schema: messageMetadataSchema
            ) {
                _ = await context.state.withMutableState { $0.message.metadata = merged }
            }
        }

        if let messageId {
            _ = await context.state.withMutableState { $0.message.id = messageId }
        }

        if messageId != nil || messageMetadata != nil {
            await context.write()
        }

    case .finish(let finishReason, let messageMetadata):
        if let finishReason {
            _ = await context.state.withMutableState { $0.finishReason = finishReason }
        }
        if let metadata = messageMetadata {
            let existing = await context.state.withMutableState { $0.message.metadata }
            if let merged = try await mergeMetadata(
                existing: existing,
                incoming: metadata,
                schema: messageMetadataSchema
            ) {
                _ = await context.state.withMutableState { $0.message.metadata = merged }
                await context.write()
            }
        }

    case .messageMetadata(let metadata):
        let existing = await context.state.withMutableState { $0.message.metadata }
        if let merged = try await mergeMetadata(
            existing: existing,
            incoming: metadata,
            schema: messageMetadataSchema
        ) {
            _ = await context.state.withMutableState { $0.message.metadata = merged }
            await context.write()
        }

    case .error(let errorText):
        if let onError {
            try await onError(UIMessageChunkError(message: errorText))
        }

    case .data(let dataChunk):
        if let schema = dataPartSchemas?[dataChunk.typeIdentifier] {
            _ = try await validateTypes(
                ValidateTypesOptions(
                    value: jsonValueToAny(dataChunk.data),
                    schema: schema
                )
            )
        }

        let dataUIPart = DataUIPart(
            typeIdentifier: dataChunk.typeIdentifier,
            id: dataChunk.id,
            data: dataChunk.data
        )

        if dataChunk.transient == true {
            onData?(dataUIPart)
            break
        }

        _ = await context.state.withMutableState { state in
            if let index = state.indexOfDataPart(
                typeIdentifier: dataChunk.typeIdentifier,
                id: dataChunk.id
            ) {
                state.updateDataPart(at: index) { part in
                    part.data = dataChunk.data
                }
            } else {
                state.appendPart(UIMessagePart.data(dataUIPart))
            }
        }

        onData?(dataUIPart)
        await context.write()

    case .abort:
        // handled by caller (needed only for onFinish metadata)
        break
    }
}

// MARK: - Helpers

private func mergeMetadata(
    existing: JSONValue?,
    incoming: JSONValue,
    schema: FlexibleSchema<JSONValue>?
) async throws -> JSONValue? {
    let merged: JSONValue

    switch (existing, incoming) {
    case (.object(let base), .object(let overrides)):
        let mergedDictionary = mergeJSONObjects(base, overrides)
        merged = .object(mergedDictionary)
    case (.some, _):
        merged = incoming
    case (.none, _):
        merged = incoming
    }

    if let schema {
        _ = try await validateTypes(
            ValidateTypesOptions(
                value: jsonValueToAny(merged),
                schema: schema
            )
        )
    }

    return merged
}

private func mergeJSONObjects(
    _ base: [String: JSONValue],
    _ overrides: [String: JSONValue]
) -> [String: JSONValue] {
    var result = base

    for (key, value) in overrides {
        if case .object(let baseObject) = result[key],
           case .object(let overrideObject) = value {
            result[key] = .object(mergeJSONObjects(baseObject, overrideObject))
        } else {
            result[key] = value
        }
    }

    return result
}

private func jsonValueToAny(_ value: JSONValue) -> Any {
    switch value {
    case .string(let string):
        return string
    case .number(let number):
        return number
    case .bool(let bool):
        return bool
    case .null:
        return NSNull()
    case .array(let array):
        return array.map { jsonValueToAny($0) }
    case .object(let dictionary):
        var result: [String: Any] = [:]
        for (key, entry) in dictionary {
            result[key] = jsonValueToAny(entry)
        }
        return result
    }
}

private struct UIMessageChunkError: Error, LocalizedError, CustomStringConvertible {
    let message: String

    init(message: String) {
        self.message = message
    }

    var description: String { message }
    var errorDescription: String? { message }
}

private extension Storage {
    enum ToolInvocationKind {
        case tool
        case dynamic
    }

    mutating func updateTextPart(at index: Int, _ mutate: (inout TextUIPart) -> Void) {
        guard case .text(var part) = message.parts[index] else {
            return
        }
        mutate(&part)
        message.parts[index] = .text(part)
    }

    mutating func updateReasoningPart(at index: Int, _ mutate: (inout ReasoningUIPart) -> Void) {
        guard case .reasoning(var part) = message.parts[index] else {
            return
        }
        mutate(&part)
        message.parts[index] = .reasoning(part)
    }

    mutating func updateToolPart(with toolCallId: String, mutate: (inout UIToolUIPart) -> Void) {
        guard let index = toolPartIndex(for: toolCallId),
              case .tool(var part) = message.parts[index] else {
            return
        }
        mutate(&part)
        message.parts[index] = .tool(part)
    }

    mutating func updateDynamicToolPart(with toolCallId: String, mutate: (inout UIDynamicToolUIPart) -> Void) {
        guard let index = dynamicToolPartIndex(for: toolCallId),
              case .dynamicTool(var part) = message.parts[index] else {
            return
        }
        mutate(&part)
        message.parts[index] = .dynamicTool(part)
    }

    mutating func updateDataPart(at index: Int, mutate: (inout DataUIPart) -> Void) {
        guard case .data(var part) = message.parts[index] else {
            return
        }
        mutate(&part)
        message.parts[index] = .data(part)
    }

    func toolPartIndex(for toolCallId: String) -> Int? {
        message.parts.firstIndex {
            if case .tool(let part) = $0 {
                return part.toolCallId == toolCallId
            } else {
                return false
            }
        }
    }

    func dynamicToolPartIndex(for toolCallId: String) -> Int? {
        message.parts.firstIndex {
            if case .dynamicTool(let part) = $0 {
                return part.toolCallId == toolCallId
            } else {
                return false
            }
        }
    }

    func toolPart(for toolCallId: String) -> UIToolUIPart? {
        guard let index = toolPartIndex(for: toolCallId),
              case .tool(let part) = message.parts[index] else {
            return nil
        }
        return part
    }

    func dynamicToolPart(for toolCallId: String) -> UIDynamicToolUIPart? {
        guard let index = dynamicToolPartIndex(for: toolCallId),
              case .dynamicTool(let part) = message.parts[index] else {
            return nil
        }
        return part
    }

    func toolInvocationKind(for toolCallId: String) -> ToolInvocationKind? {
        for part in message.parts {
            switch part {
            case .tool(let toolPart) where toolPart.toolCallId == toolCallId:
                return .tool
            case .dynamicTool(let dynamicToolPart) where dynamicToolPart.toolCallId == toolCallId:
                return .dynamic
            default:
                continue
            }
        }

        return nil
    }

    mutating func upsertToolPart(
        toolCallId: String,
        toolName: String,
        state: UIToolInvocationState,
        input: JSONValue?,
        output: JSONValue?,
        rawInput: JSONValue?,
        errorText: String?,
        providerExecuted: Bool?,
        providerMetadata: ProviderMetadata?,
        preliminary: Bool?,
        approval: UIToolApproval?,
        title: String?
    ) {
        if let index = toolPartIndex(for: toolCallId),
           case .tool(var part) = message.parts[index] {
            part.state = state
            part.input = input
            part.output = output
            part.rawInput = rawInput
            part.errorText = errorText
            if let providerExecuted { part.providerExecuted = providerExecuted }
            if let providerMetadata {
                if state == .outputAvailable || state == .outputError {
                    part.resultProviderMetadata = providerMetadata
                } else {
                    part.callProviderMetadata = providerMetadata
                }
            }
            part.preliminary = preliminary
            if let approval { part.approval = approval }
            if let title { part.title = title }
            message.parts[index] = .tool(part)
        } else {
            let part = UIToolUIPart(
                toolName: toolName,
                toolCallId: toolCallId,
                state: state,
                input: input,
                output: output,
                rawInput: rawInput,
                errorText: errorText,
                providerExecuted: providerExecuted,
                callProviderMetadata: state == .outputAvailable || state == .outputError ? nil : providerMetadata,
                resultProviderMetadata: state == .outputAvailable || state == .outputError ? providerMetadata : nil,
                preliminary: preliminary,
                approval: approval,
                title: title
            )
            appendPart(.tool(part))
        }
    }

    mutating func upsertDynamicToolPart(
        toolCallId: String,
        toolName: String,
        state: UIDynamicToolInvocationState,
        input: JSONValue?,
        output: JSONValue?,
        errorText: String?,
        providerExecuted: Bool?,
        providerMetadata: ProviderMetadata?,
        preliminary: Bool?,
        approval: UIToolApproval?,
        title: String?
    ) {
        if let index = dynamicToolPartIndex(for: toolCallId),
           case .dynamicTool(var part) = message.parts[index] {
            part.state = state
            part.input = input
            part.output = output
            part.errorText = errorText
            if let providerExecuted { part.providerExecuted = providerExecuted }
            if let providerMetadata {
                if state == .outputAvailable || state == .outputError {
                    part.resultProviderMetadata = providerMetadata
                } else {
                    part.callProviderMetadata = providerMetadata
                }
            }
            part.preliminary = preliminary
            if let approval { part.approval = approval }
            if let title { part.title = title }
            part.toolName = toolName
            message.parts[index] = .dynamicTool(part)
        } else {
            let part = UIDynamicToolUIPart(
                toolName: toolName,
                toolCallId: toolCallId,
                state: state,
                input: input,
                output: output,
                errorText: errorText,
                providerExecuted: providerExecuted,
                callProviderMetadata: state == .outputAvailable || state == .outputError ? nil : providerMetadata,
                resultProviderMetadata: state == .outputAvailable || state == .outputError ? providerMetadata : nil,
                preliminary: preliminary,
                approval: approval,
                title: title
            )
            appendPart(.dynamicTool(part))
        }
    }

    func indexOfDataPart(typeIdentifier: String, id: String?) -> Int? {
        message.parts.firstIndex {
            switch $0 {
            case .data(let part):
                if part.typeIdentifier != typeIdentifier {
                    return false
                }
                if let id {
                    return part.id == id
                } else {
                    return part.id == nil
                }
            default:
                return false
            }
        }
    }
}
