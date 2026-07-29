import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether Apple's on-device model can be used right now, expressed so callers
/// on any OS version can reason about it without `#available` gymnastics.
enum OnDeviceAvailability: Equatable {
    case available
    /// The Mac supports it, but the user hasn't switched Apple Intelligence on.
    case needsAppleIntelligence
    case deviceNotEligible
    /// Supported and enabled, but the weights are still downloading.
    case modelNotReady
    case osTooOld

    var isAvailable: Bool { self == .available }

    /// Short status for the Settings row.
    var summary: String {
        switch self {
        case .available: return "Ready — runs entirely on this Mac, no key needed"
        case .needsAppleIntelligence: return "Apple Intelligence is turned off"
        case .deviceNotEligible: return "This Mac doesn't support Apple Intelligence"
        case .modelNotReady: return "The model is still downloading"
        case .osTooOld: return "Requires macOS 26 or later"
        }
    }

    /// What the user can do about it, when there is something.
    var recovery: String? {
        switch self {
        case .available: return nil
        case .needsAppleIntelligence:
            return "turn it on in System Settings → Apple Intelligence & Siri"
        case .deviceNotEligible:
            return "use a cloud or local-server provider instead"
        case .modelNotReady:
            return "try again in a few minutes"
        case .osTooOld:
            return "use a cloud or local-server provider instead"
        }
    }
}

/// Rewrites text with the language model built into macOS.
///
/// This is the "no key, no server, nothing to install" provider. The model is
/// far smaller than a hosted one and its context window is only a few thousand
/// tokens, so it's positioned as the private/free option rather than the best
/// one — see the copy in Settings → Style.
///
/// The whole framework is gated: `canImport` keeps the file building on older
/// toolchains, and `@available` makes the symbols weak-linked so the app still
/// launches on macOS 15, where this simply reports `.osTooOld`.
enum OnDeviceModelClient {

    // MARK: - availability

