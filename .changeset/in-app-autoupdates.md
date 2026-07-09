---
"looped-whisper": minor
---

In-app auto-updates: when a new release is available, the app now downloads the signed, notarized update in the background, verifies its Developer ID code signature (Apple-anchored chain + matching Team ID), and offers a one-click "Restart to Update" from the menu bar and the About tab. Builds that can't safely self-update (dev builds, translocated or read-only installs) keep the existing behavior of linking to the releases page. The Homebrew cask is now marked `auto_updates true` so `brew upgrade` doesn't fight the in-app updater.
