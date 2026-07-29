import XCTest
@testable import Whisper

/// Fixed dates so ordering is deterministic.
private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: 86_400 * Double(n)) }

// Varied fixture text. The corpus deliberately drops near-duplicates, so
// samples have to differ the way real writing does — repeating one sentence
// with a changing number would all collapse into a single stored sample.
private let subjects = ["the migration", "our roadmap", "the billing service", "onboarding",
                        "the public API", "search relevance", "the mobile app", "weekly reporting"]
private let verbs = ["blocks", "slows down", "complicates", "quietly improves",
                     "replaces", "simplifies", "keeps breaking", "finally unblocks"]
private let objects = ["the release", "our timeline", "the support load", "customer trust",
                       "next quarter's budget", "the rollout plan", "the on-call rota", "our estimates"]
private let clauses = ["and nobody has owned it yet", "so we should decide this week",
                       "which is why the estimate slipped", "though the fix looks small",
                       "even after the last refactor", "unless we cut the scope",
                       "now that the contract is signed", "before anyone else notices"]

private func sentence(_ i: Int) -> String {
    "\(subjects[i % 8]) \(verbs[(i / 3) % 8]) \(objects[(i / 5) % 8]) \(clauses[(i / 7) % 8])"
}

/// One sentence — lands in `.brief`.
private func brief(_ i: Int) -> String { sentence(i * 3).prefix(1).uppercased() + sentence(i * 3).dropFirst() + "." }

/// ~50 words — lands in `.standard`.
private func paragraph(_ i: Int) -> String {
    (0..<4).map { sentence(i * 4 + $0) }.joined(separator: ". ") + "."
}

/// ~150 words — lands in `.extended`.
private func longForm(_ i: Int) -> String {
    (0..<12).map { sentence(i * 12 + $0) }.joined(separator: ". ") + "."
}

final class StyleCorpusTests: XCTestCase {

    // MARK: - readiness

    /// Three honest states, and rewriting is never blocked on any of them.
    func testReadinessProgressesThroughTheThreeStates() {
        var corpus = StyleCorpus()
        XCTAssertEqual(corpus.readiness, .generic)

        for i in 0..<6 { corpus.addSample(paragraph(i), source: .written, at: day(i)) }
        guard case .learning = corpus.readiness else {
            return XCTFail("expected learning, got \(corpus.readiness)")
        }

        // Volume alone isn't enough — one register is not a style.
        for i in 6..<30 { corpus.addSample(paragraph(i), source: .written, at: day(i)) }
        // Volume is there but variety isn't — and the label must say so rather
        // than showing a nonsense "30/25" count (audit finding #14).
        guard case .learning(_, _, let needsMoreVariety) = corpus.readiness else {
            return XCTFail("one register should still be learning, got \(corpus.readiness)")
        }
        XCTAssertTrue(needsMoreVariety)
        XCTAssertTrue(corpus.readiness.label.contains("similar length"),
                      "got: \(corpus.readiness.label)")

        for i in 0..<4 { corpus.addSample(longForm(i), source: .written, at: day(100 + i)) }
        XCTAssertEqual(corpus.readiness, .matched)
    }

    // MARK: - sampling

    /// Very short fragments say nothing about voice.
    func testTooShortSamplesAreIgnored() {
        var corpus = StyleCorpus()
        corpus.addSample("yes", source: .dictation)
        corpus.addSample("okay sure", source: .dictation)
        XCTAssertTrue(corpus.samples.isEmpty)
    }

    /// Saying the same thing twice shouldn't count twice.
    func testNearDuplicateSamplesAreNotStoredTwice() {
        var corpus = StyleCorpus()
        corpus.addSample("Can you send me that file when you get a chance", source: .dictation)
        corpus.addSample("Can you send me that file when you get a chance", source: .dictation)
        corpus.addSample("Can you send me that file when you get the chance", source: .dictation)
        XCTAssertEqual(corpus.samples.count, 1)
    }

    // MARK: - retrieval

