---
"looped-whisper": patch
---

Pin the rewrite's output language to the passage. The instruction sent to the model is written in English whatever language you selected, and nothing previously told the model to keep the passage's language — so a German selection could come back rewritten into English, most likely with the smaller on-device model. The rule is now unconditional, and when the language is identified it's named explicitly as well.

This also means you don't need to speak the language you're writing in: say "style it" in English over a German selection and you get your German style, in German. The style is chosen by the selected text, not by the command.
