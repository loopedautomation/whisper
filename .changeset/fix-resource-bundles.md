---
"looped-whisper": patch
---

Fix a crash on launch / when opening Hotkeys settings: the app bundle was missing the SwiftPM resource bundles (KeyboardShortcuts, swift-crypto, swift-transformers), so `Bundle.module` trapped at runtime. The build now copies them into the app and signs them.
