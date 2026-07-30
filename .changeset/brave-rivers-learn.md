---
"looped-whisper": minor
---

Learn style **per language**, and understand commands in German, French and Spanish.

Style was previously one profile across every language. That's fine while the corpus is empty, but once you've accumulated English samples, rewriting a German paragraph handed the model English samples labelled as your voice — dragging the result toward English rhythm and vocabulary. Worse than sending no samples at all.

Samples now record the language they're written in, detected on-device (and taken from transcription, which already knows). Retrieval only offers samples in the passage's language: no German samples means generic prose, which is the honest outcome. Readiness is reported per language too, so Settings → Style says "matching your style in English, still learning in German" instead of one number that promises a match it can't deliver. Punctuation rules are mined from a single language, since German „quotes" and French guillemets are conventions, not habits to be overridden by English evidence. Existing corpora have their languages filled in on first load.

Commands also work properly in German, French and Spanish now: *"mach es kürzer"* lands on the same intent as *"make it shorter"*, negation isn't inverted (*"weniger formell"* means less formal, not more), and accented characters survive the normalizer. Anything in another language still falls through to the model verbatim, as before.