    /// Three one-line dictations teach nothing about rewriting a long
    /// paragraph, and sending them anyway argues for the wrong rhythm.
    func testRetrievalPrefersSamplesOfTheSameShape() {
        var corpus = StyleCorpus()
        for i in 0..<5 { corpus.addSample(brief(i), source: .dictation, at: day(i)) }
        for i in 0..<5 { corpus.addSample(longForm(i), source: .written, at: day(10 + i)) }

        let retrieved = corpus.samples(for: longForm(99), limit: 3)
        XCTAssertEqual(retrieved.count, 3)
        XCTAssertTrue(retrieved.allSatisfy { $0.register == .extended },
                      "expected long-form samples, got \(retrieved.map(\.register))")
    }

    /// Audit follow-up: off-register samples argue for the wrong rhythm, so a
    /// thin same-register set is not padded out with wrong-shaped ones.
    func testRetrievalDoesNotPadWithWrongShapedSamples() {
        var corpus = StyleCorpus()
        for i in 0..<8 { corpus.addSample(brief(i), source: .dictation, at: day(i)) }
        corpus.addSample(longForm(0), source: .written, at: day(20))

        let retrieved = corpus.samples(for: longForm(99), limit: 3)
        XCTAssertEqual(retrieved.count, 1)
        XCTAssertEqual(retrieved.first?.register, .extended)
    }

    /// Below the floor there's nothing worth sending — better generic prose
    /// than a voice extrapolated from two lines.
    func testRetrievalReturnsNothingWhileGeneric() {
        var corpus = StyleCorpus()
        corpus.addSample(paragraph(0), source: .written)
        XCTAssertTrue(corpus.samples(for: paragraph(99)).isEmpty)
    }

    /// The same corpus must always build the same prompt.
    func testRetrievalIsDeterministic() {
        var corpus = StyleCorpus()
        for i in 0..<12 { corpus.addSample(paragraph(i), source: .written, at: day(i)) }
        let first = corpus.samples(for: paragraph(99)).map(\.text)
        let second = corpus.samples(for: paragraph(99)).map(\.text)
        XCTAssertEqual(first, second)
    }

    // MARK: - classifying a selection

    /// The key distinction the whole correction signal rests on.
    func testSelectionIsClassifiedAgainstWhatWePasted() {
        var corpus = StyleCorpus()
        let produced = "The plan is simple, we ship on Friday and tell the team afterwards."
        corpus.noteProduced(produced, at: day(1))

        // Untouched: ours, so it must not become a "sample of their voice".
        XCTAssertEqual(corpus.classify(produced, now: day(2)), .unchangedOutput)

        // Edited: the difference is the signal.
        let edited = "The plan is simple: we ship Friday and tell the team afterwards."
        XCTAssertEqual(corpus.classify(edited, now: day(2)), .editedOutput(produced: produced))

        // Unrelated text is their own writing.
        XCTAssertEqual(
            corpus.classify("A completely different sentence about other matters entirely.",
                            now: day(2)),
            .userWriting)
    }

    /// An output nobody edited for weeks was accepted as-is; a much later
    /// selection isn't evidence about it.
    func testStaleOutputsStopBeingCandidates() {
        var corpus = StyleCorpus()
        let produced = "The plan is simple, we ship on Friday and tell the team afterwards."
        corpus.noteProduced(produced, at: day(1))
        XCTAssertEqual(corpus.classify(produced, now: day(60)), .userWriting)
    }

    /// One edit is one correction, however often that text is selected later.
    func testConsumingAPendingOutputStopsItRecurring() {
        var corpus = StyleCorpus()
        let produced = "The plan is simple, we ship on Friday and tell the team afterwards."
        corpus.noteProduced(produced, at: day(1))
        corpus.consumePendingOutput(produced)
        XCTAssertEqual(corpus.classify(produced, now: day(2)), .userWriting)
    }
}

final class TextSimilarityTests: XCTestCase {

    func testIdenticalTextScoresOne() {
        XCTAssertEqual(TextSimilarity.ratio("the same words here", "the same words here"), 1.0)
    }

    /// Re-punctuating is an edit, not a different text.
    func testPunctuationAndCaseAreIgnored() {
        XCTAssertEqual(TextSimilarity.ratio("Ship it, now.", "ship it now"), 1.0)
    }

    func testUnrelatedTextScoresLow() {
        XCTAssertLessThan(
            TextSimilarity.ratio("the quick brown fox jumps", "entirely different subject matter"),
            0.3)
    }

