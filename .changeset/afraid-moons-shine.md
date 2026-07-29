---
"looped-whisper": minor
---

Add Apple's on-device model as a third rewrite provider. Rewriting previously needed an Anthropic API key or a user-run OpenAI-compatible server, which sat badly with an app whose transcription is fully local. Selectable for both the selection rewrite and the dictation cleanup: no key, no server, no download, and nothing leaves the machine.

It requires macOS 26 with Apple Intelligence enabled. The framework is weak-linked, so the app still launches on macOS 15 and simply reports the provider as unavailable — as it does for a Mac that is ineligible, has Apple Intelligence switched off, or is still downloading the model, each with the specific fix rather than a generic "not configured".

Two behaviours needed handling that the hosted providers don't have. The context window covers instructions, prompt and reply together, so the reply budget is computed from what's left after the passage and checked before generating — a selection with no room for an answer fails up front, and a reply that runs to the ceiling is treated as truncated rather than pasted over your text. And because the default guardrails refuse legitimate material like a news paragraph or a medical email, generation uses Apple's permissive content-transformation mode; in that mode the model can still decline by *returning* a refusal instead of throwing, so refusals are detected and reported rather than pasted into your document.

The cloud provider stays the default. The on-device model is much smaller: good for short everyday rewrites, weaker at matching your voice from samples and at long or intricate instructions. Settings says so rather than implying parity.
