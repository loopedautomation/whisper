import Foundation

/// LLM fallback for quick-action detection: when no local trigger matches,
/// asks the user's configured Rewrite provider whether the utterance is a
/// paraphrased command for one of the user-defined actions ("could you pull
/// up github" → Open GitHub). The model only *selects among the user's
/// actions by id* — it never invents URLs or commands. Any failure, parse
/// error, or unknown id resolves to nil and the transcript is pasted as usual.
struct QuickActionClassifier {
    struct Match {
        var actionID: UUID
        var query: String?
    }

    private static let systemPrompt = """
    You classify a dictated utterance against a list of user-defined quick \
    actions. Respond with ONLY a JSON object, no prose or markdown. If the \
    utterance is clearly a spoken command matching exactly one action, respond \
    {"action_id": "<id>", "query": "<free text the action's {{query}} \
    placeholder should receive, or null>"}. If it is ordinary dictation, \
    ambiguous, or matches nothing, respond {"action_id": null}. Prefer null \
    when unsure — a false positive (swallowing the user's dictation) is much \
    worse than a miss.
    """

    static func classify(_ transcript: String, actions: [QuickAction], config: RewriteService.Config) async -> Match? {
        let candidates = actions.filter(\.enabled)
        guard !candidates.isEmpty, !transcript.isEmpty, !config.apiKey.isEmpty else { return nil }

        let catalog = candidates.map {
            ["id": $0.id.uuidString, "name": $0.name, "triggers": $0.triggers,
             "kind": $0.kind.label, "accepts_query": $0.target.contains("{{query}}")] as [String: Any]
        }
        guard let catalogData = try? JSONSerialization.data(withJSONObject: catalog),
              let catalogJSON = String(data: catalogData, encoding: .utf8) else { return nil }
        let userMessage = "Actions:\n\(catalogJSON)\n\nUtterance:\n\(transcript)"

        guard let reply = try? await complete(userMessage: userMessage, config: config) else { return nil }
        return parse(reply, actions: candidates)
    }

    /// Parses the model reply. Tolerates markdown code fences; anything else
    /// unexpected → nil (fall through to paste).
    static func parse(_ reply: String, actions: [QuickAction]) -> Match? {
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idString = json["action_id"] as? String,
              let id = UUID(uuidString: idString),
              actions.contains(where: { $0.id == id }) else { return nil }
        let query = (json["query"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Match(actionID: id, query: query)
    }

    // MARK: - provider calls (same wire formats as RewriteService)

    private static func complete(userMessage: String, config: RewriteService.Config) async throws -> String {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = min(config.timeout, 5)
        let session = URLSession(configuration: cfg)

        var req: URLRequest
        let body: [String: Any]
        switch config.provider {
        case .anthropic:
            req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": config.model,
                "max_tokens": 256,
                "system": systemPrompt,
                "messages": [["role": "user", "content": userMessage]]
            ]
        case .openaiCompatible(let baseURL):
            let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")!
            req = URLRequest(url: url)
            req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": config.model,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userMessage]
                ]
            ]
        }
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "QuickActionClassifier", code: 1)
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        switch config.provider {
        case .anthropic:
            let content = json?["content"] as? [[String: Any]]
            return content?.compactMap { $0["text"] as? String }.joined() ?? ""
        case .openaiCompatible:
            let choices = json?["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            return message?["content"] as? String ?? ""
        }
    }
}
