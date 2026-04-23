import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("rerank")
struct RerankTests {
    @Test("returns empty result without calling the model")
    func returnsEmptyResultWithoutCallingModel() async throws {
        actor CallCounter {
            var count = 0
            func increment() { count += 1 }
            func current() -> Int { count }
        }

        let counter = CallCounter()
        let model = TestRerankingModel(provider: "test", modelId: "test-model") { _ in
            await counter.increment()
            return RerankingModelV3DoRerankResult(ranking: [])
        }

        let result = try await rerank(
            model: model,
            documents: [String](),
            query: "q"
        )

        #expect(result.originalDocuments.isEmpty)
        #expect(result.ranking.isEmpty)
        #expect(result.rerankedDocuments.isEmpty)
        #expect(result.response.modelId == "test-model")
        #expect(await counter.current() == 0)
    }

    @Test("maps ranking entries and response metadata")
    func mapsRankingAndResponse() async throws {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let model = TestRerankingModel(provider: "test", modelId: "test-model") { options in
            guard case .text(let values) = options.documents else {
                Issue.record("Expected text documents")
                return RerankingModelV3DoRerankResult(ranking: [])
            }

            #expect(values == ["a", "b", "c"])
            #expect(options.query == "query")
            #expect(options.topN == 2)
            #expect(options.headers?["user-agent"]?.contains("ai/\(VERSION)") == true)

            return RerankingModelV3DoRerankResult(
                ranking: [
                    RerankingModelV3Ranking(index: 2, relevanceScore: 0.9),
                    RerankingModelV3Ranking(index: 0, relevanceScore: 0.5),
                ],
                providerMetadata: ["test": ["note": .string("ok")]],
                response: RerankingModelV3ResponseInfo(
                    id: "resp-id",
                    timestamp: fixedDate,
                    modelId: "override-model",
                    headers: ["x-test": "1"],
                    body: nil
                )
            )
        }

        let result = try await rerank(
            model: model,
            documents: ["a", "b", "c"],
            query: "query",
            topN: 2
        )

        #expect(result.rerankedDocuments == ["c", "a"])
        #expect(result.ranking.count == 2)
        #expect(result.ranking[0].originalIndex == 2)
        #expect(result.ranking[0].score == 0.9)
        #expect(result.ranking[0].document == "c")
        #expect(result.providerMetadata?["test"]?["note"] == .string("ok"))
        #expect(result.response.id == "resp-id")
        #expect(result.response.timestamp == fixedDate)
        #expect(result.response.modelId == "override-model")
        #expect(result.response.headers?["x-test"] == "1")
    }

    @Test("logs reranking warnings")
    func logsWarnings() async throws {
        setWarningsLoggingDisabledForTests(true)
        defer { setWarningsLoggingDisabledForTests(false) }

        final class WarningsCapture: @unchecked Sendable {
            private let lock = NSLock()
            private var warningsBatches: [[Warning]] = []

            func append(_ warnings: [Warning]) {
                lock.lock()
                warningsBatches.append(warnings)
                lock.unlock()
            }

            func contains(_ warning: Warning) -> Bool {
                lock.lock()
                defer { lock.unlock() }
                return warningsBatches.contains(where: { $0.contains(warning) })
            }
        }

        let capture = WarningsCapture()
        logWarningsObserver = { warnings in
            if !warnings.isEmpty {
                capture.append(warnings)
            }
        }
        defer { logWarningsObserver = nil }

        let model = TestRerankingModel(provider: "test", modelId: "test-model") { _ in
            RerankingModelV3DoRerankResult(
                ranking: [],
                warnings: [
                    .unsupported(feature: "object documents", details: "not supported")
                ]
            )
        }

        _ = try await rerank(
            model: model,
            documents: ["a"],
            query: "q"
        )

        #expect(capture.contains(
            .rerankingModel(.unsupported(feature: "object documents", details: "not supported"))
        ))
    }
}

// MARK: - Test Helpers

private final class TestRerankingModel: RerankingModelV3, @unchecked Sendable {
    let providerValue: String
    let modelIdentifier: String
    let handler: @Sendable (RerankingModelV3CallOptions) async throws -> RerankingModelV3DoRerankResult

    init(
        provider: String,
        modelId: String,
        handler: @escaping @Sendable (RerankingModelV3CallOptions) async throws -> RerankingModelV3DoRerankResult
    ) {
        self.providerValue = provider
        self.modelIdentifier = modelId
        self.handler = handler
    }

    var provider: String { providerValue }
    var modelId: String { modelIdentifier }

    func doRerank(options: RerankingModelV3CallOptions) async throws -> RerankingModelV3DoRerankResult {
        try await handler(options)
    }
}
