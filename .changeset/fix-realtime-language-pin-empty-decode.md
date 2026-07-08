---
"looped-whisper": patch
---

Fix a bug in realtime dictation with 2+ languages selected: the final transcript could sometimes come back empty — no paste, no clipboard, no warning — even when live captions clearly showed real speech. The final decode was reusing a language guess made from only the first ~2 seconds of audio; a bad early guess could force the entire recording into the wrong language, degrading it all the way to nothing. The final decode now always detects fresh against the complete recording (as batch mode already did), and additionally retries once with free auto-detect if a detected-and-pinned language still decodes to nothing.
