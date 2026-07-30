import AppKit

/// Decides whether the user has text selected, so one hotkey can rewrite a
/// selection or dictate when there isn't one.
///
/// Getting this wrong destroys text in **both** directions, which is why it
/// asks the Accessibility API rather than guessing:
///
/// - A false "selected" means a dictation is treated as a rewrite: the user
///   speaks a sentence expecting it typed, and instead something elsewhere is
///   rewritten.
/// - A false "not selected" means the selected paragraph is replaced by the
///   literal words they just spoke.
///
/// So the answer is three-valued. `.unknown` — the honest result for apps whose
/// AX tree doesn't expose selection — is never silently collapsed into either
/// certainty; the caller decides what to do with a shrug.
@MainActor
enum SelectionProbe {

    enum Result: Equatable {
        /// Text is definitely selected, and here it is. No clipboard involved.
        case selected(String)
        /// Definitely nothing selected — dictation is what the user wants.
        case none
        /// Couldn't tell. The AX tree is absent, disabled, or doesn't report
        /// selection (Electron apps, mostly).
        case unknown
    }

    /// Asks the frontmost app what's selected. Cheap and non-destructive —
    /// safe to call on every hotkey press.
    static func probe() -> Result {
        guard let text = FocusInspector.selectedText() else { return .unknown }
        // An empty string here is a real answer: the attribute exists and says
        // nothing is selected.
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .none
            : .selected(text)
    }

    /// What the smart hotkey should do, given the probe and how the user wants
    /// ambiguity resolved.
    ///
    /// `.unknown` is the whole reason this is a separate decision: in an app
    /// that won't say, we have to pick a default, and the safe pick depends on
    /// which mistake the user would rather absorb.
    static func decide(_ result: Result, whenUnknown fallback: SmartHotkeyFallback) -> Action {
        switch result {
        case .selected(let text): return .rewrite(text)
        case .none: return .dictate
        case .unknown:
            switch fallback {
            case .dictate: return .dictate
            // Confirming by ⌘C costs a moment but can't guess wrong: if the
            // copy yields nothing, there was nothing selected.
            case .confirmByCopying: return .rewriteIfCopyFindsText
            }
        }
    }

    enum Action: Equatable {
        /// Selection already in hand — no ⌘C needed, so the clipboard is left
        /// alone entirely.
        case rewrite(String)
        case dictate
        /// Fall back to the clipboard probe to settle it.
        case rewriteIfCopyFindsText
    }
}

/// How to resolve an app that won't report its selection.
enum SmartHotkeyFallback: String, CaseIterable, Identifiable {
    /// Treat unknown as "nothing selected" and dictate. Never rewrites the
    /// wrong thing, but silently won't rewrite in Electron apps.
    case dictate
    /// Try ⌘C and rewrite only if it produces text. Reliable, at the cost of
    /// putting the selection on the clipboard.
    case confirmByCopying

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dictate: return "Dictate (never rewrites by mistake)"
        case .confirmByCopying: return "Check by copying (works in more apps)"
        }
    }
}
