// MemoryOption.swift
// Swarm V3 API
//
// Factory enum for dot-syntax memory construction.

import Foundation

// MARK: - MemoryOption

/// Factory enum for memory selection. Replaces manual memory construction.
///
/// For memory types requiring injected dependencies (VectorMemory, SummaryMemory,
/// PersistentMemory), use `.custom(yourMemoryInstance)`.
public enum MemoryOption: Sendable {
    /// No memory (stateless agent).
    case none

    /// FIFO conversation memory with a message count limit.
    case conversation(limit: Int = 100)

    /// Token-aware sliding window memory.
    case slidingWindow(maxTokens: Int = 4000)

    /// Pre-configured memory instance.
    case custom(any Memory)

    /// Constructs the memory instance. Returns `nil` for `.none`.
    public func makeMemory() -> (any Memory)? {
        switch self {
        case .none:
            return nil
        case .conversation(let limit):
            return ConversationMemory(maxMessages: limit)
        case .slidingWindow(let maxTokens):
            return SlidingWindowMemory(maxTokens: maxTokens)
        case .custom(let memory):
            return memory
        }
    }
}
