import XCTest
@testable import Whisper

/// Hands back canned model replies in order and records what it was asked.
/// Lets the whole rewrite pipeline run with no network and no microphone.
private actor ReplyStub {
    enum StubError: Error { case exhausted, boom }

    private var replies: [String]
    private var failAfter: Int?
    private(set) var prompts: [String] = []

    /// `failAfter: n` makes call number n+1 throw, to exercise the paths where
    /// the provider dies mid-pipeline.
    init(_ replies: [String], failAfter: Int? = nil) {
        self.replies = replies
        self.failAfter = failAfter
    }

    var callCount: Int { prompts.count }

    func next(system: String, user: String) throws -> String {
        prompts.append(user)
        if let failAfter, prompts.count > failAfter { throw StubError.boom }
        guard !replies.isEmpty else { throw StubError.exhausted }
        return replies.removeFirst()
    }
}

final class StyleEnforcerTests: XCTestCase {

    /// The headline guarantee: the model emits an em dash, the user never sees
    /// one. Prompting alone can't promise this, so it's fixed in code.
    func testEmDashIsRepairedWithoutAskingTheModelAgain() {
        let enforced = StyleProfile.Enforced(
            substitutions: [.init(find: "\u{2014}", replace: ", ")])
        let result = StyleEnforcer.apply("It was fine\u{2014}really fine.", style: enforced)

        XCTAssertEqual(result.text, "It was fine, really fine.")
        XCTAssertFalse(result.text.contains("\u{2014}"))
        // Repairable, so nothing goes back to the model.
        XCTAssertTrue(result.isCompliant)
    }

    func testCurlyQuotesAreStraightened() {
        let enforced = StyleProfile.Enforced(straightenQuotes: true)
        let result = StyleEnforcer.apply(
            "\u{201C}It\u{2019}s fine,\u{201D} she said.", style: enforced)
        XCTAssertEqual(result.text, "\"It's fine,\" she said.")
        XCTAssertTrue(result.isCompliant)
    }

    /// A banned word that names its replacement is swapped in code, keeping the
    /// original capitalization so sentence starts don't come back lowercased.
    func testBannedWordWithReplacementIsSwappedPreservingCase() {
        let enforced = StyleProfile.Enforced(
            bannedWords: [.init(word: "leverage", replacement: "use")])
        let result = StyleEnforcer.apply(
            "Leverage the tool. We leverage it daily. LEVERAGE it.", style: enforced)

        XCTAssertEqual(result.text, "Use the tool. We use it daily. USE it.")
        XCTAssertTrue(result.isCompliant)
    }

    /// Whole-word only — "leveraged" and "cleverage" must survive untouched.
    func testBannedWordDoesNotMatchInsideOtherWords() {
        let enforced = StyleProfile.Enforced(
            bannedWords: [.init(word: "use", replacement: "apply")])
        let result = StyleEnforcer.apply("Reuse the used user's use.", style: enforced)
        XCTAssertEqual(result.text, "Reuse the used user's apply.")
    }

    /// No replacement given, so code can't fix it — it becomes a violation for
    /// the model, not a silent deletion.
    func testBannedWordWithoutReplacementIsReportedNotDeleted() {
        let enforced = StyleProfile.Enforced(bannedWords: [.init(word: "synergy", replacement: nil)])
        let result = StyleEnforcer.apply("We need real synergy here.", style: enforced)

        XCTAssertEqual(result.text, "We need real synergy here.")
        XCTAssertEqual(result.violations.count, 1)
        XCTAssertTrue(result.violations[0].message.contains("\"synergy\""))
    }

    /// The retry message has to name the breach precisely — a vague "you broke
    /// a rule" is far weaker than the numbers.
    func testWordLimitViolationNamesBothNumbers() {
        let enforced = StyleProfile.Enforced(maxWords: 3)
        let result = StyleEnforcer.apply("one two three four five", style: enforced)
        XCTAssertEqual(result.violations, [.init(message: "the rewrite is 5 words; the limit is 3")])
    }

