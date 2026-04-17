// AgentMemory.swift
// Swarm Framework
//
// Core protocol defining memory storage and retrieval for agents.

import Foundation

// MARK: - Memory

/// Actor-isolated memory backing for agents — storage + context retrieval.
///
/// Six built-in implementations cover common patterns:
///
/// | Type | Best for |
/// |---|---|
/// | ``ConversationMemory`` | Simple chat history; rolling buffer |
/// | ``SlidingWindowMemory`` | Token-bounded sliding window |
/// | ``SummaryMemory`` | Long conversations; summarizes old messages |
/// | ``HybridMemory`` | Short-term detail + summarized long-term |
/// | ``PersistentMemory`` | Production apps; pluggable storage backend |
/// | ``VectorMemory`` | RAG / semantic search over history |
///
/// Factory methods return each built-in type through Swift's generic constraint
/// system — write `.conversation(…)` and the compiler resolves it to
/// ``ConversationMemory``:
///
/// ```swift
/// let memory: any Memory = .conversation(maxMessages: 50)
/// ```
///
/// Pass the result to an ``Agent`` via its initializer's `memory:` parameter.
/// See <doc:MemoryAndSessions> for patterns (which type to pick, custom
/// conformance, persistence, RAG).
///
/// Conforming types must be actors — the `Actor` requirement is part of the
/// protocol. `Sendable` inherits so `any Memory` values flow safely across
/// concurrency boundaries.
///
/// ## See Also
/// - ``ConversationMemory``
/// - ``VectorMemory``
/// - ``SlidingWindowMemory``
/// - ``SummaryMemory``
/// - ``HybridMemory``
/// - ``PersistentMemory``
/// - ``MemoryMessage``
public protocol Memory: Actor, Sendable {
    /// Current message count. Should be cheap — avoid fetching all messages.
    var count: Int { get async }

    /// Whether memory contains zero messages. Should be cheap.
    var isEmpty: Bool { get async }

    /// Appends a message. Implementations may apply their own eviction policy
    /// (e.g. rolling buffer, token cap, summarization trigger).
    func add(_ message: MemoryMessage) async

    /// Returns context relevant to `query`, formatted for a prompt and bounded
    /// by `tokenLimit`. Semantics vary by implementation — recent-first,
    /// semantic similarity, or summarized.
    /// - SeeAlso: ``MemoryMessage/formatContext(_:tokenLimit:tokenEstimator:)``
    func context(for query: String, tokenLimit: Int) async -> String

    /// All stored messages in chronological order. Can be expensive on large memories.
    func allMessages() async -> [MemoryMessage]

    /// Removes all messages. After this, ``isEmpty`` is `true` and ``count`` is `0`.
    func clear() async
}

// MARK: - MemoryMessage Context Formatting

public extension MemoryMessage {
    /// Joins messages into a context string, most-recent-first, stopping when
    /// adding the next message would exceed `tokenLimit`. Messages are
    /// separated by double newlines.
    static func formatContext(
        _ messages: [MemoryMessage],
        tokenLimit: Int,
        tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared
    ) -> String {
        var result: [String] = []
        var currentTokens = 0

        // Process messages in reverse (most recent first) then reverse result
        for message in messages.reversed() {
            let formatted = message.formattedContent
            let messageTokens = tokenEstimator.estimateTokens(for: formatted)

            if currentTokens + messageTokens <= tokenLimit {
                result.append(formatted)
                currentTokens += messageTokens
            } else {
                break
            }
        }

        return result.reversed().joined(separator: "\n\n")
    }

