# looped-whisper

## 0.11.0

### Minor Changes

- 45180ff: Learn style **per language**, and understand commands in German, French and Spanish.

  Style was previously one profile across every language. That's fine while the corpus is empty, but once you've accumulated English samples, rewriting a German paragraph handed the model English samples labelled as your voice — dragging the result toward English rhythm and vocabulary. Worse than sending no samples at all.

  Samples now record the language they're written in, detected on-device (and taken from transcription, which already knows). Retrieval only offers samples in the passage's language: no German samples means generic prose, which is the honest outcome. Readiness is reported per language too, so Settings → Style says "matching your style in English, still learning in German" instead of one number that promises a match it can't deliver. Punctuation rules are mined from a single language, since German „quotes" and French guillemets are conventions, not habits to be overridden by English evidence. Existing corpora have their languages filled in on first load.

  Commands also work properly in German, French and Spanish now: _"mach es kürzer"_ lands on the same intent as _"make it shorter"_, negation isn't inverted (_"weniger formell"_ means less formal, not more), and accented characters survive the normalizer. Anything in another language still falls through to the model verbatim, as before.

- ed974e9: Make style templates discoverable, and let one hotkey do both jobs.

  **Templates were invisible to existing users.** The starter file demonstrating them is only written when no `style.json` exists, so anyone who already had one never received the examples — and the Settings picker hid itself when there were no templates, leaving nothing on screen to suggest the feature existed. The Style tab now always shows a Templates section, with a button that writes the Email and Slack examples straight into your config.

  **Push-to-talk can now rewrite a selection.** Turn on "Push-to-talk rewrites a selection" in Settings → Hotkeys and your dictation key rewrites whatever text is selected, dictating only when nothing is. No second shortcut to remember.

  Whether text is selected is read through the Accessibility API rather than guessed, because guessing wrong destroys text in both directions: a false positive rewrites something while you meant to dictate, and a false negative replaces your selected paragraph with the words you just spoke. When Accessibility answers, the selection is used directly and **your clipboard is never touched at all** — no copy, no paste. Some apps (Electron ones especially) won't report their selection; that case is reported as _unknown_ rather than assumed either way, and a second setting decides whether to dictate or confirm by copying. The dedicated ⌃⌥E shortcut keeps working regardless, and the whole thing is off by default since it changes what an existing key does.

### Patch Changes

- 76e088d: Pin the rewrite's output language to the passage. The instruction sent to the model is written in English whatever language you selected, and nothing previously told the model to keep the passage's language — so a German selection could come back rewritten into English, most likely with the smaller on-device model. The rule is now unconditional, and when the language is identified it's named explicitly as well.

  This also means you don't need to speak the language you're writing in: say "style it" in English over a German selection and you get your German style, in German. The style is chosen by the selected text, not by the command.

## 0.10.0

### Minor Changes

- 2598b3c: Add style templates. `style.json` can now hold named variations — Email, Slack, whatever you write in — alongside the base profile. Name one while you speak ("style it as an email", "make it shorter as a slack message"), or set a default in Settings → Style so one applies whenever you don't say otherwise.

  Templates add to the base rather than replacing it: guidance, substitutions and banned words merge, so a word you never use stays banned everywhere, while single values like `maxWords`, `voice.description` and `straightenQuotes` override. A template can also switch a base rule off. An unrecognized template name falls back to the base rather than failing, since a misheard word shouldn't cost you the rewrite.

  The config stays as strict as before, and the strictness reaches inside templates: a typo in `templates.email.enforced` is the same hard error it would be at the top level, and pointing `defaultTemplate` at a template that doesn't exist is rejected rather than quietly ignored. "style it" now also reads as a plain rewrite instruction. Existing single-profile configs are unchanged and keep working.

### Patch Changes

- 010e131: Hide the Model and API key fields in Settings → Rewrite when the on-device provider is selected. They don't apply to it, and two empty boxes read as "something is missing" when nothing is. The availability status is shown there now too, matching Settings → Style.

## 0.9.0

### Minor Changes

