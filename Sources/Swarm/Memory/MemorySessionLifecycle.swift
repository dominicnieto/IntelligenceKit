import Foundation

/// Optional lifecycle observer for memory implementations that need session scoping.
///
/// This is primarily used by persistent, single-file memories (e.g. Wax) to tag
/// ingested content per agent run without exposing storage-specific APIs to agents.
public protocol MemorySessionLifecycle: Memory {
    /// Called at the beginning of an agent `run` / `stream`.
    func beginMemorySession() async

    /// Called at the end of an agent `run` / `stream` (success or failure).
    func endMemorySession() async
}

/// Optional hook for memories that want custom handling when session history is replayed
/// into a fresh memory instance.
public protocol MemorySessionReplayAware: Memory {
    /// Imports a batch of session history messages using memory-specific logic.
    func importSessionHistory(_ messages: [MemoryMessage]) async
}