    /// Like ``formatContext(_:tokenLimit:tokenEstimator:)`` but with a caller-
    /// supplied separator. The separator's own token cost is counted against
    /// `tokenLimit` for every message after the first.
    static func formatContext(
        _ messages: [MemoryMessage],
        tokenLimit: Int,
        separator: String,
        tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared
    ) -> String {
        var result: [String] = []
        var currentTokens = 0
        let separatorTokens = tokenEstimator.estimateTokens(for: separator)

        for message in messages.reversed() {
            let formatted = message.formattedContent
            let messageTokens = tokenEstimator.estimateTokens(for: formatted)
            let totalNeeded = messageTokens + (result.isEmpty ? 0 : separatorTokens)

            if currentTokens + totalNeeded <= tokenLimit {
                result.append(formatted)
                currentTokens += totalNeeded
            } else {
                break
            }
        }

        return result.reversed().joined(separator: separator)
    }
}

// MARK: - Memory Factory Extensions

extension Memory where Self == ConversationMemory {
    /// Rolling buffer of the most recent messages. Oldest messages are evicted
    /// when `maxMessages` is exceeded. Simplest option; no embedding or
    /// summarization.
    /// - Parameter maxMessages: cap. Default: `100`
    public static func conversation(maxMessages: Int = 100) -> ConversationMemory {
        ConversationMemory(maxMessages: maxMessages)
    }
}

extension Memory where Self == SlidingWindowMemory {
    /// Token-bounded sliding window. Evicts oldest messages to stay within
    /// `maxTokens`. More precise than ``conversation(maxMessages:)`` when the
    /// model has a strict context budget.
    /// - Parameter maxTokens: cap. Default: `4000`
    public static func slidingWindow(maxTokens: Int = 4000) -> SlidingWindowMemory {
        SlidingWindowMemory(maxTokens: maxTokens)
    }
}

extension Memory where Self == PersistentMemory {
    /// Persists messages across app restarts via a pluggable
    /// ``PersistentMemoryBackend`` (in-memory for tests, SwiftData for
    /// production via ``SwiftDataBackend``).
    /// - Parameter maxMessages: retention cap. `0` means unlimited. Default: `0`
    public static func persistent(
        backend: any PersistentMemoryBackend = InMemoryBackend(),
        conversationId: String = UUID().uuidString,
        maxMessages: Int = 0
    ) -> PersistentMemory {
        PersistentMemory(
            backend: backend,
            conversationId: conversationId,
            maxMessages: maxMessages
        )
    }
}

extension Memory where Self == HybridMemory {
    /// Keeps recent messages intact while summarizing older ones. Balances
    /// detail and breadth for long-running conversations.
    public static func hybrid(
        configuration: HybridMemory.Configuration = .default,
        summarizer: any Summarizer = TruncatingSummarizer.shared
    ) -> HybridMemory {
        HybridMemory(configuration: configuration, summarizer: summarizer)
    }
}

extension Memory where Self == SummaryMemory {
    /// Aggressive summarization: keeps `recentMessageCount` messages verbatim,
    /// continuously summarizes everything older. Use when the token budget is
    /// tight and approximate older context is acceptable.
    public static func summary(
        configuration: SummaryMemory.Configuration = .default,
        summarizer: any Summarizer = TruncatingSummarizer.shared
    ) -> SummaryMemory {
        SummaryMemory(configuration: configuration, summarizer: summarizer)
    }
}

extension Memory where Self == VectorMemory {
    /// Embedding-backed memory for RAG and semantic recall. The
    /// ``EmbeddingProvider`` turns text into vectors; retrieval returns the
    /// `maxResults` most similar messages above `similarityThreshold`.
    /// - Parameters:
    ///   - similarityThreshold: cosine-similarity cutoff in `0 ... 1`. Default: `0.7`
    ///   - maxResults: cap on returned messages. Default: `10`
    public static func vector(
        embeddingProvider: any EmbeddingProvider,
        similarityThreshold: Float = 0.7,
        maxResults: Int = 10
    ) -> VectorMemory {
        VectorMemory(
            embeddingProvider: embeddingProvider,
            similarityThreshold: similarityThreshold,
            maxResults: maxResults
        )
    }
}