    /// A small edit to a paragraph has to stay well inside the "edited" band.
    func testSmallEditStaysRecognizable() {
        let a = "We should ship this on Friday and let the whole team know about it afterwards"
        let b = "We should ship this on Friday and tell the whole team about it afterwards"
        let score = TextSimilarity.ratio(a, b)
        XCTAssertGreaterThan(score, StyleCorpus.editedThreshold)
        XCTAssertLessThan(score, StyleCorpus.unchangedThreshold)
    }
}

final class StyleMinerTests: XCTestCase {

    private var emptyProfile: StyleProfile {
        StyleProfile(voice: .init(), prompted: .init(), enforced: .init())
    }

    /// Whisper chooses the punctuation in a dictation transcript, not the user.
    /// Mining punctuation from it would manufacture rules out of the
    /// transcriber's habits.
    func testPunctuationIsNotMinedFromDictationTranscripts() {
        var corpus = StyleCorpus()
        for i in 0..<40 {
            corpus.addSample(paragraph(i), source: .dictation, at: day(i))
        }
        XCTAssertTrue(StyleMiner.proposals(from: corpus, profile: emptyProfile).isEmpty)
    }

    /// The same evidence, from text the user actually typed, does yield a rule.
    func testEmDashRuleIsProposedFromWrittenSamples() {
        var corpus = StyleCorpus()
        for i in 0..<15 {
            corpus.addSample(paragraph(i), source: .written, at: day(i))
        }
        let proposals = StyleMiner.proposals(from: corpus, profile: emptyProfile)
        guard let emDash = proposals.first(where: {
            $0.kind == .substitution(find: "\u{2014}", replace: ", ")
        }) else {
            return XCTFail("expected an em dash proposal, got \(proposals.map(\.id))")
        }
        XCTAssertTrue(emDash.evidence.contains("15"), "evidence should carry the count")
    }

    /// A user who does use em dashes must never be told they don't.
    func testNoRuleWhenTheEvidenceIsNotOneSided() {
        var corpus = StyleCorpus()
        for i in 0..<15 {
            let text = i == 7 ? paragraph(i) + " \u{2014} and more"
                              : paragraph(i)
            corpus.addSample(text, source: .written, at: day(i))
        }
        let proposals = StyleMiner.proposals(from: corpus, profile: emptyProfile)
        XCTAssertFalse(proposals.contains { $0.id == "sub:\u{2014}" })
    }

    /// Rules already in style.json aren't offered again.
    func testExistingRulesAreNotReProposed() {
        var corpus = StyleCorpus()
        for i in 0..<15 {
            corpus.addSample(paragraph(i), source: .written, at: day(i))
        }
        let profile = StyleProfile(
            voice: .init(), prompted: .init(),
            enforced: .init(substitutions: [.init(find: "\u{2014}", replace: ", ")],
                            straightenQuotes: true))
        XCTAssertFalse(StyleMiner.proposals(from: corpus, profile: profile)
            .contains { $0.id == "sub:\u{2014}" || $0.id == "quotes" })
    }

    /// A word repeatedly cut from our rewrites, that the user never writes
    /// themselves, is a banned-word candidate.
    func testRepeatedlyRemovedWordIsProposed() {
        var corpus = StyleCorpus()
        for i in 0..<4 {
            corpus.addCorrection(
                produced: "We should leverage the new tooling for this workstream \(i)",
                corrected: "We should use the new tooling for this workstream \(i)",
                at: day(i))
        }
        let proposals = StyleMiner.proposals(from: corpus, profile: emptyProfile)
        XCTAssertTrue(proposals.contains { $0.kind == .bannedWord("leverage") },
                      "got \(proposals.map(\.id))")
    }

    /// One edit is not a rule.
    func testASingleRemovalIsNotEnough() {
        var corpus = StyleCorpus()
        corpus.addCorrection(produced: "We should leverage the tooling",
                             corrected: "We should use the tooling", at: day(1))
        XCTAssertFalse(StyleMiner.proposals(from: corpus, profile: emptyProfile)
            .contains { $0.kind == .bannedWord("leverage") })
    }

