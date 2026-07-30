---
"looped-whisper": minor
---

Make style templates discoverable, and let one hotkey do both jobs.

**Templates were invisible to existing users.** The starter file demonstrating them is only written when no `style.json` exists, so anyone who already had one never received the examples — and the Settings picker hid itself when there were no templates, leaving nothing on screen to suggest the feature existed. The Style tab now always shows a Templates section, with a button that writes the Email and Slack examples straight into your config.

**Push-to-talk can now rewrite a selection.** Turn on "Push-to-talk rewrites a selection" in Settings → Hotkeys and your dictation key rewrites whatever text is selected, dictating only when nothing is. No second shortcut to remember.

Whether text is selected is read through the Accessibility API rather than guessed, because guessing wrong destroys text in both directions: a false positive rewrites something while you meant to dictate, and a false negative replaces your selected paragraph with the words you just spoke. When Accessibility answers, the selection is used directly and **your clipboard is never touched at all** — no copy, no paste. Some apps (Electron ones especially) won't report their selection; that case is reported as *unknown* rather than assumed either way, and a second setting decides whether to dictate or confirm by copying. The dedicated ⌃⌥E shortcut keeps working regardless, and the whole thing is off by default since it changes what an existing key does.