    static func availability() -> OnDeviceAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled: return .needsAppleIntelligence
                case .deviceNotEligible: return .deviceNotEligible
                case .modelNotReady: return .modelNotReady
                @unknown default: return .modelNotReady
                }
            @unknown default:
                return .modelNotReady
            }
        }
        #endif
        return .osTooOld
    }

    /// Loads the model while the user is still speaking, so the rewrite itself
    /// doesn't pay the startup cost. Safe to call when unavailable.
    static func prewarm() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), availability().isAvailable {
            makeSession().prewarm()
        }
        #endif
    }

    // MARK: - generation

    /// One-shot completion. Signature matches the HTTP providers so the
    /// `SelectionRewriter.Complete` seam doesn't care which is in use.
    static func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await generate(system: system, user: user, maxTokens: maxTokens)
        }
        #endif
        throw RewriteError.onDeviceUnavailable(.osTooOld)
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func makeSession(instructions: String? = nil) -> LanguageModelSession {
        // `.permissiveContentTransformations` is Apple's mode for exactly this
        // job — transforming text the user supplies, which may legitimately be
        // about difficult subjects. Without it, rewriting a news paragraph or a
        // medical email can trip the default guardrails. It applies only to
        // plain-string generation, which is all this feature does.
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        return LanguageModelSession(model: model, instructions: instructions)
    }

    @available(macOS 26.0, *)
    private static func generate(system: String, user: String, maxTokens: Int) async throws -> String {
        let state = availability()
        guard state.isAvailable else { throw RewriteError.onDeviceUnavailable(state) }

        // The context window covers instructions + prompt + reply together, so
        // the reply budget is whatever is left after the passage. Checked up
        // front: a rewrite that dies partway is worse than one that never ran.
        let context = SystemLanguageModel.default.contextSize
        let budget = try replyBudget(system: system, user: user,
                                     requested: maxTokens, contextSize: context)

        let response: LanguageModelSession.Response<String>
        do {
            response = try await makeSession(instructions: system).respond(
                to: user,
                options: GenerationOptions(temperature: 0.3, maximumResponseTokens: budget))
        } catch let error as LanguageModelSession.GenerationError {
            throw mapped(error)
        }

        let text = response.content
        // Whether hitting `maximumResponseTokens` throws or silently truncates
        // isn't documented, and a truncated rewrite pasted over the selection
        // would amputate the user's text. Treat a reply that ran right up to
        // the ceiling as truncated — the pre-flight check above sizes the
        // budget generously, so a legitimate rewrite shouldn't reach it.
        if estimatedTokens(text) >= Int(Double(budget) * 0.98) {
            throw RewriteError.truncated
        }
        // In permissive mode the model can still decline, and it does so by
        // *returning* a refusal rather than throwing — which would otherwise
        // sail through and get pasted over the user's document.
        if isRefusal(reply: text, prompt: user) {
            throw RewriteError.onDeviceDeclined
        }
        return text
    }

    @available(macOS 26.0, *)
    private static func mapped(_ error: LanguageModelSession.GenerationError) -> RewriteError {
        switch error {
        case .exceededContextWindowSize:
            return .selectionTooLong
        case .guardrailViolation, .refusal:
            return .onDeviceDeclined
        case .unsupportedLanguageOrLocale:
            return .onDeviceUnsupportedLanguage
        case .assetsUnavailable:
            return .onDeviceUnavailable(.modelNotReady)
        case .rateLimited:
            return .onDeviceRateLimited
        default:
            return .onDeviceFailed(error.localizedDescription)
        }
    }
    #endif

    // MARK: - budgeting

    /// Rough token estimate. Deliberately pessimistic (a low chars-per-token
    /// ratio over-counts), because over-counting costs a "too long" error while
    /// under-counting risks a truncated paste.
    static func estimatedTokens(_ text: String) -> Int {
        max(1, Int((Double(text.count) / 3.2).rounded(.up)))
    }

    /// How many tokens the reply may use, or a `selectionTooLong` error when
    /// the passage leaves too little room to be worth attempting.
    ///
    /// A rewrite is usually close to the length of its input, and an "expand
    /// this" instruction is longer — so the floor is generous relative to the
    /// prompt rather than a fixed number.
    static func replyBudget(system: String, user: String,
                            requested: Int, contextSize: Int) throws -> Int {
        let used = estimatedTokens(system) + estimatedTokens(user)
        let remaining = contextSize - used
        // Leave headroom: the estimate is approximate, and running the window
        // exactly to its limit is what produces a mid-sentence cut-off.
        let usable = Int(Double(remaining) * 0.9)
        // The reply needs at least as much room as the passage, or a "make it
        // shorter" would fit while "expand this" silently couldn't.
        let needed = min(requested, max(256, estimatedTokens(user)))
        guard usable >= needed else { throw RewriteError.selectionTooLong }
        return min(requested, usable)
    }

    // MARK: - refusal detection

    /// True when a reply looks like the model declining rather than rewriting.
    ///
    /// Necessarily a heuristic: in permissive mode a refusal comes back as an
    /// ordinary successful string. Two signals must agree — refusal *phrasing*
    /// and a *shape* that doesn't match a rewrite. A real rewrite reuses the
    /// passage's vocabulary heavily; a refusal talks about the request instead.
    /// Requiring both keeps a legitimately short rewrite ("I can't make it
    /// Friday." from a longer excuse) from being thrown away.
    static func isRefusal(reply: String, prompt: String) -> Bool {
        let lowered = reply.lowercased()
        let opens = refusalOpeners.contains { lowered.hasPrefix($0) || lowered.contains(" \($0)") }
        guard opens else { return false }
        // Refusals are short. A long reply that merely contains "I can't"
        // somewhere is the user's own prose being rewritten.
        guard StyleCorpus.wordCount(reply) < 60 else { return false }
        return overlap(reply: reply, prompt: prompt) < 0.25
    }

    /// Share of the reply's words that also appear in the prompt.
    private static func overlap(reply: String, prompt: String) -> Double {
        let replyWords = Set(words(reply))
        guard !replyWords.isEmpty else { return 0 }
        let promptWords = Set(words(prompt))
        let shared = replyWords.filter(promptWords.contains).count
        return Double(shared) / Double(replyWords.count)
    }

    private static func words(_ text: String) -> [String] {
        let cleaned = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").map(String.init)
    }

    private static let refusalOpeners = [
        "i can't", "i cannot", "i can not", "i'm not able", "i am not able",
        "i'm unable", "i am unable", "i won't", "i will not", "sorry, i",
        "i'm sorry", "i am sorry", "unfortunately, i", "i'm not going to",
        "i don't feel comfortable", "i'm not comfortable"
    ]
}
