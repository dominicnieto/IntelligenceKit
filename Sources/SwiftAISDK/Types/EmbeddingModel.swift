import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Embedding model types and type aliases.

 Port of `@ai-sdk/ai/src/types/embedding-model.ts`.

 Provides type aliases for working with embedding models in the AI SDK Core functions.
 */

/**
 Embedding model that is used by the AI SDK Core functions.

 Can be one of:
 - An `EmbeddingModelV3` protocol implementation
 - An `EmbeddingModelV2` protocol implementation

 Swift fork equivalent: `EmbeddingModelV3<VALUE> | EmbeddingModelV2<VALUE>`
 */
public enum EmbeddingModel<VALUE: Sendable>: Sendable {
    /// Embedding model V3 implementation
    case v3(any EmbeddingModelV3<VALUE>)

    /// Embedding model V2 implementation
    case v2(any EmbeddingModelV2<VALUE>)
}

/**
 Embedding vector.

 Type alias for `EmbeddingModelV3Embedding` from the Provider package.
 */
public typealias Embedding = EmbeddingModelV3Embedding
