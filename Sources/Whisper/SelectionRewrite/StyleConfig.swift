import Foundation

/// A named variation on the base style — "Email", "Slack", "Docs".
///
/// An overlay, not a whole profile. Lists **add** to the base and scalars
/// **replace** it, which matches how people actually think about this: a word
/// you never use anywhere stays banned everywhere, while a template adds its
/// own tone and its own limits on top.
struct StyleOverlay: Equatable {
    /// Replaces the base description when present.
    var description: String?
    /// Replaces the base samples when present — a template's voice is its own,
    /// not the base voice with extras bolted on.
    var samples: [String]?
    /// Added to the base guidance.
    var guidance: [String] = []
    /// Added to the base rules.
    var substitutions: [StyleProfile.Substitution] = []
    var bannedWords: [StyleProfile.BannedWord] = []
    /// Replace the base value when present.
    var straightenQuotes: Bool?
    var maxWords: Int?
}

/// The whole of `style.json`: one base profile plus any named templates.
///
/// A file with no `templates` key is just the base — which is every existing
/// config, so nothing has to change to keep working.
struct StyleConfig: Equatable {
    var base = StyleProfile()
    /// Keyed by lowercased name for lookup; `order` preserves the file's own
    /// ordering for display.
    var templates: [String: StyleOverlay] = [:]
    var order: [String] = []
    /// Template applied when the user doesn't name one. `nil` = the base.
    var defaultTemplate: String?

    /// Display names, in file order, with the base first.
    static let baseName = "Default"

    var names: [String] { [StyleConfig.baseName] + order }

    /// Names the command parser should recognize in spoken instructions.
    var templateNames: [String] { order }

    /// Resolves a template name to the profile a rewrite should actually use.
    /// Unknown or absent names fall back to the base rather than failing — a
    /// misheard template shouldn't cost the user their rewrite.
    func profile(named name: String?) -> StyleProfile {
        guard let name, let overlay = templates[name.lowercased()] else { return base }
        var p = base
        if let description = overlay.description { p.voice.description = description }
        if let samples = overlay.samples { p.voice.samples = samples }
        p.prompted.guidance += overlay.guidance
        p.enforced.substitutions += overlay.substitutions
        // A word banned in both places would otherwise be reported twice.
        var seen = Set(p.enforced.bannedWords.map { $0.word.lowercased() })
        for banned in overlay.bannedWords where !seen.contains(banned.word.lowercased()) {
            p.enforced.bannedWords.append(banned)
            seen.insert(banned.word.lowercased())
        }
        if let straighten = overlay.straightenQuotes { p.enforced.straightenQuotes = straighten }
        if let limit = overlay.maxWords { p.enforced.maxWords = limit }
        return p
    }

    /// The profile used when no template is named in the command.
    var defaultProfile: StyleProfile { profile(named: defaultTemplate) }
}

// MARK: - decoding

extension StyleConfig {
    /// Same strictness as the base profile: an unknown key anywhere — including
    /// inside a template — is a hard error, so a typo can never be a silently
    /// inactive rule.
    private static var schema: JSONSchema {
        guard case .object(let baseFields) = StyleProfile.schema else {
            return StyleProfile.schema
        }
        var fields = baseFields
        fields["templates"] = .dictionary(.object(baseFields))
        fields["defaultTemplate"] = .scalar
        return .object(fields)
    }

    static func decode(_ data: Data) throws -> StyleConfig {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw StyleProfileError.malformedJSON(error.localizedDescription)
        }
        guard let object = root as? [String: Any] else { throw StyleProfileError.notAnObject }
        try schema.validate(object, at: [])

        var config = StyleConfig()
        config.base = try StyleProfile.build(from: object)

