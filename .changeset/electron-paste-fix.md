---
"looped-whisper": patch
---

Fix paste never firing in Electron apps (Discord, Claude, etc.). The keyboard-focus check added in 0.6.0 treated Electron's lazily-enabled accessibility tree as "nothing focused" and skipped the paste entirely. We now ask Chromium apps to enable their AX tree (`AXManualAccessibility`) and, when an app has a focused window but reports no focused element, attempt the paste anyway instead of dropping it.