    /// If they use the word themselves, cutting it from our output was a
    /// judgement call about that sentence, not a blanket ban.
    func testWordTheUserWritesThemselvesIsNotBanned() {
        var corpus = StyleCorpus()
        for i in 0..<4 {
            corpus.addCorrection(
                produced: "We should leverage the new tooling for this workstream \(i)",
                corrected: "We should use the new tooling for this workstream \(i)",
                at: day(i))
        }
        corpus.addSample("I do sometimes leverage that library when it makes sense to",
                         source: .written, at: day(20))
        XCTAssertFalse(StyleMiner.proposals(from: corpus, profile: emptyProfile)
            .contains { $0.kind == .bannedWord("leverage") })
    }

    /// Banning a common word would be a disaster.
    func testStopWordsAreNeverProposed() {
        var corpus = StyleCorpus()
        for i in 0..<5 {
            corpus.addCorrection(produced: "This is the thing that we should do now \(i)",
                                 corrected: "We should do it now \(i)", at: day(i))
        }
        let banned = StyleMiner.proposals(from: corpus, profile: emptyProfile).compactMap { p -> String? in
            if case .bannedWord(let w) = p.kind { return w }
            return nil
        }
        XCTAssertFalse(banned.contains("that"))
        XCTAssertFalse(banned.contains("this"))
    }
}

final class StyleProposalApplicationTests: XCTestCase {

    /// Accepting a rule writes it into style.json, and the file still parses.
    func testAcceptedProposalRoundTripsThroughTheConfig() throws {
        let profile = StyleProfile(voice: .init(description: "Terse.", samples: ["A sample."]),
                                   prompted: .init(guidance: ["Lead with the point."]),
                                   enforced: .init(maxWords: 200))
        let updated = profile.applying(
            StyleProposal(kind: .substitution(find: "\u{2014}", replace: ", "), evidence: ""))
        let reloaded = try StyleProfile.decode(try updated.encoded())

        XCTAssertEqual(reloaded.enforced.substitutions,
                       [.init(find: "\u{2014}", replace: ", ")])
        // Nothing else may be lost in the round trip.
        XCTAssertEqual(reloaded.voice.description, "Terse.")
        XCTAssertEqual(reloaded.voice.samples, ["A sample."])
        XCTAssertEqual(reloaded.prompted.guidance, ["Lead with the point."])
        XCTAssertEqual(reloaded.enforced.maxWords, 200)
    }

    /// Supplying a replacement moves a banned word from the tier that costs a
    /// retry into the one fixed in code.
    func testReplacementUpgradesABannedWordToRepairable() throws {
        let profile = StyleProfile(voice: .init(), prompted: .init(), enforced: .init())
        let proposal = StyleProposal(kind: .bannedWord("leverage"), evidence: "")

        let without = profile.applying(proposal, replacement: nil)
        XCTAssertNil(without.enforced.bannedWords.first?.replacement)
        XCTAssertFalse(StyleEnforcer.apply("We leverage it.", style: without.enforced).isCompliant)

        let with = profile.applying(proposal, replacement: "use")
        let repaired = StyleEnforcer.apply("We leverage it.", style: with.enforced)
        XCTAssertEqual(repaired.text, "We use it.")
        XCTAssertTrue(repaired.isCompliant)
    }

    /// Accepting the same rule twice must not duplicate it.
    func testApplyingTwiceIsIdempotent() {
        let proposal = StyleProposal(kind: .substitution(find: "\u{2014}", replace: ", "),
                                     evidence: "")
        let once = StyleProfile(voice: .init(), prompted: .init(), enforced: .init())
            .applying(proposal)
        XCTAssertEqual(once.applying(proposal).enforced.substitutions.count, 1)
    }
}

final class ResolvedStyleTests: XCTestCase {

    /// Hand-written and learned samples are shown together — the user doesn't
    /// distinguish them, and the model shouldn't weight them differently.
    func testLearnedSamplesJoinHandWrittenOnesInThePrompt() {
        let style = ResolvedStyle(
            profile: StyleProfile(voice: .init(description: "", samples: ["Hand written one."]),
                                  prompted: .init(), enforced: .init()),
            learnedSamples: ["Learned from dictation."])
        let prompt = SelectionRewriter.systemPrompt(style: style)

        XCTAssertTrue(prompt.contains("Hand written one."))
        XCTAssertTrue(prompt.contains("Learned from dictation."))
    }

