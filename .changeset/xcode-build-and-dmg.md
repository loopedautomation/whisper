---
"looped-whisper": patch
---

Build the app with Xcode so SwiftPM dependency resource bundles are embedded correctly — fixes the crash when opening Settings (the previous fix didn't fully resolve it). Also ship a notarized `.dmg` installer (drag-to-Applications) alongside the zip and Homebrew cask.
