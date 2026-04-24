import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Get a tracer for telemetry.

 Port of `@ai-sdk/ai/src/telemetry/get-tracer.ts`.

 Returns appropriate tracer based on telemetry configuration:
 - If disabled: returns noopTracer
 - If custom tracer provided: returns custom tracer
 - Otherwise: returns noopTracer
 */

/// Get tracer for telemetry
///
/// - Parameters:
///   - isEnabled: Whether telemetry is enabled (default: false)
///   - tracer: Custom tracer to use (optional)
/// - Returns: Appropriate tracer based on configuration
public func getTracer(
    isEnabled: Bool = false,
    tracer: (any Tracer)? = nil
) -> any Tracer {
    if !isEnabled {
        return noopTracer
    }

    return tracer ?? noopTracer
}
