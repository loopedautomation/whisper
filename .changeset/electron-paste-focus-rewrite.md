---
"looped-whisper": patch
---

Actually fix pasting into Electron apps (Discord, Claude, …). The 0.6.1 fix missed the real failure: the system-wide accessibility "focused application" query itself answers "none" for Electron apps, so the focus check bailed to copy-only before any fallback logic ran. The focus check now finds the frontmost app via NSWorkspace, asks its accessibility tree directly, and only skips the paste when the app positively reports that no window and no element have focus — any uncertainty means the paste is attempted.
