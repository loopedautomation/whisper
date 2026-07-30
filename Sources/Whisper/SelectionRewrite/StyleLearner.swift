import Foundation
import AppKit
import Combine

/// Accumulates evidence about how the user writes, and turns it into better
/// rewrites over time.
///
/// Two kinds of signal, both collected from work the user was doing anyway:
/// their own writing (dictation transcripts, and any selection that isn't
/// something we produced), and their edits to rewrites we pasted. Nothing here
/// changes behaviour on its own — samples flow into the prompt, and mined rules
/// are only ever *proposed*.
///
/// Everything stays on this machine, in readable JSON next to `style.json`.
@MainActor
final class StyleLearner: ObservableObject {
    @Published private(set) var corpus = StyleCorpus()
    /// Rules mined from the corpus, awaiting the user's decision.
    @Published private(set) var proposals: [StyleProposal] = []

    let fileURL = AppPaths.styleCorpusFile

    /// Harvesting is on by default; this switches off collection entirely
    /// without discarding what's already been learned.
    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: PrefKey.styleLearningEnabled)
    }

    var readiness: StyleReadiness {
        // With collection off, whatever is stored still gets used — turning off
        // learning shouldn't silently downgrade rewrites that already work.
        corpus.readiness
    }

    init() { load() }

    // MARK: - harvesting

    /// A dictation transcript: the user's words, but the transcriber's
    /// punctuation — recorded as such so punctuation mining ignores it.
    ///
    /// Takes the *raw* transcript deliberately. The LLM-cleaned version is the
    /// model's prose, and feeding it back would teach the app to imitate itself.
    /// `language` is what transcription already determined for this recording;
    /// passing it avoids re-detecting, and is more reliable than detection on a
    /// short transcript.
    func harvestDictation(_ rawTranscript: String, language: String? = nil) {
        guard isEnabled else { return }
        corpus.addSample(rawTranscript, source: .dictation, language: language)
        save()
    }

    /// A freshly captured selection, before it's rewritten. Either the user's
    /// own writing, or a rewrite of ours they've since edited.
    func noteSelection(_ selection: String) {
        guard isEnabled else { return }
        switch corpus.classify(selection) {
        case .userWriting:
            corpus.addSample(selection, source: .written)
        case .unchangedOutput:
            // Ours, untouched. Not evidence of anything.
            break
        case .editedOutput(let produced):
            corpus.addCorrection(produced: produced, corrected: selection)
            corpus.consumePendingOutput(produced)
        }
        save()
    }

    /// A rewrite the app just pasted. Remembered so a later selection can be
    /// recognized as an edited version of it.
    func noteProduced(_ text: String) {
        guard isEnabled else { return }
        corpus.noteProduced(text)
        save()
    }

    // MARK: - using what's been learned

    /// Style for one specific passage: the hand-written profile plus whatever
    /// the corpus can contribute for text of this shape.
    func resolve(_ profile: StyleProfile, for passage: String) -> ResolvedStyle {
        // Readiness reported for *this passage's* language, not the corpus at
        // large: rewriting German with an English-only corpus is generic, and
        // saying otherwise would claim a voice match that isn't happening.
        ResolvedStyle(
            profile: profile,
            learnedSamples: corpus.samples(for: passage).map(\.text),
            corrections: corpus.recentCorrections(),
            readiness: corpus.readiness(in: LanguageDetector.detect(passage)))
    }

    /// Readiness for a specific language, for the Settings breakdown.
    func readiness(in language: String?) -> StyleReadiness { corpus.readiness(in: language) }

    // MARK: - proposals

    func refreshProposals(profile: StyleProfile?) {
        guard let profile else { proposals = []; return }
        let dismissed = dismissedProposalIDs
        proposals = StyleMiner.proposals(from: corpus, profile: profile)
            .filter { !dismissed.contains($0.id) }
    }

    /// Stops a proposal being offered again after the user declines it.
    func dismissProposal(_ proposal: StyleProposal) {
        proposals.removeAll { $0.id == proposal.id }
        var dismissed = Set(UserDefaults.standard.stringArray(forKey: PrefKey.dismissedStyleProposals) ?? [])
        dismissed.insert(proposal.id)
        UserDefaults.standard.set(Array(dismissed), forKey: PrefKey.dismissedStyleProposals)
    }

    var dismissedProposalIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: PrefKey.dismissedStyleProposals) ?? [])
    }

    // MARK: - the user's data, on their terms

    func forgetEverything() {
        corpus = StyleCorpus()
        proposals = []
        save()
    }

    func forgetSample(_ sample: StyleSample) {
        corpus.samples.removeAll { $0 == sample }
        save()
    }

    func forgetCorrection(_ correction: CorrectionPair) {
        corpus.corrections.removeAll { $0 == correction }
        save()
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    // MARK: - persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // A corrupt corpus is recoverable — it's derived data, so starting over
        // costs the user some accumulated learning but nothing irreplaceable.
        // This is exactly the opposite of style.json, where a parse failure has
        // to be loud because those are rules the user wrote by hand.
        guard var decoded = try? decoder.decode(StyleCorpus.self, from: data) else { return }
        // Samples stored before languages were recorded have none; fill them in
        // once so retrieval can filter properly from here on.
        let backfilled = decoded.backfillLanguages()
        corpus = decoded
        if backfilled { save() }
    }

    /// Serializes and writes off the main actor. The corpus reaches a megabyte
    /// or so, and this runs after every dictation and every rewrite — doing it
    /// inline stutters the paste that immediately follows.
    private func save() {
        let snapshot = corpus
        let url = fileURL
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// The style handed to a single rewrite: the hand-written profile, plus the
/// samples and corrections retrieval picked for this particular passage.
struct ResolvedStyle: Equatable {
    var profile: StyleProfile
    /// Samples from the corpus, chosen to match the passage's shape.
    var learnedSamples: [String] = []
    var corrections: [CorrectionPair] = []
    var readiness: StyleReadiness = .generic

    /// A profile with no learned material — what a rewrite looks like on day
    /// one, and what the tests use when they only care about enforcement.
    init(profile: StyleProfile,
         learnedSamples: [String] = [],
         corrections: [CorrectionPair] = [],
         readiness: StyleReadiness = .generic) {
        self.profile = profile
        self.learnedSamples = learnedSamples
        self.corrections = corrections
        self.readiness = readiness
    }
}
