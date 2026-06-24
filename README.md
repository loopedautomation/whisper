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
- 🔒 Launch at login, menu-bar agent (no Dock icon).

## Install

Once a release is published, install with Homebrew (Apple Silicon, macOS 14+):

```bash
brew install --cask loopedautomation/tap/looped-whisper
```

Or download the notarized `.zip` from the [Releases](https://github.com/loopedautomation/whisper/releases) page.

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

## Tests

```bash
swift test
```

## Changesets

Changelog and versioning are managed with [changesets](https://github.com/changesets/changesets).
When you make a notable change, record it:

```bash
npx changeset            # write a changeset (pick the bump level + summary)
```

At release time, roll the pending changesets into `CHANGELOG.md` and bump the version:

```bash
npx changeset version    # updates CHANGELOG.md + package.json version
```

Then tag the matching `vX.Y.Z` release to trigger the signed/notarized build.

## License

MIT — see [LICENSE](LICENSE).
