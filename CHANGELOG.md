# looped-whisper

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
