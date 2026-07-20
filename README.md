<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme-cover.png">
  <img alt="Looped Whisper" src=".github/readme-cover-light.png" width="100%">
</picture>

<div align="center">

# Looped Whisper<br/><sub><b>Hold a key, speak — your words land at the cursor.</b></sub><br/><br/>[![Release](https://github.com/loopedautomation/whisper/actions/workflows/release.yml/badge.svg)](https://github.com/loopedautomation/whisper/actions/workflows/release.yml) [![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE) [![Platform](https://img.shields.io/badge/macOS%2014%2B-Apple%20Silicon-8b5cf6)](https://github.com/loopedautomation/whisper/releases)

</div>

A free, open-source, **Mac-only** voice transcription utility for developers. It
runs **local open-source Whisper models** (bring your own model) — no cloud
transcription. It lives in the menu bar, is driven by global hotkeys, and the
transcribed text is copied to the clipboard and pasted at your cursor.

**Contents:** [Features](#features) · [Install](#install) · [Build & run](#build--run) · [LLM rewrite](#llm-rewrite) · [Tests](#tests) · [License](#license)

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

## Tests

```bash
swift test
```

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