    /// The correction pairs are the strongest signal available, so they have to
    /// reach the prompt as before/after, not as more prose samples.
    func testCorrectionsAppearAsBeforeAndAfter() {
        let style = ResolvedStyle(
            profile: StyleProfile(voice: .init(), prompted: .init(), enforced: .init()),
            corrections: [CorrectionPair(produced: "We should leverage it.",
                                         corrected: "We should use it.",
                                         addedAt: day(1))])
        let prompt = SelectionRewriter.systemPrompt(style: style)

        XCTAssertTrue(prompt.contains("We should leverage it."))
        XCTAssertTrue(prompt.contains("We should use it."))
        XCTAssertTrue(prompt.contains("<you_wrote>"))
        XCTAssertTrue(prompt.contains("<they_changed_it_to>"))
    }

    /// Day one: no corpus, no learned sections, and the rewrite still works.
    func testGenericStyleAddsNothingToThePrompt() {
        let style = ResolvedStyle(
            profile: StyleProfile(voice: .init(), prompted: .init(), enforced: .init()))
        let prompt = SelectionRewriter.systemPrompt(style: style)

        XCTAssertFalse(prompt.contains("<sample 1>"))
        XCTAssertFalse(prompt.contains("<you_wrote>"))
        XCTAssertTrue(prompt.contains("Never invent facts"))
    }
}

/// Fixture with a base profile and two templates, exercising both merge rules.
private let templatedConfig = """
{
  "voice": { "description": "Terse.", "samples": ["Base sample."] },
  "prompted": { "guidance": ["Lead with the point."] },
  "enforced": {
    "bannedWords": [{ "word": "delve" }],
    "straightenQuotes": true,
    "maxWords": 500
  },
  "templates": {
    "email": {
      "voice": { "description": "Warmer, still brief." },
      "prompted": { "guidance": ["Open with the ask."] },
      "enforced": { "maxWords": 150, "bannedWords": [{ "word": "circle back" }] }
    },
    "slack": {
      "voice": { "samples": ["yeah that works, shipping it now"] },
      "enforced": { "straightenQuotes": false }
    }
  },
  "defaultTemplate": "email"
}
"""

final class StyleConfigTests: XCTestCase {

    private func config(_ json: String = templatedConfig) throws -> StyleConfig {
        try StyleConfig.decode(Data(json.utf8))
    }

    /// A file with no templates is exactly what every existing config is, and
    /// must keep working untouched.
    func testConfigWithoutTemplatesIsJustTheBase() throws {
        let c = try config("""
        { "voice": { "description": "Terse." }, "enforced": { "maxWords": 200 } }
        """)
        XCTAssertTrue(c.templateNames.isEmpty)
        XCTAssertNil(c.defaultTemplate)
        XCTAssertEqual(c.defaultProfile.voice.description, "Terse.")
        XCTAssertEqual(c.defaultProfile.enforced.maxWords, 200)
    }

    /// The merge rule: lists add to the base, scalars replace it. A word banned
    /// at the base stays banned inside every template.
    func testTemplateAddsToListsAndOverridesScalars() throws {
        let email = try config().profile(named: "email")

        // Scalars replaced.
        XCTAssertEqual(email.voice.description, "Warmer, still brief.")
        XCTAssertEqual(email.enforced.maxWords, 150)
        // Lists added to — the base rule survives alongside the template's.
        XCTAssertEqual(email.prompted.guidance, ["Lead with the point.", "Open with the ask."])
        XCTAssertEqual(email.enforced.bannedWords.map(\.word), ["delve", "circle back"])
        // Untouched by this template, so inherited.
        XCTAssertEqual(email.voice.samples, ["Base sample."])
        XCTAssertTrue(email.enforced.straightenQuotes)
    }

    /// A template can turn a base rule off, not just add to it.
    func testTemplateCanDisableABaseRule() throws {
        XCTAssertFalse(try config().profile(named: "slack").enforced.straightenQuotes)
    }

    /// Samples are replaced rather than appended — a template's voice is its
    /// own, not the base voice with extras.
    func testTemplateSamplesReplaceRatherThanAppend() throws {
        XCTAssertEqual(try config().profile(named: "slack").voice.samples,
                       ["yeah that works, shipping it now"])
    }

