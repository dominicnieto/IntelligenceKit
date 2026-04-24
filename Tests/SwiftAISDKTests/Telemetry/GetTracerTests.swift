import Testing
@testable import SwiftAISDK

@Suite("GetTracer")
struct GetTracerTests {
    @Test("returns noop tracer when telemetry is disabled")
    func returnsNoopWhenDisabled() {
        let tracer = getTracer(isEnabled: false, tracer: nil)

        #expect(tracer is NoopTracer)
    }

    @Test("returns noop tracer when telemetry is enabled without explicit tracer")
    func returnsNoopWhenEnabledWithoutTracer() {
        let tracer = getTracer(isEnabled: true, tracer: nil)

        #expect(tracer is NoopTracer)
    }

    @Test("returns explicit tracer when telemetry is enabled")
    func returnsExplicitTracerWhenProvided() {
        let expected = TestTracer()
        let tracer = getTracer(isEnabled: true, tracer: expected)

        #expect(tracer is TestTracer)
        #expect(ObjectIdentifier(tracer as AnyObject) == ObjectIdentifier(expected))
    }
}

private final class TestTracer: Tracer, @unchecked Sendable {
    func startSpan(name: String, options: SpanOptions?) -> any Span {
        noopTracer.startSpan(name: name, options: options)
    }

    func startActiveSpan<T>(
        _ name: String,
        options: SpanOptions?,
        _ fn: @Sendable (any Span) async throws -> T
    ) async rethrows -> T {
        try await noopTracer.startActiveSpan(name, options: options, fn)
    }
}
