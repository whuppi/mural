# ═══════════════════════════════════════════════════════════════════
# SDK resolution
#
# Uses fvm by default (.fvmrc pins the version). Contributors without
# fvm can override:  make check DART=dart FLUTTER=flutter
# ═══════════════════════════════════════════════════════════════════

DART    ?= fvm dart
FLUTTER ?= fvm flutter
TEST_RESULTS_DIR ?= test-results
TIMEOUT := $(if $(CI),--timeout=30x,)
VERBOSE := $(if $(CI),--verbose,)

.PHONY: check hooks \
        analyze analyze-floor lint-shell platforms format test-guards \
        test test-unit test-web \
        test-example-matrix test-example-macos test-example-device \
        test-example-android test-example-ios test-example-linux \
        test-example-windows test-example-web \
        verify-android verify-ios verify-macos verify-linux \
        verify-windows verify-web \
        clean

# ═══════════════════════════════════════════════════════════════════
# § 1 — Gate
#
# make check    Full local gate before PR.
# make hooks    Activate the repo's git hooks (commit-msg, pre-commit).
#               Run once after cloning — they stay dormant otherwise.
#               Idempotent.
# ═══════════════════════════════════════════════════════════════════

check: format analyze analyze-floor lint-shell platforms test-guards test test-example-matrix

hooks:
	@git config core.hooksPath .githooks
	@echo "✓ git hooks active (core.hooksPath → .githooks)"

# ═══════════════════════════════════════════════════════════════════
# § 2 — Analyze
#
# make format         Formatter in check mode — fails on unformatted files
#                     (CI is never the first place the formatter runs).
# make analyze        Static analysis via the shared analyze_core.sh (canonical
#                     in whuppi/ci, stamped into tool/) — a suppression-comment
#                     ban + dart/flutter analyze --fatal-infos over lib, test,
#                     tool, and example; an INFO fails like an error.
# make analyze-floor  Resolve to the OLDEST in-range dependencies and
#                     analyze the shipped code (lib only). The lower bounds
#                     are only honest if the code analyzes against them,
#                     not just the newest a fresh build resolves. Tests are
#                     excluded on purpose; a consumer sees lib, never your
#                     tests. Snapshots and restores the lock so a local run
#                     leaves the tree clean.
# make platforms      Gate pub.dev platform support via the shared
#                     platforms_gate.sh (canonical in whuppi/ci, stamped into
#                     tool/): pana — pinned to PANA_VERSION in tool/versions.env,
#                     the exact analyzer pub.dev runs — must report all six
#                     platforms, else a regression like an unconditional dart:io
#                     import silently drops web (the conditional worker export
#                     in lib/src/encode/ is what it protects).
# make lint-shell     Shell portability gate via the shared lint_shell.sh
#                     (canonical in whuppi/ci): shellcheck + a bash-3.2 + BSD
#                     scan over every tracked script and workflow run block.
# ═══════════════════════════════════════════════════════════════════

format:
	$(DART) format --output=none --set-exit-if-changed .

analyze:
	@DART="$(DART)" FLUTTER="$(FLUTTER)" bash tool/analyze_core.sh

analyze-floor:
	@cp pubspec.lock .pubspec.lock.floor-backup
	$(FLUTTER) pub downgrade
	$(DART) analyze lib
	@mv .pubspec.lock.floor-backup pubspec.lock
	@$(FLUTTER) pub get >/dev/null
	@echo "✓ floor analyze clean (lockfile restored)"

platforms:
	@DART="$(DART)" EXPECTED_PLATFORMS="android ios linux macos windows web" bash tool/platforms_gate.sh

lint-shell:
	@bash tool/lint_shell.sh

# ═══════════════════════════════════════════════════════════════════
# § 2b — Test-suite guards
#
# make test-guards   Mechanical rules over the package and its suite:
#                    - dart:io nowhere in lib/ or test/ — the package is
#                      pure cross-platform Dart; the only platform split
#                      is the conditional worker/raster-policy exports
#                    - dart:js_interop only in the web seam files
#                      (png_worker_web, raster_policy_web) — anywhere
#                      else breaks every non-web compile
#                    - dart:isolate only in png_worker_native.dart —
#                      the one file the io-conditional export selects
#                    - batteries stay platform-blind: no dart:isolate,
#                      no dart:js_interop — the SAME battery must run
#                      on the VM and in a browser
# ═══════════════════════════════════════════════════════════════════

