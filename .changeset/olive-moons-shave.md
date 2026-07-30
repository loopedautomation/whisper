---
"looped-whisper": minor
---

Remove the old transcript-cleanup rewrite, and collapse three model settings into one.

**The LLM cleanup pass over every dictation is gone.** It predates "rewrite my selection" and was superseded by it: instead of an always-on model pass guessing at what you meant, you now select text and say what you want. Dictation is delivered exactly as Whisper transcribed it — no round-trip, no latency, and nothing leaves your Mac on the dictation path. The user-editable prompt template goes with it.

**Settings → Rewrite is now Settings → AI, and it's the only place a model is configured.** The app had grown two provider configurations that shared one Keychain entry — one for transcript cleanup, one for selection rewrite — plus language repair and quick-action matching quietly reading the first of them. That meant the tab you'd configure and the feature you'd configured it for could drift apart, and the Style tab had to explain that its API key lived somewhere else. Now there is one provider, one model, one base URL, one key, used by everything that calls a model.

Your existing setup carries over on first launch. The selection-rewrite configuration wins where both were set, since it configures the feature that survives; the Keychain entry is deliberately left where it is, so your API key is untouched.

Two consequences worth knowing: language repair and quick-action classification now run on whatever model you picked for rewriting your prose, so if you had pointed transcript cleanup at a cheap fast tier, those two jobs are no longer using it. And the default Anthropic model is now `claude-opus-4-8` rather than a Haiku tier, because rewriting your writing is the demanding job this setting now serves.