        if let raw = object["templates"], !(raw is NSNull) {
            guard let dict = raw as? [String: Any] else {
                throw StyleProfileError.wrongType("templates", expected: "object")
            }
            // Sorted so the order is stable across launches — JSON objects have
            // no inherent ordering, and a picker that reshuffles is maddening.
            for name in dict.keys.sorted() {
                guard let entry = dict[name] as? [String: Any] else {
                    throw StyleProfileError.wrongType("templates.\(name)", expected: "object")
                }
                guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                    throw StyleProfileError.invalidValue("templates", reason: "has an unnamed template")
                }
                config.templates[name.lowercased()] = try overlay(from: entry, name: name)
                config.order.append(name)
            }
        }

        if let raw = object["defaultTemplate"], !(raw is NSNull) {
            guard let name = raw as? String else {
                throw StyleProfileError.wrongType("defaultTemplate", expected: "string")
            }
            // Pointing the default at a template that doesn't exist would
            // silently fall back to the base — exactly the "rule you think is
            // on but isn't" failure this config refuses to have.
            guard name.isEmpty || config.templates[name.lowercased()] != nil else {
                throw StyleProfileError.invalidValue(
                    "defaultTemplate",
                    reason: "names \"\(name)\", which isn't one of your templates")
            }
            config.defaultTemplate = name.isEmpty ? nil : name
        }
        return config
    }

    private static func overlay(from object: [String: Any], name: String) throws -> StyleOverlay {
        var overlay = StyleOverlay()
        let path = "templates.\(name)"
        if let voice = object["voice"] as? [String: Any] {
            overlay.description = try StyleProfile.string(voice["description"], at: "\(path).voice.description")
            if let raw = voice["samples"], !(raw is NSNull) {
                overlay.samples = try StyleProfile.strings(raw, at: "\(path).voice.samples")
            }
        }
        if let prompted = object["prompted"] as? [String: Any] {
            overlay.guidance = try StyleProfile.strings(prompted["guidance"], at: "\(path).prompted.guidance")
        }
        if let enforced = object["enforced"] as? [String: Any] {
            // Reuse the base rule parser so templates and the base can never
            // drift in what they accept.
            let rules = try StyleProfile.decodeEnforced(enforced)
            overlay.substitutions = rules.substitutions
            overlay.bannedWords = rules.bannedWords
            overlay.maxWords = rules.maxWords
            // `straightenQuotes` defaults to false, so an absent key and an
            // explicit `false` are indistinguishable after parsing — check the
            // raw document to tell "not set" from "turned off".
            if let raw = enforced["straightenQuotes"], !(raw is NSNull) {
                overlay.straightenQuotes = raw as? Bool
            }
        }
        return overlay
    }
}

// MARK: - encoding

extension StyleConfig {
    /// Serializes the whole config back to `style.json`, templates included, so
    /// accepting a mined rule can't drop them.
    func encoded() throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: base.encoded()) as? [String: Any] else {
            throw StyleProfileError.notAnObject
        }
        if !order.isEmpty {
            var out: [String: Any] = [:]
            for name in order {
                guard let overlay = templates[name.lowercased()] else { continue }
                out[name] = overlay.jsonObject()
            }
            root["templates"] = out
        }
        if let defaultTemplate { root["defaultTemplate"] = defaultTemplate }
        return try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}

private extension StyleOverlay {
    /// Only what the template actually sets — writing absent keys back as
    /// defaults would turn "inherit from base" into "override with nothing".
    func jsonObject() -> [String: Any] {
        var voice: [String: Any] = [:]
        if let description { voice["description"] = description }
        if let samples { voice["samples"] = samples }

        var enforced: [String: Any] = [:]
        if !substitutions.isEmpty {
            enforced["substitutions"] = substitutions.map { ["find": $0.find, "replace": $0.replace] }
        }
        if !bannedWords.isEmpty {
            enforced["bannedWords"] = bannedWords.map { banned -> [String: Any] in
                var entry: [String: Any] = ["word": banned.word]
                if let replacement = banned.replacement { entry["replacement"] = replacement }
                return entry
            }
        }
        if let straightenQuotes { enforced["straightenQuotes"] = straightenQuotes }
        if let maxWords { enforced["maxWords"] = maxWords }

        var out: [String: Any] = [:]
        if !voice.isEmpty { out["voice"] = voice }
        if !guidance.isEmpty { out["prompted"] = ["guidance": guidance] }
        if !enforced.isEmpty { out["enforced"] = enforced }
        return out
    }
}