test-guards:
	@bad=$$(grep -rln "import 'dart:io'" lib/ test/ --include="*.dart" || true); \
	if [ -n "$$bad" ]; then \
	  echo "dart:io found — mural is pure cross-platform Dart; the platform"; \
	  echo "splits are the conditional exports, never dart:io:"; \
	  echo "$$bad"; exit 1; fi
	@bad=$$(grep -rln "import 'dart:js_interop" lib/ --include="*.dart" \
	  | grep -v "lib/src/encode/png_worker_web.dart" \
	  | grep -v "lib/src/capture/raster_policy_web.dart" || true); \
	if [ -n "$$bad" ]; then \
	  echo "dart:js_interop outside the web seam files — every non-web"; \
	  echo "compile breaks:"; \
	  echo "$$bad"; exit 1; fi
	@bad=$$(grep -rln "import 'dart:isolate'" lib/ --include="*.dart" \
	  | grep -v "lib/src/encode/png_worker_native.dart" || true); \
	if [ -n "$$bad" ]; then \
	  echo "dart:isolate outside png_worker_native.dart — the io-conditional"; \
	  echo "export is the only place isolates may live:"; \
	  echo "$$bad"; exit 1; fi
	@bad=$$(grep -rln "import 'dart:isolate'\|import 'dart:js_interop" test/batteries/ --include="*.dart" || true); \
	if [ -n "$$bad" ]; then \
	  echo "platform-bound import in a battery — batteries run identically"; \
	  echo "on the VM and in a browser:"; \
	  echo "$$bad"; exit 1; fi
	@echo "✓ test guards clean"

# ═══════════════════════════════════════════════════════════════════
# § 3 — Test
#
# make test        Every battery on the VM + the same batteries in a
#                  real web engine.
# make test-unit   Batteries via the native runner + VM-only isolate
#                  suites (flutter test).
# make test-web    The IDENTICAL batteries in wasm Chrome. Runs through
#                  `--wasm` (dart2wasm + skwasm) deliberately: it is the
#                  lane Flutter's own framework CI runs, and the DDC lane
#                  has a module-emission bug that hangs suite loading
#                  forever (upstream report tracked in-repo). On Linux CI
#                  Chrome ships no SUID sandbox binary, so
#                  CHROME_EXECUTABLE is wrapped with --no-sandbox.
# ═══════════════════════════════════════════════════════════════════

test: test-unit test-web

test-unit:
	@echo "=== Unit: VM (batteries via native runner + isolate suites) ==="
	@mkdir -p $(TEST_RESULTS_DIR)
	$(FLUTTER) test $(VERBOSE) $(TIMEOUT) --file-reporter json:$(TEST_RESULTS_DIR)/unit.json

test-web:
	@echo "=== Web: every battery in wasm Chrome (flutter test --wasm) ==="
	@mkdir -p $(TEST_RESULTS_DIR)
	@if [ "$$(uname -s)" = "Linux" ] && [ -n "$$CI" ]; then \
	  base="$${CHROME_EXECUTABLE:-$$(command -v google-chrome-stable || command -v google-chrome || command -v chromium)}"; \
	  printf '#!/bin/sh\nexec "%s" --no-sandbox --disable-gpu "$$@"\n' "$$base" > $(TEST_RESULTS_DIR)/chrome-ci; \
	  chmod +x $(TEST_RESULTS_DIR)/chrome-ci; \
	  export CHROME_EXECUTABLE="$$PWD/$(TEST_RESULTS_DIR)/chrome-ci"; \
	fi; \
	$(FLUTTER) test $(VERBOSE) $(TIMEOUT) --platform chrome --wasm test/runners/web_runner_test.dart --file-reporter json:$(TEST_RESULTS_DIR)/web.json

# ═══════════════════════════════════════════════════════════════════
# § 3b — Example tests
#
# make test-example-matrix   Host-VM journeys: the example UI driven end
#                            to end through real captures. No device
#                            needed — part of check.
# make test-example-macos    Integration smoke on macOS.
# make test-example-device   Integration smoke on DEVICE=<id>.
# make test-example-<plat>   Integration smoke on one real target — the
#                            per-platform CI matrix (full-test) runs these.
# make verify-<plat>         Release build of the example — proves the
#                            package builds and links on that target.
# ═══════════════════════════════════════════════════════════════════

test-example-matrix:
	@echo "=== Example: journey matrix (host VM) ==="
	cd example && $(FLUTTER) test $(VERBOSE) $(TIMEOUT) test/journeys

