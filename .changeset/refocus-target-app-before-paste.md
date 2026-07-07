---
"looped-whisper": patch
---

Fix an intermittent bug where a recording would finish but nothing got typed, with no error shown — most noticeable since language detection and AI cleanup can add real latency before delivery, widening the window for focus to drift away from the app you were dictating into. The app you were in when you started recording is now captured and explicitly re-activated right before pasting or typing, regardless of what's frontmost by the time delivery actually happens.