    func testCompliantTextHasNoViolations() {
        let enforced = StyleProfile.Enforced(bannedWords: [.init(word: "synergy")], maxWords: 10)
        XCTAssertTrue(StyleEnforcer.apply("A short, clean sentence.", style: enforced).isCompliant)
    }

    /// Repairs run before checking, so a substitution can't leave the text
    /// over the word limit by accident — and the count is measured on what the
    /// user actually receives.
    func testWordCountIsMeasuredAfterRepairs() {
        let enforced = StyleProfile.Enforced(
            substitutions: [.init(find: "\u{2014}", replace: " ")], maxWords: 2)
        let result = StyleEnforcer.apply("one\u{2014}two", style: enforced)
        XCTAssertEqual(result.text, "one two")
        XCTAssertTrue(result.isCompliant)
    }
}

final class ResponseUnwrapperTests: XCTestCase {

    func testStripsCodeFence() {
        XCTAssertEqual(ResponseUnwrapper.unwrap("```\nHello there.\n```"), "Hello there.")
        XCTAssertEqual(ResponseUnwrapper.unwrap("```markdown\nHello there.\n```"), "Hello there.")
    }

    func testStripsPreamble() {
        XCTAssertEqual(
            ResponseUnwrapper.unwrap("Here's the rewritten text:\n\nHello there."),
            "Hello there.")
        XCTAssertEqual(
            ResponseUnwrapper.unwrap("Sure! Here is a shorter version:\nHello."),
            "Hello.")
    }

    func testStripsSurroundingQuotes() {
        XCTAssertEqual(ResponseUnwrapper.unwrap("\"Hello there.\""), "Hello there.")
        XCTAssertEqual(ResponseUnwrapper.unwrap("\u{201C}Hello there.\u{201D}"), "Hello there.")
    }

    /// Quoted dialogue is real content — unwrapping it would corrupt the text.
    func testKeepsQuotesThatAreActuallyPartOfTheText() {
        let dialogue = "\"Stop,\" he said, \"now.\""
        XCTAssertEqual(ResponseUnwrapper.unwrap(dialogue), dialogue)
    }

    /// A fenced block inside a longer reply is content, not packaging.
    func testKeepsInternalCodeFence() {
        let text = "Run this:\n```\nls -la\n```\nThen check the output."
        XCTAssertEqual(ResponseUnwrapper.unwrap(text), text)
    }

    /// Regression, audit finding #4: matching on "here's" / "i have" alone
    /// deleted lines the *user* wrote. A lead-in has to refer to the output.
    func testKeepsFirstLinesThatAreTheUsersOwnContent() {
        for text in ["I have three concerns:\n1. Cost\n2. Timing",
                     "Here's what we found:\nThe build is slow.",
                     "Sure things to check:\nThe cache."] {
            XCTAssertEqual(ResponseUnwrapper.unwrap(text), text,
                           "should not strip a content heading from: \(text)")
        }
    }

    /// Regression, audit finding #10: content after the closing fence was
    /// discarded, silently truncating the paste.
    func testKeepsContentFollowingAClosingFence() {
        let text = "```\nlet x = 1\n```\nAnd here is why that matters."
        XCTAssertEqual(ResponseUnwrapper.unwrap(text), text)
    }

    /// Models stack the layers; one pass isn't enough.
    func testStripsCombinedLayers() {
        XCTAssertEqual(
            ResponseUnwrapper.unwrap("Here's the rewritten text:\n```\n\"Hello there.\"\n```"),
            "Hello there.")
    }
}

final class CommandNormalizerTests: XCTestCase {

    /// The requirement: transcript noise must not change the intent.
    func testNoisySpokenCommandLandsOnTheSameIntentAsTheTerseOne() {
        let noisy = CommandNormalizer.normalize("um, could you make this shorter please")
        let terse = CommandNormalizer.normalize("shorter")

        XCTAssertEqual(noisy.intent, .shorten)
        XCTAssertEqual(noisy.intent, terse.intent)
        // Same instruction reaches the model either way.
        XCTAssertEqual(noisy.intent.instruction, terse.intent.instruction)
        XCTAssertEqual(noisy.cleaned, "shorter")
    }

