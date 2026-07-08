---
"looped-whisper": patch
---

Fix a confusing "stuck" experience after switching to a bigger model (or while a previous recording is still transcribing/cleaning up): starting a new recording during that window doesn't fail, it just silently queues behind the in-flight work, while the status line gets overwritten to "Recording…"/"Transcribing…" — hiding what's actually happening for as long as that takes (worst case: minutes, for a multi-GB model download). Starting a recording is now refused with a specific message ("Large v3 (turbo) is still loading", "Still transcribing the previous recording", etc.) instead of silently queuing.