test-example-macos:
	@echo "=== Example: integration smoke on macOS ==="
	cd example && $(FLUTTER) test $(TIMEOUT) integration_test/mural_smoke_test.dart -d macos

test-example-device:
	@echo "=== Example: integration smoke on device=$(DEVICE) ==="
	cd example && $(FLUTTER) test $(TIMEOUT) integration_test/mural_smoke_test.dart -d $(DEVICE)

test-example-android:
	@echo "=== Example: Android ==="
	@mkdir -p $(TEST_RESULTS_DIR)
	cd example && $(FLUTTER) test $(VERBOSE) $(TIMEOUT) integration_test/mural_smoke_test.dart --file-reporter json:../$(TEST_RESULTS_DIR)/int-android.json

test-example-ios:
	@echo "=== Example: iOS ==="
	@mkdir -p $(TEST_RESULTS_DIR)
	cd example && $(FLUTTER) test $(VERBOSE) $(TIMEOUT) integration_test/mural_smoke_test.dart --file-reporter json:../$(TEST_RESULTS_DIR)/int-ios.json

test-example-linux:
	@echo "=== Example: Linux ==="
	$(call ensure_gtk)
	@mkdir -p $(TEST_RESULTS_DIR)
	cd example && $(FLUTTER) test $(VERBOSE) $(TIMEOUT) integration_test/mural_smoke_test.dart -d linux --file-reporter json:../$(TEST_RESULTS_DIR)/int-linux.json

test-example-windows:
	@echo "=== Example: Windows ==="
	@mkdir -p $(TEST_RESULTS_DIR)
	cd example && $(FLUTTER) test $(VERBOSE) $(TIMEOUT) integration_test/mural_smoke_test.dart -d windows --file-reporter json:../$(TEST_RESULTS_DIR)/int-windows.json

# Web integration runs through flutter drive (-d web-server) with a single
# Chrome managed by chromedriver. The chrome capability puts chromedriver
# on PATH in CI. One shell so the background chromedriver PID survives to
# the cleanup.
test-example-web:
	@echo "=== Example: Web (integration smoke via flutter drive) ==="
	@chromedriver --port=4444 >/dev/null 2>&1 & \
	CD_PID=$$!; \
	sleep 2; \
	( cd example && $(FLUTTER) drive \
	    --driver=test_driver/integration_test.dart \
	    --target=integration_test/mural_smoke_test.dart \
	    -d web-server \
	    --browser-name=chrome \
	    --driver-port=4444 \
	    --web-browser-flag=--no-sandbox ); \
	rc=$$?; \
	kill $$CD_PID 2>/dev/null || true; \
	exit $$rc

# ── Verify: release builds of the example ──
verify-android:
	@echo "=== Verify: Android ==="
	cd example && $(FLUTTER) build apk --release $(VERBOSE)

verify-ios:
	@echo "=== Verify: iOS ==="
	cd example && $(FLUTTER) build ios --release --no-codesign $(VERBOSE)

verify-macos:
	@echo "=== Verify: macOS ==="
	cd example && $(FLUTTER) build macos --release $(VERBOSE)

verify-linux:
	@echo "=== Verify: Linux ==="
	$(call ensure_gtk)
	cd example && $(FLUTTER) build linux --release $(VERBOSE)

verify-windows:
	@echo "=== Verify: Windows ==="
	cd example && $(FLUTTER) build windows --release $(VERBOSE)

verify-web:
	@echo "=== Verify: Web ==="
	@FLUTTER="$(FLUTTER)" bash tool/verify_web_gate.sh

# ═══════════════════════════════════════════════════════════════════
# § 3c — Build helpers
# ═══════════════════════════════════════════════════════════════════

# Linux desktop builds need GTK 3. Present → no-op. Missing → install on
# CI, instruct locally.
define ensure_gtk
	@command -v pkg-config >/dev/null && pkg-config --exists gtk+-3.0 || { \
		if [ -n "$$CI" ]; then sudo apt-get update -qq && sudo apt-get install -y -qq ninja-build libgtk-3-dev; \
		else echo "Error: libgtk-3-dev not found. Run: sudo apt-get install -y ninja-build libgtk-3-dev"; exit 1; fi; }
endef

# ═══════════════════════════════════════════════════════════════════
# § 4 — Clean
# ═══════════════════════════════════════════════════════════════════

clean:
	$(FLUTTER) clean
	rm -rf $(TEST_RESULTS_DIR)