    func testDefaultTemplateIsApplied() throws {
        XCTAssertEqual(try config().defaultProfile.enforced.maxWords, 150)
    }

    /// A misheard template name shouldn't cost the user their rewrite.
    func testUnknownTemplateFallsBackToTheBase() throws {
        XCTAssertEqual(try config().profile(named: "carrier pigeon").enforced.maxWords, 500)
    }

    func testTemplateLookupIsCaseInsensitive() throws {
        XCTAssertEqual(try config().profile(named: "EMAIL").enforced.maxWords, 150)
    }

    /// Strictness has to reach inside templates too, or a typo there is exactly
    /// the silently-inactive rule the whole config refuses to have.
    func testTypoInsideATemplateIsAHardError() {
        XCTAssertThrowsError(try config("""
        { "templates": { "email": { "enforced": { "maxWord": 150 } } } }
        """)) { error in
            guard case StyleProfileError.unknownKey(let path, let suggestion) = error else {
                return XCTFail("expected unknownKey, got \(error)")
            }
            XCTAssertEqual(path, "templates.email.enforced.maxWord")
            XCTAssertEqual(suggestion, "maxWords")
        }
    }

    /// Pointing the default at a template that doesn't exist would silently use
    /// the base instead — the same class of failure as a misspelled rule.
    func testDefaultNamingAMissingTemplateIsRejected() {
        XCTAssertThrowsError(try config("""
        { "templates": { "email": {} }, "defaultTemplate": "slack" }
        """)) { error in
            guard case StyleProfileError.invalidValue(let path, _) = error else {
                return XCTFail("expected invalidValue, got \(error)")
            }
            XCTAssertEqual(path, "defaultTemplate")
        }
    }

    /// Accepting a mined rule rewrites the file, so templates must survive it.
    func testTemplatesSurviveARoundTrip() throws {
        let reloaded = try StyleConfig.decode(try config().encoded())
        XCTAssertEqual(reloaded.templateNames, ["email", "slack"])
        XCTAssertEqual(reloaded.defaultTemplate, "email")
        XCTAssertEqual(reloaded.profile(named: "email").enforced.maxWords, 150)
        XCTAssertFalse(reloaded.profile(named: "slack").enforced.straightenQuotes)
        XCTAssertEqual(reloaded.base.enforced.maxWords, 500)
    }

    /// Template order must be stable, or the Settings picker reshuffles between
    /// launches — JSON objects have no inherent ordering.
    func testTemplateOrderIsStable() throws {
        XCTAssertEqual(try config().templateNames, try config().templateNames)
        XCTAssertEqual(try config().templateNames, ["email", "slack"])
    }
}

final class TemplateCommandTests: XCTestCase {

    private let templates = ["email", "slack", "formal email"]

    /// Naming a template picks it for one rewrite, and the rest of the command
    /// still reads as an instruction.
    func testTemplateIsExtractedAndInstructionSurvives() {
        let command = CommandNormalizer.normalize("make it shorter as an email",
                                                  templates: templates)
        XCTAssertEqual(command.template, "email")
        XCTAssertEqual(command.intent, .shorten)
    }

    /// "style it" on its own is a plain rewrite under the default template.
    func testStyleItIsARewriteWithNoTemplate() {
        let command = CommandNormalizer.normalize("style it", templates: templates)
        XCTAssertNil(command.template)
        XCTAssertEqual(command.intent, .rewrite)
    }

    func testStyleItAsATemplate() {
        let command = CommandNormalizer.normalize("style it as a slack message",
                                                  templates: templates)
        XCTAssertEqual(command.template, "slack")
    }

    /// The longer name has to win, or "formal email" would match "email" and
    /// silently pick the wrong template.
    func testLongestTemplateNameWins() {
        XCTAssertEqual(
            CommandNormalizer.normalize("as a formal email", templates: templates).template,
            "formal email")
    }

    /// No templates configured means nothing to extract — the words stay part
    /// of the instruction.
    func testNoTemplatesConfiguredLeavesTheCommandAlone() {
        let command = CommandNormalizer.normalize("make it shorter as an email", templates: [])
        XCTAssertNil(command.template)
        XCTAssertEqual(command.intent, .shorten)
    }
}
