# Looped Whisper — task runner. Wraps SwiftPM + scripts/build-app.sh.
# Usage: `make <target>` (run `make help` to list).

APP      := build/LoopedWhisper.app
BIN      := $(APP)/Contents/MacOS/LoopedWhisper

.DEFAULT_GOAL := help
.PHONY: help build build-debug bundle run run-debug dev test clean resolve fmt icon dev-cert reset-perms

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: ## Build a release .app bundle
	@./scripts/build-app.sh release

build-debug: ## Build a debug .app bundle
	@./scripts/build-app.sh debug

bundle: build ## Alias for `build`

run: build ## Build (release) and launch the app
	@open "$(APP)"

run-debug: build-debug ## Build (debug) and run in the foreground with logs
	@"$(BIN)"

dev: ## Watch sources: rebuild + relaunch on change (needs `brew install watchexec`)
	@command -v watchexec >/dev/null 2>&1 || { \
		echo "watchexec not found. Install with: brew install watchexec"; exit 1; }
	@watchexec -e swift -r --project-origin . -- \
		'./scripts/build-app.sh debug && open "$(APP)"'

icon: ## Generate AppIcon.icns from Resources/AppIcon.png
	@./scripts/make-icon.sh

dev-cert: ## Create a stable self-signed signing identity (so TCC grants persist)
	@./scripts/dev-cert.sh

reset-perms: ## Clear stale TCC grants for the app (then relaunch & re-grant)
	@tccutil reset Accessibility com.looped.whisper || true
	@tccutil reset ListenEvent com.looped.whisper || true
	@tccutil reset Microphone com.looped.whisper || true
	@echo "Cleared TCC entries for com.looped.whisper. Rebuild + relaunch, then re-grant."

test: ## Run unit tests
	@swift test

resolve: ## Resolve/fetch SwiftPM dependencies
	@swift package resolve

clean: ## Remove build artifacts
	@swift package clean
	@rm -rf build .build

fmt: ## Format sources with swift-format if available
	@command -v swift-format >/dev/null 2>&1 \
		&& swift-format format -i -r Sources Tests \
		|| echo "swift-format not found (optional). Try: brew install swift-format"
