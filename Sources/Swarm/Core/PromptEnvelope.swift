import Foundation

/// Enforces context-envelope limits for provider prompts.
enum PromptEnvelope {
    private static let truncationMarker = "\n\n[... context truncated for strict4k budget ...]\n\n"

    static func enforce(prompt: String, profile: ContextProfile) async -> String {
        guard profile.preset == .strict4k else {
            return prompt
        }

        let counter = PromptTokenBudgeting.counter()
        let maxTokens = profile.budget.maxInputTokens

        if await PromptTokenBudgeting.countTokens(in: prompt, using: counter) <= maxTokens {
            return prompt
        }

        let marker = truncationMarker
        let markerTokens = await PromptTokenBudgeting.countTokens(in: marker, using: counter)

        if maxTokens <= markerTokens + 16 {
            return await PromptTokenBudgeting.prefix(marker, maxTokens: maxTokens, using: counter)
        }

        // Preserve the beginning (instructions/system context) and the end
        // (latest user/tool context), trimming middle context first.
        let tailTokens = max(16, maxTokens / 3)
        let headTokens = max(16, maxTokens - markerTokens - tailTokens)

        let head = await PromptTokenBudgeting.prefix(prompt, maxTokens: headTokens, using: counter)
        let tail = await PromptTokenBudgeting.suffix(prompt, maxTokens: tailTokens, using: counter)

        var combined = head + marker + tail
        let combinedTokens = await PromptTokenBudgeting.countTokens(in: combined, using: counter)
        if combinedTokens <= maxTokens {
            return combined
        }

        let overflow = combinedTokens - maxTokens
        let adjustedTail = max(0, tailTokens - overflow)
        let adjustedSuffix = await PromptTokenBudgeting.suffix(
            prompt,
            maxTokens: adjustedTail,
            using: counter
        )
        combined = head + marker + adjustedSuffix

        if await PromptTokenBudgeting.countTokens(in: combined, using: counter) <= maxTokens {
            return combined
        }

        let adjustedHead = max(0, maxTokens - markerTokens)
        let fallback = await PromptTokenBudgeting.prefix(prompt, maxTokens: adjustedHead, using: counter) + marker
        if await PromptTokenBudgeting.countTokens(in: fallback, using: counter) <= maxTokens {
            return fallback
        }

        return await PromptTokenBudgeting.prefix(marker, maxTokens: maxTokens, using: counter)
    }
}
