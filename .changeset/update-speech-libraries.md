---
"looped-whisper": minor
---

Update the speech libraries, and add a compact turbo model.

- **WhisperKit 1.0.0 → 1.1.1:** crash fixes, a fix for vocabulary prompts, no more re-downloading config files when checking a model you already have, and a cancelled download now fails instead of leaving a model that looks complete but is missing files.
- **speech-swift 0.0.21 → 0.0.29:** includes an upstream fix to how Parakeet filters digit tokens.
- **New model: Large v3 (turbo, compact)** — the same turbo model compressed to about 630 MB instead of 1.6 GB.