- 86b35e2: Add Apple's on-device model as a third rewrite provider. Rewriting previously needed an Anthropic API key or a user-run OpenAI-compatible server, which sat badly with an app whose transcription is fully local. Selectable for both the selection rewrite and the dictation cleanup: no key, no server, no download, and nothing leaves the machine.

  It requires macOS 26 with Apple Intelligence enabled. The framework is weak-linked, so the app still launches on macOS 15 and simply reports the provider as unavailable — as it does for a Mac that is ineligible, has Apple Intelligence switched off, or is still downloading the model, each with the specific fix rather than a generic "not configured".

  Two behaviours needed handling that the hosted providers don't have. The context window covers instructions, prompt and reply together, so the reply budget is computed from what's left after the passage and checked before generating — a selection with no room for an answer fails up front, and a reply that runs to the ceiling is treated as truncated rather than pasted over your text. And because the default guardrails refuse legitimate material like a news paragraph or a medical email, generation uses Apple's permissive content-transformation mode; in that mode the model can still decline by _returning_ a refusal instead of throwing, so refusals are detected and reported rather than pasted into your document.

  The cloud provider stays the default. The on-device model is much smaller: good for short everyday rewrites, weaker at matching your voice from samples and at long or intricate instructions. Settings says so rather than implying parity.

## 0.8.0

### Minor Changes

- 31b4945: Add "rewrite my selection": select text in any app, hold ⌃⌥E, say what you want ("make it shorter", "fix the typos"), and the selection is replaced in place with a rewrite in your own writing style. A typed-instruction path is available from the menu bar for use without a microphone.

  Your style lives in a hand-edited `style.json`, split into rules that are prompted and rules that are enforced in code after the model replies. Safe substitutions (em dash → comma, curly → straight quotes, a banned word with a stated replacement) are applied deterministically with no extra model call. Rules that can't be repaired without deciding what the text means (a word limit, a banned word with no replacement) go back to the model once, naming the breach exactly; if it still won't comply you get the best attempt plus a visible error listing every rule that didn't hold. A misspelled rule name is a hard error rather than a silently ignored no-op.

  The model is instructed never to invent facts, names, numbers, or dates absent from the original, and any packaging around its reply (code fences, "Here's the rewritten text:", surrounding quotes) is stripped before it reaches your document. Settings → Style picks the provider separately from the dictation cleanup, so the selection can be sent to a local model (Ollama, LM Studio) instead of a hosted one.

  Two robustness details worth knowing: the paste target is pinned when you press the shortcut rather than following focus, so switching apps while the model works can't send the rewrite into the wrong window (this also hardens the existing dictation path); and a reply cut off at the model's output ceiling is reported instead of pasted, so a long selection is never replaced by a truncated version of itself.

  The rewrite also learns your voice as you use it, from two signals collected out of work you were already doing: your dictation transcripts and the text you select, plus your edits to rewrites it pasted earlier — a selection that matches an earlier rewrite is recognized as that rewrite after you changed it, which says directly what you wanted. Samples matching the passage's shape are sent with each rewrite rather than a fixed set. Rewriting is never blocked on this; the menu bar and Settings → Style report honestly whether it's running generic, still learning, or matching your style. Once the evidence is one-sided, rules are _proposed_ in the Style tab with the counts behind them and are only ever written to `style.json` by an explicit click. Everything stays on the machine in `style-corpus.json`, which you can read, prune, or wipe, with a toggle to stop collecting.

## 0.7.0

### Minor Changes

- 7f6b42b: In-app auto-updates: when a new release is available, the app now downloads the signed, notarized update in the background, verifies its Developer ID code signature (Apple-anchored chain + matching Team ID), and offers a one-click "Restart to Update" from the menu bar and the About tab. Builds that can't safely self-update (dev builds, translocated or read-only installs) keep the existing behavior of linking to the releases page. The Homebrew cask is now marked `auto_updates true` so `brew upgrade` doesn't fight the in-app updater.

## 0.6.2

### Patch Changes