    func testRecognizesTheCoreCommands() {
        let cases: [(String, RewriteIntent)] = [
            ("rewrite it", .rewrite),
            ("make it shorter", .shorten),
            ("fix the typos", .fixTypos),
            ("uh, fix the spelling, please", .fixTypos),
            ("can you make this a bit more formal", .formalize),
            ("expand on this", .lengthen),
            ("simplify it", .simplify),
            ("make it more casual", .casualize),
            ("tighten it up", .shorten)
        ]
        for (spoken, expected) in cases {
            XCTAssertEqual(CommandNormalizer.normalize(spoken).intent, expected,
                           "for spoken command: \(spoken)")
        }
    }

    /// Anything unrecognized still works — it's passed through verbatim rather
    /// than forced into the nearest known bucket.
    func testUnknownCommandIsPassedThroughAsCustom() {
        let command = CommandNormalizer.normalize("um, make it sound like a pirate")
        XCTAssertEqual(command.intent, .custom("sound like a pirate"))
        XCTAssertEqual(command.intent.instruction, "sound like a pirate")
        XCTAssertEqual(command.raw, "um, make it sound like a pirate")
    }

    /// Regression, audit finding #7: "less formal" matched the bare keyword
    /// "formal" and returned the exact opposite of the request.
    func testNegatedCommandsAreNotInverted() {
        XCTAssertEqual(CommandNormalizer.normalize("make it less formal").intent, .casualize)
        XCTAssertEqual(CommandNormalizer.normalize("not so formal please").intent, .casualize)
        XCTAssertEqual(CommandNormalizer.normalize("make it less casual").intent, .formalize)
        XCTAssertEqual(CommandNormalizer.normalize("less wordy").intent, .shorten)
    }

    /// Regression, audit finding #7: `.fixTypos` instructs the model to change
    /// nothing else, so it must not win over an explicit shortening request.
    func testShorteningWinsOverTypoFixingWhenBothAreAsked() {
        XCTAssertEqual(
            CommandNormalizer.normalize("make it shorter and fix the typos").intent, .shorten)
        // …but a bare typo request is still a typo request.
        XCTAssertEqual(CommandNormalizer.normalize("fix the typos").intent, .fixTypos)
    }

    /// Filler-stripping must not eat meaning. "like", "well" and friends are
    /// throat-clearing at the start of a command but load-bearing inside one —
    /// stripping them everywhere turns "sound like a pirate" into "sound a
    /// pirate", which is a different instruction.
    func testMeaningfulWordsAreOnlyStrippedWhenLeading() {
        XCTAssertEqual(CommandNormalizer.normalize("um, like, make it shorter").intent, .shorten)
        XCTAssertEqual(CommandNormalizer.normalize("well, just fix the typos").intent, .fixTypos)
        XCTAssertEqual(CommandNormalizer.normalize("make it sound like a pirate").intent,
                       .custom("sound like a pirate"))
        XCTAssertEqual(CommandNormalizer.normalize("make it read well").intent,
                       .custom("read well"))
    }

    /// Pure filler is a bare "rewrite it", not an empty instruction.
    func testEmptyOrFillerOnlyCommandFallsBackToRewrite() {
        XCTAssertEqual(CommandNormalizer.normalize("").intent, .rewrite)
        XCTAssertEqual(CommandNormalizer.normalize("um, uh, please").intent, .rewrite)
    }
}

