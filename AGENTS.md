<!--
============================================================================
AUTO-GENERATED — DO NOT EDIT
============================================================================
This file is rendered by:
  /Users/deepanshu/personal1/whuppi/.claude/scripts/stamp-agents.sh
from:
  /Users/deepanshu/personal1/whuppi/AGENTS.template.md
  with per-repo data inlined in the stamper itself.

To change content:
  - Workspace-wide: edit AGENTS.template.md, then re-run the stamper.
  - One repo only:  edit the `repo_data` case for "mural" in stamp-agents.sh,
                    then re-run the stamper.
Manual edits to this file will be overwritten on the next stamp.
============================================================================
-->

# mural

> **Public AI agent contract** for mural — read by Cursor, OpenAI Codex, Aider, Devin, JetBrains Junie, and any AI tool that follows the [agents.md](https://agents.md) convention.
>
> Claude Code reads the deeper workspace config at `whuppi/.claude/rules/` and `whuppi/.claude/memory/` automatically — this AGENTS.md exists for every *other* AI tool.
>
> Stamped from `whuppi/AGENTS.template.md`. Per-repo content lives in the placeholder sections; everything else is identical workspace-wide.

---

## What this tool does

**mural** captures any Flutter widget as an image at any size — the GPU clamps a single rasterization to its maximum texture size (flutter/flutter#118024), so mural rasterizes in tiles from frozen scene snapshots, assembles bands, and streams the encode, bounding memory by a budget instead of by output size. Three doors on one `Mural` facade: `capture` (offscreen widget, staged with deterministic readiness — no timers), `captureInto` (bands stream into any `Sink<List<int>>`; the whole image never exists in memory), and `captureBoundary` (an on-screen `MuralBoundary`, frozen synchronously at the call so the shot shows that exact moment even mid-animation). Pure Dart, zero runtime dependencies, six platforms; PNG comes from an in-package streaming encoder (isolate on native, browser-native `CompressionStream` on web), with raw straight-alpha RGBA as the escape hatch.

This repo is one tool inside the **whuppi** workspace — a multi-tool monorepo. The workspace ships shared engineering standards, code conventions, brand identity, and build patterns that apply across every tool. They're documented in three layers:

- **Repo-specific architecture, design, reference:** `./docs/`
- **Workspace human-readable standards:** `../docs/` (when this repo is cloned as part of the whuppi workspace) — engineering principles, decision frameworks, secret/CI patterns
- **Workspace AI-only directives:** `../.claude/rules/` (Claude Code reads these automatically; other AI tools can read them as supplementary context)

If you're working on this tool standalone (cloned outside the workspace), the in-repo `./docs/` is your authority; ignore the workspace pointers.

---

## Build and test commands

Run these after every code change. A failing test or analyzer error means the task is not done — don't suppress with `// ignore:`, `# noqa`, or `--no-verify`. Fix the underlying issue.

```bash
# Setup (needs FVM — https://fvm.app; .fvmrc pins the Flutter version)
make hooks                      # activate git hooks (once after cloning)
fvm install
fvm flutter pub get
make check                      # format + analyze + analyze-floor + lint-shell + platforms + test-guards + test + example journeys

# Without FVM (override SDK commands)
make check DART=dart FLUTTER=flutter

# Individual targets
make analyze                    # static analysis, strict lints
make platforms                  # pana gate — all six platforms must stay attributed
make test-unit                  # every battery + native isolate suites (VM)
make test-web                   # the same batteries in a real web engine (wasm Chrome)
make test-example-matrix        # example UI journeys across a device-profile matrix
make test-example-macos         # example integration smoke on macOS (real engine + GPU)
```

---

## Code style

Match the style of existing code in this repo first. Workspace-wide standards live at:

- **Engineering standards** (seven questions before every decision, env-blind code, twelve-factor checklist): `../docs/universal/development-standards.md`
- **Secrets and environments** (GitHub Environments, branch=env, security walls, files-not-env-vars): `../docs/universal/secrets-and-environments.md`
- **Python tools** (SDK/CLI/MCP three-layer pattern, ruff config, hatchling): `../.claude/rules/python-shared/sdk-cli-mcp-pattern.md`
- **Flutter packages** (opaque boundaries, async at edges, dependency flow): `../.claude/rules/flutter-shared/package-design.md`
- **Comments and doc-comments** (what earns a comment, what doesn't): `../.claude/rules/universal/comments.md`
- **Renaming anything** (sweep all references in one session): `../.claude/rules/universal/rename-hygiene.md`

When in doubt, read existing code in this repo and match it. Per-repo style consistency beats general-best-practice consistency.

---

## Tool-specific notes

**The GPU ceiling is learned from the engine, never queried.** No API reports the raster context's max texture size, and a plugin GL/Metal query would interrogate a different context. `GpuLimits` interprets the engine's own responses (exact / proportional clamp / failure) — both engine backends clamp proportionally (`snapshot_controller_skia.cc`, `snapshot_controller_impeller.cc`), so the longest returned side IS the ceiling. Don't replace this with hardware probing.

**`raster_policy.dart` is a verified platform seam, not an optimization.** The web engine flattens a scene synchronously inside `Scene.toImage` and building the next scene from the same layer tree hollows out the previous one (last-built wins) — so web rasterizes eagerly inside the snapshot loop, native lazily from retained scenes. The web engine also returns premultiplied bytes regardless of the requested format; `straightenAlpha` restores the straight-alpha contract. Both behaviors are pinned by the web batteries.

**Readiness is never a timer.** Offscreen staging exposes one deterministic hook — `MuralStage.ready(context)`, called with a context INSIDE the offscreen tree (assets resolve at the capture's pixel ratio there). Images are the caller's `precacheImage(provider, context)` one-liner. Never add delay/settle-style options.

**The freeze guarantee is synchronous.** `captureBoundary` validates and snapshots scene state inside the call itself, before returning — moving that work into the async body reintroduces tearing on live widgets. The freeze battery test proves it.

**Tests are batteries + two runners.** Platform-blind suites live in `test/batteries/` and run identically on the VM (`test/runners/native_runner_test.dart`) and in wasm Chrome (`test/runners/web_runner_test.dart`); VM-only mechanics are quarantined in `test/platform/native/`. Web tests run through `--wasm` — the DDC lane has a known module-emission bug (upstream report tracked in-repo).

**Seam fidelity is load-bearing, not decoration.** Tile origins stay multiples of 8 (both engines dither gradients with an 8x8 device-anchored matrix) and tiles rasterize `bleed` extra margin around interior seams (seam-split shadows/blurs are otherwise truncated). The differential battery compares tiled output against the framework's own single-shot rasterization byte for byte — don't "simplify" the planner's alignment or bleed math; the receipts live in `docs/UPDATING.md`.

**PNG output is proven against an independent decoder** (`package:image`, dev-only). The encoder is RFC-built (2083/1950/1951); band boundaries must never change output bytes.

---

## Data, secrets, and gitignore

This repo's `.gitignore` is stamped from `../.gitignore.template` (workspace canonical). It already covers:

- `data/.env` and every other `.env` flavor (only `.env.example` / `.env.template` / `.env.sample` are committed)
- `data/auth/` (captured tokens, cookies, OAuth credentials)
- `data/db/*.sqlite*` (full app state — irreplaceable)
- `cookies*.json`, `*.token`, `*.pem`, `*.key`
- `output/`, `debug/`, `logs/`, `cache/`

Never commit a sensitive file even if it's somehow not gitignored — surface to the maintainer instead. The gitignore is defense-in-depth, not the only check.

---

## Working with AI agents

- **Run the test suite before claiming completion.** Always.
- **Don't add `TODO` comments as a substitute for fixing things.** If you found it, you own it — fix in this pass or surface to the maintainer.
- **Don't add backwards-compat shims** for code that hasn't shipped. Code assumes the latest schema and contracts; migrations handle old data once.
- **Don't refactor "for cleanliness" without a stated reason.** Surface the suggestion before changing surrounding code.
- **No co-authored-by AI in commits.** The maintainer is the author.
- **Never force-push protected branches** (`prod`, `main`, `dev`). Never skip pre-commit hooks.

For the engineering philosophy that informs every line of code in this workspace, see `../.claude/rules/universal/dc-engineering-philosophy.md` if available.

---

*This file is stamped from `whuppi/AGENTS.template.md`. The placeholder sections (`{{...}}`) are the only parts customized per repo. Re-stamping refreshes the shared content; per-repo placeholders are preserved.*
