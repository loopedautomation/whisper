# looped-whisper

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