- cb0a29c: Actually fix pasting into Electron apps (Discord, Claude, …). The 0.6.1 fix missed the real failure: the system-wide accessibility "focused application" query itself answers "none" for Electron apps, so the focus check bailed to copy-only before any fallback logic ran. The focus check now finds the frontmost app via NSWorkspace, asks its accessibility tree directly, and only skips the paste when the app positively reports that no window and no element have focus — any uncertainty means the paste is attempted.

## 0.6.1

### Patch Changes

- 87e276e: Fix paste never firing in Electron apps (Discord, Claude, etc.). The keyboard-focus check added in 0.6.0 treated Electron's lazily-enabled accessibility tree as "nothing focused" and skipped the paste entirely. We now ask Chromium apps to enable their AX tree (`AXManualAccessibility`) and, when an app has a focused window but reports no focused element, attempt the paste anyway instead of dropping it.

## 0.6.0

### Minor Changes

- 02a6e20: Add voice quick actions: spoken commands can trigger actions instead of pasting text — open URLs (including incognito), launch or quit apps, and run Siri Shortcuts. Trigger phrases are matched on-device, with optional AI intent detection via your Rewrite provider for paraphrased commands. Hold a configurable modifier (default ⌘) as recording starts to switch into action mode; without it, everything pastes as normal dictation. Configure in Settings → Actions (off by default).
- f676eed: Add Parakeet TDT v3 (via speech-swift) as an additional transcription engine alongside WhisperKit.
- 6d0bac9: Capture crashes locally (uncaught exceptions and signals) and surface them on the next launch so they can be reviewed and reported. Privacy-respecting: crash logs stay on your machine and nothing is sent anywhere without your consent.

## 0.5.2

### Patch Changes

- e3adca2: Fix a confusing "stuck" experience after switching to a bigger model (or while a previous recording is still transcribing/cleaning up): starting a new recording during that window doesn't fail, it just silently queues behind the in-flight work, while the status line gets overwritten to "Recording…"/"Transcribing…" — hiding what's actually happening for as long as that takes (worst case: minutes, for a multi-GB model download). Starting a recording is now refused with a specific message ("Large v3 (turbo) is still loading", "Still transcribing the previous recording", etc.) instead of silently queuing.
- 7737db2: Fix a bug in realtime dictation with 2+ languages selected: the final transcript could sometimes come back empty — no paste, no clipboard, no warning — even when live captions clearly showed real speech. The final decode was reusing a language guess made from only the first ~2 seconds of audio; a bad early guess could force the entire recording into the wrong language, degrading it all the way to nothing. The final decode now always detects fresh against the complete recording (as batch mode already did), and additionally retries once with free auto-detect if a detected-and-pinned language still decodes to nothing.

## 0.5.1

### Patch Changes

- df54e78: Fix an intermittent bug where a recording would finish but nothing got typed, with no error shown — most noticeable since language detection and AI cleanup can add real latency before delivery, widening the window for focus to drift away from the app you were dictating into. The app you were in when you started recording is now captured and explicitly re-activated right before pasting or typing, regardless of what's frontmost by the time delivery actually happens.

## 0.5.0

### Minor Changes

- 4dcd3d3: Add an opt-in "Fix cross-language mix-ups with AI" toggle (Settings → Model, shown once you select 2+ languages) that repairs words transcribed in the wrong language — e.g. mid-sentence switches between English and German — by sending the transcript to your configured Rewrite provider. Off by default so transcription stays fully local unless you turn it on. Not applied during realtime incremental typing.

### Patch Changes

- a46c31b: Fix a bug where a recording could decode to an empty transcript (silence, background noise, a very short or quiet clip) and still play the success sound with nothing typed and no warning shown. Empty decode results are now treated the same as "no speech detected" — same soft warning as recording with no audio at all — instead of silently completing as if delivery had succeeded.

## 0.4.0

### Minor Changes

- 318dd2b: Add a multi-language selector for transcription: pick the languages you speak from a popover checklist in Settings → Model. Select exactly one to pin it, or several (or none) to let the model auto-detect the language of each recording.
- 318dd2b: When several languages are selected, auto-detection is now restricted to just those languages — a recording can no longer be mis-transcribed in a language you never selected.

