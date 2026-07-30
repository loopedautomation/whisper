---
"looped-whisper": patch
---

Fix a stuck recording. With "Push-to-talk rewrites a selection" enabled and text selected, releasing the push-to-talk key did nothing at all — the recording never stopped and the microphone stayed on until you pressed Esc or quit the app.

The cause: that key can now start *either* pipeline, but its release only ever ended dictation, and dictation's end refused to act while a selection rewrite was live. So the release matched neither, and nothing stopped the recorder. Releases now end whichever pipeline the press actually started, and the same fix covers the toggle shortcut and the fn key, which had the identical hole.

Also: the "Push-to-talk rewrites a selection" toggle now applies as soon as you flip it. It previously required pressing Save, which made it look like it had taken effect when it hadn't.
