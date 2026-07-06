---
"looped-whisper": patch
---

Fix a bug where a recording could decode to an empty transcript (silence, background noise, a very short or quiet clip) and still play the success sound with nothing typed and no warning shown. Empty decode results are now treated the same as "no speech detected" — same soft warning as recording with no audio at all — instead of silently completing as if delivery had succeeded.
