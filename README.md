# Looped Whisper

A free, open-source, **Mac-only** voice transcription utility for developers. It
runs **local open-source Whisper models** (bring your own model) — no cloud
transcription. It lives in the menu bar, is driven by global hotkeys, and the
transcribed text is copied to the clipboard and pasted at your cursor.

> Apple Silicon, macOS 14+. Transcription is powered by
> [WhisperKit](https://github.com/argmaxinc/WhisperKit) (CoreML).

## Features

- 🎙️ **Local transcription** — Whisper models run on-device via WhisperKit; works
  offline after the model is downloaded.
- 🧠 **Bring your own model** — pick tiny → large-v3; auto-downloaded & cached.
- ⌨️ **Global hotkeys** — push-to-talk (hold) and start/stop toggle, configurable.
- 🌐 **fn / Globe key support** — hold-to-talk or double-tap-to-toggle (see caveats).
- 📋 **Auto clipboard + paste** at the cursor.
- ⚡ **Realtime mode** — live caption as you speak.
- ✨ **LLM cleanup** — optionally fix typos/punctuation via an Anthropic
  or OpenAI-compatible API key (stored in Keychain).
- 📖 **Vocabulary** — bias recognition toward your names / jargon / identifiers.
- ✍️ **Rewrite my selection** — select text anywhere, hold a hotkey, say what you
  want ("make it shorter", "fix the typos"), and it's replaced in place in your
  own writing style. See [Rewrite my selection](#rewrite-my-selection).
- 🎯 **Learns your voice** — picks up how you write from your dictation and your
  edits, and suggests style rules once the evidence is there. Stays local.
- 🔒 Launch at login, menu-bar agent (no Dock icon).

## Install

Apple Silicon, macOS 14+. Install with Homebrew:

```bash
brew install --cask loopedautomation/tap/looped-whisper
```

Or download the notarized **`.dmg`** from the [Releases](https://github.com/loopedautomation/whisper/releases) page and drag the app into Applications.

## Build & run

```bash
# Build a runnable .app bundle (handles SPM deps: WhisperKit, KeyboardShortcuts)
make build            # or: ./scripts/build-app.sh release
open build/LoopedWhisper.app

# Or run with logs in the terminal:
./build/LoopedWhisper.app/Contents/MacOS/LoopedWhisper
```

First launch:

1. Grant **Microphone** when prompted, and **Accessibility** (for paste).
   Grant **Input Monitoring** only if you want the fn/Globe hotkey.
   All are in **Settings → Permissions**.
2. In **Settings → Model**, pick a model (`tiny`/`base` are fastest). The first
   use downloads the model.
3. In **Settings → Hotkeys**, set your push-to-talk and toggle shortcuts.

### fn / Globe key

The fn/Globe key can't be a normal registered hotkey, so it's handled by a
passive event tap (needs Input Monitoring). macOS maps **double-tap fn** to
Dictation by default — set _System Settings → Keyboard → "Press 🌐 to" → Do
Nothing_ to avoid conflicts. Some non-Apple keyboards don't emit an fn event;
keep a standard shortcut as a fallback.

## LLM rewrite

In **Settings → Rewrite**, enable cleanup, choose Anthropic (default, e.g.
`claude-haiku-4-5-20251001`) or any OpenAI-compatible endpoint, and paste an
API key. The key is stored in the macOS Keychain. On any API error or timeout
the raw transcript is used instead.

## Rewrite my selection

Select text in any app, hold **⌃⌥E**, say what you want, and release. The
selection is replaced in place with a rewrite in your own writing style.

```
select text  →  hold ⌃⌥E, say "make it shorter"  →  release  →  text is replaced
```

Spoken commands are transcribed locally by the same Whisper model as dictation,
so transcript noise is expected and handled: _"um, could you make this shorter
please"_ and _"shorter"_ land on the same intent. Anything unrecognized is passed
through to the model verbatim, so _"make it sound like a pirate"_ works too.

No microphone? **Menu bar → Rewrite Selection…** takes the same instruction as
typed text and runs the identical pipeline.

### How it reads your selection

Nothing portable can read another app's selection, so this works by pressing
**⌘C**, reading the clipboard, rewriting, writing the clipboard, and pressing
**⌘V**. Two consequences worth knowing:

- **Your clipboard ends up holding the rewrite.** Unavoidable on this route.
- It needs **Accessibility** permission, like auto-paste.
- **Don't clear the selection while it's thinking.** The paste lands on whatever
  is selected when it arrives. The app pins the target window when you press the
  shortcut and re-activates it before pasting, so switching apps meanwhile is
  handled — but if you clear the selection itself, the rewrite is inserted at the
  cursor instead of replacing anything.
- **Very long selections** are sized a token budget to match. If a rewrite still
  comes back cut off, you're told and nothing is pasted, rather than having the
  tail of your text silently replaced with a truncated version.

If nothing is selected, ⌘C is a no-op and you get "No text selected" rather
than a rewrite of whatever happened to be on your clipboard.

### Your style, in `style.json`

Edit it once at `~/Library/Application Support/Looped Whisper/style.json`
(**Settings → Style → Reveal**). A starter file is created on first launch.

```jsonc
{
  "voice": {
    "description": "Terse. Short sentences. No hedging.",
    "samples": ["A paragraph of your actual writing, to match the voice against."]
  },
  "prompted": {
    "guidance": ["Lead with the point, then the reasoning."]
  },
  "enforced": {
    "substitutions": [{ "find": "—", "replace": ", " }],
    "straightenQuotes": true,
    "bannedWords": [
      { "word": "leverage", "replacement": "use" },
      { "word": "delve" }
    ],
    "maxWords": 200
  }
}
```

**A misspelled rule name is a hard error, not a silent no-op.** `bannedWord`
instead of `bannedWords` refuses to load and tells you which key it didn't
recognize (with the nearest match). Rewriting stays disabled until the file
parses — a rule you believe is on but isn't is the failure you'd never catch.

### Prompted vs. enforced

The split is the point. A model told "never use an em dash" still produces one
now and then — not often, but often enough that the feature feels broken,
because an em dash is exactly the thing you notice. So `enforced` rules are
handled in code after the model replies, in two tiers:

| Rule | Tier | What happens |
| --- | --- | --- |
| `substitutions`, `straightenQuotes`, `bannedWords` **with** a `replacement` | Repairable | Applied in code. No extra model call, cannot fail. |
| `maxWords`, `bannedWords` **without** a `replacement` | Unrepairable | Can't be fixed without deciding what the text means, so it goes back to the model **once**, naming the breach exactly: _"the rewrite is 240 words; the limit is 200"_. |

If it still won't comply, you get the best attempt **plus** a visible error
listing every rule that didn't hold. A rule you asked for is never silently
dropped.

Two more things happen on every reply: the model is forbidden from inventing
facts, names, numbers, or dates that weren't in the original, and any packaging
it wraps around the answer (code fences, "Here's the rewritten text:",
surrounding quotes) is stripped before anything reaches your document.

### It learns your voice as you use it

`style.json` is the half you write. The other half the app works out for itself,
from writing you were doing anyway.

**Three states**, shown in the menu bar and in **Settings → Style**. Rewriting
always works — it just tells you which one it's in:

| State | What it means |
| --- | --- |
| **Generic** | Nothing learned yet. Rewrites run on `style.json` alone. |
| **Learning** | Samples accumulating, already used where they fit the passage. |
| **Matching your style** | Enough writing, across enough shapes, to match you. |

There's no locked door on first launch, and no progress bar to wait out. The
gate would also be self-defeating: the most valuable signal — your edits to
rewrites — can only appear once rewrites are happening.

**Two signals, both free.** Every dictation transcript is you writing, and so is
any selection that isn't something the app produced. And because the app
remembers what it pasted, a selection that fuzzy-matches an earlier rewrite is
recognized as *that rewrite after you edited it* — the difference is a direct
statement of what you actually wanted, worth far more than raw samples. No
feedback buttons, no thumbs up or down.

Retrieval sends the two or three samples closest to the passage in shape, not a
fixed set: three one-line dictations teach nothing about rewriting a long
paragraph, and sending them anyway argues for the wrong rhythm.

**Mined rules are proposed, never switched on.** Once there's enough evidence,
"you have never once used an em dash in 40 things you wrote" becomes a suggested
rule in the Style tab, with the count behind it. One click writes it into
`style.json` where you can read it. A rule that enabled itself would be the same
failure as one that silently didn't apply.

Mining is deliberately conservative, because these rules land in an engine that
fails loudly: evidence has to be one-sided, punctuation rules only come from text
you actually typed (a dictation transcript's punctuation is Whisper's choice, not
yours), and a word is only suggested for banning if you removed it from several
rewrites *and* never use it yourself.

Everything is local, in `style-corpus.json` next to `style.json` — **Reveal** to
read it, **Forget everything** to wipe it, and a toggle to stop collecting while
keeping what's already learned. Note that with a hosted model, the samples
retrieval picks are sent with each rewrite along with your selection; the local
model option keeps all of it on this machine.

One thing it can't tell: **selected text is assumed to be yours.** Shorten a
colleague's email or a paragraph from a web page and that prose is harvested as
your voice. The app knows to skip its own output, but it has no way to know who
wrote anything else. If you rewrite a lot of other people's text, either turn
collection off or prune the corpus from the Style tab.

### Local models

**Settings → Style** picks the provider independently of the dictation cleanup,
so your prose can go somewhere different from your transcripts. Choose
_OpenAI-compatible_ and point it at a local server to keep your writing on this
machine:

| Server | Base URL |
| --- | --- |
| Ollama | `http://localhost:11434/v1` |
| LM Studio | `http://localhost:1234/v1` |

No API key is needed for a local server — the header simply isn't sent when the
key is empty.

## Tests

```bash
swift test
```

Requires a full Xcode install (the `KeyboardShortcuts` dependency uses the
`#Preview` macro, and `XCTest` ships with Xcode). Command Line Tools alone
isn't enough to build or test this project.

## Changesets

Changelog and versioning are managed with [changesets](https://github.com/changesets/changesets).
When you make a notable change, record it:

```bash
pnpm changeset            # write a changeset (pick the bump level + summary)
```

On push to `main`, the **Changesets** workflow opens a "Version Packages" PR that
consumes the pending changesets. Merging it bumps `package.json` and regenerates
`CHANGELOG.md`. To preview locally:

```bash
pnpm install
pnpm changeset version    # updates CHANGELOG.md + package.json version
```

Then tag the matching `vX.Y.Z` release to trigger the signed/notarized build.

## License

MIT — see [LICENSE](LICENSE).