## 0.3.0

### Minor Changes

- d9b4d5e: Add an in-app update check that compares the running version against the latest GitHub release and notifies you when a newer version is available, with a link to download it.

## 0.2.0

### Minor Changes

- e0a6d3d: Add the ability to delete downloaded transcription models from Settings to free up disk space. Deletion asks for confirmation, and the currently active model can’t be deleted.
- ff568b7: Add a microphone picker to the menu bar dropdown: choose any available input device or follow the macOS system default (which tracks the OS as you change inputs). The selection is persisted across launches.
- e0a6d3d: Surface clear, user-facing error messages when transcription or AI rewrite models fail to load or run, a model hasn’t been downloaded, or a required permission (microphone, accessibility, input monitoring) hasn’t been granted — instead of failing silently.
- 4981aea: Menu bar & sound polish: use the Looped brand mark as the menu bar icon (crisp vector template) with a state-colored pill (recording #ED9B00, busy #685EF6, error #D02E1F) matching the macOS mic indicator; add a brand color palette and #685EF6 app accent; add a sound-effects volume slider; make the menu bar model picker functional (installed models only) and move the microphone picker below Start Recording; press Esc to cancel an in-progress recording and hide the live HUD.

### Patch Changes

- e0a6d3d: Show the app as “Looped Whisper” (with a space) in Finder and the Applications folder, instead of “LoopedWhisper”.
- e0a6d3d: Fix the model rows in Settings so the per-model action buttons (e.g. Reveal in Finder) are no longer hidden behind the scrollbar.

## 0.1.2

### Patch Changes

- cc760ca: Build the app with Xcode so SwiftPM dependency resource bundles are embedded correctly — fixes the crash when opening Settings (the previous fix didn't fully resolve it). Also ship a notarized `.dmg` installer (drag-to-Applications) alongside the zip and Homebrew cask.

## 0.1.1

### Patch Changes

- 983c2d5: Fix a crash on launch / when opening Hotkeys settings: the app bundle was missing the SwiftPM resource bundles (KeyboardShortcuts, swift-crypto, swift-transformers), so `Bundle.module` trapped at runtime. The build now copies them into the app and signs them.

## 0.1.0

### Minor Changes

- 4d54649: Initial release of Looped Whisper — a free, open-source, local voice transcription utility for macOS.

  **Transcription**

  - On-device transcription with WhisperKit (CoreML); works offline after a model is downloaded.
  - Bring-your-own-model: pick tiny → large-v3, with per-model download buttons, live progress, cancel, and a visible storage location.
  - Batch mode and realtime mode (live caption in an always-on-top, top-right liquid-glass HUD).

  **Input & output**

  - Global hotkeys shipped with sensible defaults (⌃⌥Space push-to-talk, ⌃⌥R toggle), fully rebindable.
  - fn / Globe key support (hold-to-talk or double-tap-to-toggle) via a passive event tap.
  - Copies to the clipboard and pastes at the cursor, with optional clipboard restore.

  **LLM cleanup & vocabulary**

  - Optional transcript cleanup via Anthropic or any OpenAI-compatible endpoint, with an editable user-prompt template (`{{input}}`) and an app-controlled system prompt.
  - Vocabulary list that biases recognition and is preserved during rewrite; stored as a hand-editable JSON file.
  - API key stored in the macOS Keychain; graceful fallback to the raw transcript on error/timeout.

  **App & UX**

  - Menu-bar agent (no Dock icon) with an animated spinner while busy and sound effects for start/stop/toggle/done (all toggleable).
  - Settings with explicit save states, a Sounds page, an About page, and launch-at-login.
  - In-app permissions management (microphone, accessibility, input monitoring) with reset and relaunch helpers.

  **Distribution**

  - Build tooling (Makefile, app-bundle script, stable-identity dev signing), app icon pipeline, and a release workflow that signs with Developer ID, notarizes, staples, and publishes a Homebrew cask.