final class StyleProfileDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> StyleProfile {
        try StyleProfile.decode(Data(json.utf8))
    }

    func testDecodesAFullProfile() throws {
        let profile = try decode("""
        {
          "voice": { "description": "Terse.", "samples": ["A sample."] },
          "prompted": { "guidance": ["Lead with the point."] },
          "enforced": {
            "substitutions": [{ "find": "\\u2014", "replace": ", " }],
            "straightenQuotes": true,
            "bannedWords": [{ "word": "leverage", "replacement": "use" }, { "word": "delve" }],
            "maxWords": 200
          }
        }
        """)

        XCTAssertEqual(profile.voice.description, "Terse.")
        XCTAssertEqual(profile.voice.samples, ["A sample."])
        XCTAssertEqual(profile.prompted.guidance, ["Lead with the point."])
        XCTAssertEqual(profile.enforced.substitutions, [.init(find: "\u{2014}", replace: ", ")])
        XCTAssertTrue(profile.enforced.straightenQuotes)
        XCTAssertEqual(profile.enforced.bannedWords,
                       [.init(word: "leverage", replacement: "use"), .init(word: "delve")])
        XCTAssertEqual(profile.enforced.maxWords, 200)
    }

    /// The rule that matters most: a typo must be loud. A silently ignored
    /// rule is one the user would believe is on forever.
    func testMisspelledRuleNameIsAHardErrorWithASuggestion() {
        XCTAssertThrowsError(try decode("""
        { "enforced": { "bannedWord": [{ "word": "delve" }] } }
        """)) { error in
            guard case StyleProfileError.unknownKey(let path, let suggestion) = error else {
                return XCTFail("expected unknownKey, got \(error)")
            }
            XCTAssertEqual(path, "enforced.bannedWord")
            XCTAssertEqual(suggestion, "bannedWords")
        }
    }

    func testUnknownTopLevelSectionIsRejected() {
        XCTAssertThrowsError(try decode(#"{ "enforcedRules": {} }"#)) { error in
            guard case StyleProfileError.unknownKey(let path, _) = error else {
                return XCTFail("expected unknownKey, got \(error)")
            }
            XCTAssertEqual(path, "enforcedRules")
        }
    }

    /// Nested typos are caught too, with the full path so the user can find it.
    func testUnknownNestedKeyReportsItsFullPath() {
        XCTAssertThrowsError(try decode("""
        { "enforced": { "bannedWords": [{ "word": "delve", "replacment": "explore" }] } }
        """)) { error in
            guard case StyleProfileError.unknownKey(let path, let suggestion) = error else {
                return XCTFail("expected unknownKey, got \(error)")
            }
            XCTAssertEqual(path, "enforced.bannedWords[0].replacment")
            XCTAssertEqual(suggestion, "replacement")
        }
    }

    func testWrongTypeIsRejected() {
        XCTAssertThrowsError(try decode(#"{ "enforced": { "maxWords": "200" } }"#)) { error in
            guard case StyleProfileError.wrongType(let path, _) = error else {
                return XCTFail("expected wrongType, got \(error)")
            }
            XCTAssertEqual(path, "enforced.maxWords")
        }
    }

    /// Regression, audit finding #2: a section of the wrong *type* parsed
    /// happily and silently dropped every rule inside it — the exact failure
    /// the schema walk exists to prevent.
    func testWrongTypedSectionIsRejected() {
        for json in [#"{ "enforced": [ { "maxWords": 10 } ] }"#,
                     #"{ "enforced": "straightenQuotes" }"#,
                     #"{ "voice": 42 }"#,
                     #"{ "enforced": { "bannedWords": { "word": "delve" } } }"#] {
            XCTAssertThrowsError(try decode(json), "should reject: \(json)") { error in
                guard case StyleProfileError.wrongType = error else {
                    return XCTFail("expected wrongType for \(json), got \(error)")
                }
            }
        }
    }

    /// Regression, audit finding #16: JSON `1` bridges to an NSNumber that
    /// satisfies `is Bool`, so a legal one-word limit was rejected as a type
    /// error.
    func testMaxWordsOfOneIsLegal() throws {
        XCTAssertEqual(try decode(#"{ "enforced": { "maxWords": 1 } }"#).enforced.maxWords, 1)
        // …while an actual boolean, or a non-integer, is still a type error.
        XCTAssertThrowsError(try decode(#"{ "enforced": { "maxWords": true } }"#))
        XCTAssertThrowsError(try decode(#"{ "enforced": { "maxWords": 1.5 } }"#))
    }

    func testNonsensicalValuesAreRejected() {
        XCTAssertThrowsError(try decode(#"{ "enforced": { "maxWords": 0 } }"#))
        XCTAssertThrowsError(try decode(#"{ "enforced": { "bannedWords": [{ "word": "" }] } }"#))
    }

    /// `null` means "not set", so a rule can sit in the file as a placeholder.
    func testNullMeansUnset() throws {
        let profile = try decode(#"{ "enforced": { "maxWords": null } }"#)
        XCTAssertNil(profile.enforced.maxWords)
    }

    /// The starter file shipped on first launch must itself parse — as a full
    /// config, since it now demonstrates templates too.
    func testStarterFileIsValid() throws {
        let config = try StyleConfig.decode(Data(StyleStore.starterFile.utf8))
        XCTAssertTrue(config.base.enforced.straightenQuotes)
        XCTAssertEqual(config.base.enforced.substitutions.first?.find, "\u{2014}")
        // The examples have to be real, working templates, not illustrative
        // JSON that would fail the moment someone edits it.
        XCTAssertEqual(config.templateNames, ["email", "slack"])
        XCTAssertEqual(config.profile(named: "slack").enforced.maxWords, 60)
        // Shipped default is the base — templates are opt-in.
        XCTAssertNil(config.defaultTemplate)
    }
}

final class SelectionRewriterTests: XCTestCase {

    private let emDashStyle = ResolvedStyle(profile: StyleProfile(
        voice: .init(), prompted: .init(),
        enforced: .init(substitutions: [.init(find: "\u{2014}", replace: ", ")],
                        straightenQuotes: true)))

    private func command(_ text: String) -> CommandNormalizer.Command {
        CommandNormalizer.normalize(text)
    }

    /// End to end with a stubbed model: the reply contains an em dash and curly
    /// quotes, and the user sees neither — with no second model call.
    func testModelReturnsAnEmDashAndTheUserNeverSeesOne() async throws {
        let stub = ReplyStub(["The plan is simple\u{2014}we ship on Friday."])
        let outcome = await SelectionRewriter.rewrite(
            selection: "The plan, broadly speaking, is that we will be shipping on Friday.",
            command: command("make it shorter"),
            style: emDashStyle,
            complete: { try await stub.next(system: $0, user: $1) })

        guard case .rewritten(let text, let unmetRules) = outcome else {
            return XCTFail("expected a rewrite, got \(outcome)")
        }
        XCTAssertEqual(text, "The plan is simple, we ship on Friday.")
        XCTAssertFalse(text.contains("\u{2014}"))
        XCTAssertTrue(unmetRules.isEmpty)
        let calls = await stub.callCount
        XCTAssertEqual(calls, 1, "a repairable rule must not cost an extra model call")
    }

    /// Model packaging is stripped before enforcement, so neither the fence nor
    /// the em dash reaches the document.
    func testPackagingIsStrippedBeforeEnforcement() async throws {
        let stub = ReplyStub(["Here's the rewritten text:\n```\nShip it\u{2014}now.\n```"])
        let outcome = await SelectionRewriter.rewrite(
            selection: "We should probably ship it at some point soon.",
            command: command("shorter"),
            style: emDashStyle,
            complete: { try await stub.next(system: $0, user: $1) })

        guard case .rewritten(let text, _) = outcome else {
            return XCTFail("expected a rewrite, got \(outcome)")
        }
        XCTAssertEqual(text, "Ship it, now.")
    }

    /// An unrepairable rule goes back to the model exactly once, naming what
    /// broke — and the retry prompt has to carry the numbers.
    func testWordLimitTriggersOneRetryThatNamesTheBreach() async throws {
        let style = ResolvedStyle(profile: StyleProfile(
            voice: .init(), prompted: .init(), enforced: .init(maxWords: 3)))
        let stub = ReplyStub(["one two three four five", "one two three"])

        let outcome = await SelectionRewriter.rewrite(
            selection: "A long original sentence that needs cutting down.",
            command: command("shorter"),
            style: style,
            complete: { try await stub.next(system: $0, user: $1) })

        XCTAssertEqual(outcome, .rewritten(text: "one two three", unmetRules: []))
        let prompts = await stub.prompts
        XCTAssertEqual(prompts.count, 2, "exactly one retry")
        XCTAssertTrue(prompts[1].contains("the rewrite is 5 words; the limit is 3"),
                      "retry must name the breach: \(prompts[1])")
    }

    /// Still broken after the retry: deliver the best attempt, but say so.
    /// Silently dropping a rule the user asked for is the one thing we can't do.
    func testPersistentViolationIsReportedLoudlyWithTheBestAttempt() async throws {
        let style = ResolvedStyle(profile: StyleProfile(
            voice: .init(), prompted: .init(),
            enforced: .init(bannedWords: [.init(word: "synergy")])))
        let stub = ReplyStub(["Real synergy matters.", "Still about synergy."])

        let outcome = await SelectionRewriter.rewrite(
            selection: "We should talk about how the teams work together.",
            command: command("rewrite it"),
            style: style,
            complete: { try await stub.next(system: $0, user: $1) })

        guard case .rewritten(let text, let unmetRules) = outcome else {
            return XCTFail("expected a rewrite, got \(outcome)")
        }
        XCTAssertFalse(text.isEmpty, "the user still gets the best attempt")
        XCTAssertEqual(unmetRules.count, 1)
        XCTAssertTrue(unmetRules[0].contains("synergy"))
    }

    /// A dead provider must not paste anything — the user's text stays as it is.
    func testModelFailureYieldsNoTextToPaste() async throws {
        let stub = ReplyStub([], failAfter: 0)
        let outcome = await SelectionRewriter.rewrite(
            selection: "Some text.", command: command("shorter"),
            style: emDashStyle,
            complete: { try await stub.next(system: $0, user: $1) })

        guard case .failed = outcome else {
            return XCTFail("expected failure, got \(outcome)")
        }
    }

    /// If the retry call dies, the first attempt is still usable — deliver it
    /// with its unmet rules rather than losing the work entirely.
    func testRetryFailureFallsBackToTheFirstAttempt() async throws {
        let style = ResolvedStyle(profile: StyleProfile(
            voice: .init(), prompted: .init(), enforced: .init(maxWords: 2)))
        let stub = ReplyStub(["one two three"], failAfter: 1)

        let outcome = await SelectionRewriter.rewrite(
            selection: "Original text.", command: command("shorter"),
            style: style,
            complete: { try await stub.next(system: $0, user: $1) })

        guard case .rewritten(let text, let unmetRules) = outcome else {
            return XCTFail("expected a rewrite, got \(outcome)")
        }
        XCTAssertEqual(text, "one two three")
        XCTAssertEqual(unmetRules, ["the rewrite is 3 words; the limit is 2"])
    }

    func testEmptySelectionFailsBeforeCallingTheModel() async throws {
        let stub = ReplyStub(["should never be used"])
        let outcome = await SelectionRewriter.rewrite(
            selection: "   \n ", command: command("shorter"),
            style: emDashStyle,
            complete: { try await stub.next(system: $0, user: $1) })

        guard case .failed = outcome else { return XCTFail("expected failure, got \(outcome)") }
        let calls = await stub.callCount
        XCTAssertEqual(calls, 0)
    }

    /// The prompt must carry the guardrails and the style, since prompting is
    /// the first line of defence even where code enforces the same rule.
    func testSystemPromptCarriesGuardrailsVoiceAndRules() {
        let style = ResolvedStyle(profile: StyleProfile(
            voice: .init(description: "Terse and concrete.", samples: ["A real sample."]),
            prompted: .init(guidance: ["Lead with the point."]),
            enforced: .init(substitutions: [.init(find: "\u{2014}", replace: ", ")],
                            straightenQuotes: true,
                            bannedWords: [.init(word: "delve")],
                            maxWords: 200)))
        let prompt = SelectionRewriter.systemPrompt(style: style)

        XCTAssertTrue(prompt.contains("Never invent facts"))
        XCTAssertTrue(prompt.contains("Return ONLY the rewritten passage"))
        XCTAssertTrue(prompt.contains("Terse and concrete."))
        XCTAssertTrue(prompt.contains("A real sample."))
        XCTAssertTrue(prompt.contains("Lead with the point."))
        XCTAssertTrue(prompt.contains("at most 200 words"))
        XCTAssertTrue(prompt.contains("\"delve\""))
    }

    /// The passage is delimited so the model can tell instruction from content,
    /// and the raw spoken command rides along with the normalized intent.
    func testUserMessageCarriesPassageAndRawCommand() {
        let message = SelectionRewriter.userMessage(
            selection: "The original passage.",
            command: command("um, make it shorter please"))

        XCTAssertTrue(message.contains("<passage>\nThe original passage.\n</passage>"))
        XCTAssertTrue(message.contains("um, make it shorter please"))
        XCTAssertTrue(message.contains(RewriteIntent.shorten.instruction))
    }

    /// Regression, audit finding #6: the raw command was dropped for exactly
    /// the case that needs it. Normalization lowercases and strips punctuation,
    /// so a custom instruction loses the wording it depends on.
    func testCustomCommandsKeepTheirOriginalWording() {
        let message = SelectionRewriter.userMessage(
            selection: "Hi there.",
            command: command("Change the greeting to Hello, World!"))
        XCTAssertTrue(message.contains("Change the greeting to Hello, World!"),
                      "raw wording must survive: \(message)")
    }

    /// Regression, audit finding #3: a reply cut off at the token ceiling is an
    /// incomplete passage, and pasting it would amputate the user's text.
    func testTruncatedReplyIsReportedAndNothingIsPasted() async throws {
        let outcome = await SelectionRewriter.rewrite(
            selection: "A long passage.", command: command("shorter"),
            style: emDashStyle,
            complete: { _, _ in throw RewriteError.truncated })

        guard case .failed(let reason) = outcome else {
            return XCTFail("expected failure, got \(outcome)")
        }
        XCTAssertTrue(reason.contains("incomplete"), "unhelpful reason: \(reason)")
    }
}

final class OnDeviceModelClientTests: XCTestCase {

    // MARK: - context budgeting

    /// The window covers instructions + prompt + reply together, so a passage
    /// that leaves no room for an answer must fail before the model runs — a
    /// rewrite that dies partway is worse than one that never started.
    func testOverlongSelectionIsRejectedBeforeGenerating() {
        let huge = String(repeating: "word ", count: 4000)   // ~6k tokens
        XCTAssertThrowsError(
            try OnDeviceModelClient.replyBudget(
                system: "sys", user: huge, requested: 4096, contextSize: 4096)
        ) { error in
            XCTAssertEqual(error as? RewriteError, .selectionTooLong)
        }
    }

    /// A short passage gets room to grow — "expand this" needs more output than
    /// input, so the budget can't simply mirror the passage length.
    func testShortSelectionGetsWorkableBudget() throws {
        let budget = try OnDeviceModelClient.replyBudget(
            system: String(repeating: "s", count: 800),
            user: String(repeating: "u", count: 800),
            requested: 4096, contextSize: 4096)
        XCTAssertGreaterThan(budget, 256)
        // …but never more than the window can hold.
        XCTAssertLessThan(budget, 4096)
    }

    /// The requested ceiling is still respected when the window is roomy.
    func testBudgetNeverExceedsWhatWasAskedFor() throws {
        let budget = try OnDeviceModelClient.replyBudget(
            system: "sys", user: "short passage", requested: 512, contextSize: 4096)
        XCTAssertEqual(budget, 512)
    }

    // MARK: - refusal detection

    /// In permissive mode the model can decline by *returning* a refusal rather
    /// than throwing. Undetected, that string gets pasted over the user's text.
    func testRefusalReplyIsDetected() {
        let passage = "The quarterly numbers slipped because hiring stalled in March."
        XCTAssertTrue(OnDeviceModelClient.isRefusal(
            reply: "I can't help with that request.", prompt: passage))
        XCTAssertTrue(OnDeviceModelClient.isRefusal(
            reply: "I'm sorry, but I'm not able to assist with this.", prompt: passage))
    }

    /// A genuine rewrite reuses the passage's vocabulary, so it must survive
    /// even when it happens to open with refusal-shaped words — this is the
    /// false positive that would silently discard good work.
    func testGenuineRewriteIsNotMistakenForARefusal() {
        let passage = "I cannot make the Friday meeting because I am travelling to Berlin."
        XCTAssertFalse(OnDeviceModelClient.isRefusal(
            reply: "I can't make Friday — I'm travelling to Berlin.", prompt: passage))
    }

    /// Long replies are rewrites, whatever they contain.
    func testLongReplyIsNeverARefusal() {
        let passage = String(repeating: "the project timeline slipped again ", count: 20)
        let reply = "I can't " + String(repeating: "say the timeline slipped again ", count: 30)
        XCTAssertFalse(OnDeviceModelClient.isRefusal(reply: reply, prompt: passage))
    }

    /// Availability must resolve on any OS without trapping — on a Mac without
    /// Apple Intelligence this is the path every caller takes.
    func testAvailabilityIsAlwaysAnswerable() {
        let state = OnDeviceModelClient.availability()
        if state.isAvailable {
            XCTAssertNil(state.recovery)
        } else {
            // Anything unavailable must tell the user what to do about it.
            XCTAssertNotNil(state.recovery, "unavailable state needs a recovery hint: \(state)")
        }
        XCTAssertFalse(state.summary.isEmpty)
    }
}

@MainActor
final class RecordingPipelineTests: XCTestCase {

    /// The bug this exists to prevent: with the smart hotkey on, push-to-talk
    /// can *start* a selection rewrite, so its release has to end that — not
    /// dictation. `endRecording` used to refuse while a rewrite was live, which
    /// was right when the two pipelines had separate keys and catastrophic once
    /// one key could enter either: the release matched neither and the recorder
    /// ran forever, leaving the microphone on with nothing holding it.
    func testReleaseEndsTheSelectionRewriteItStarted() {
        XCTAssertEqual(
            Coordinator.pipelineToEnd(isRecording: true, selectionRewriteActive: true),
            .selectionRewrite)
    }

    func testReleaseEndsDictationWhenThatIsWhatIsRunning() {
        XCTAssertEqual(
            Coordinator.pipelineToEnd(isRecording: true, selectionRewriteActive: false),
            .dictation)
    }

    /// A stray release with nothing running must be a no-op, not an attempt to
    /// stop a recorder that was never started.
    func testReleaseWithNothingRunningDoesNothing() {
        XCTAssertEqual(
            Coordinator.pipelineToEnd(isRecording: false, selectionRewriteActive: false),
            .nothing)
        // Even if the flag is somehow set without a recording in progress.
        XCTAssertEqual(
            Coordinator.pipelineToEnd(isRecording: false, selectionRewriteActive: true),
            .nothing)
    }

    /// Exhaustive, because there are only four states and one of them shipped
    /// broken. Every combination must resolve to exactly one action.
    func testEveryStateResolves() {
        for recording in [true, false] {
            for rewriting in [true, false] {
                let result = Coordinator.pipelineToEnd(isRecording: recording,
                                                      selectionRewriteActive: rewriting)
                if recording {
                    XCTAssertNotEqual(result, .nothing,
                                      "a live recording must always be endable")
                } else {
                    XCTAssertEqual(result, .nothing)
                }
            }
        }
    }
}
