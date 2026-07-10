# Contributing

## Setup

```bash
git clone https://github.com/whuppi/mural.git
cd mural
make hooks               # activates commit-msg + pre-commit (run once)
fvm install              # downloads the SDK version pinned in .fvmrc
fvm flutter pub get
```

**Requires:** [FVM](https://fvm.app) (`.fvmrc` pins the exact Flutter
version). No native toolchains: mural is pure Dart with zero runtime
dependencies, so there is nothing platform-specific to build. The web
test lane needs a local Chrome.

**Without FVM:** all Makefile commands accept `DART` and `FLUTTER`
overrides:

```bash
make check DART=dart FLUTTER=flutter
```

## Before submitting a PR

```bash
make check
```

Runs `format` (check mode) + `analyze` (strict lints) + `analyze-floor`
(the OLDEST in-range dependencies must still analyze clean — the lower
bounds in pubspec are promises) + `lint-shell` + `platforms` (pana must
attribute all six platforms) + `test-guards` (the mechanical import
rules) + `test` + the example's journey matrix. Must pass. Don't
suppress with `// ignore:` — fix the underlying issue.

## PR workflow

All PRs target `dev`. That's the only branch contributors touch.

```
your fork / feature branch ──PR──► dev
                                    ↓ CI: the same make targets as local
                                    ↓ PR title: Conventional Commits (feat: / fix: / etc.)
                                    ↓ squash-merge when green
```

You don't write changelog entries, bump versions, or touch `prod`.
The maintainer handles releases.

## Code style

- Match existing code in the repo.
- **Expected failures are typed values, never throws to the caller.**
  Every door returns a `MuralTask`; failures complete it with a sealed
  `MuralError` (message says what to do next). Throws are reserved for
  programmer error. There is no `MuralUnknownError` — every stop has a
  name.
- **Platform code lives ONLY behind the two conditional-export seams**
  (`capture/raster_policy.dart`, `encode/png_worker.dart`). The DEFAULT
  target must compile everywhere — pub.dev's analyzer attributes to
  every platform whatever the default pulls in. `make platforms` guards
  it.
- **No `dart:io` anywhere in `lib/` or `test/`.** Mural is pure
  cross-platform Dart; `dart:isolate` lives only in
  `png_worker_native.dart` and `dart:js_interop` only in the two web
  seam files. `make test-guards` enforces all three mechanically.
- **Every engine-behavior claim needs evidence.** Mural is built on
  verified engine behavior, not API contracts — a new claim gets a
  watchlist row in `docs/UPDATING.md` (source link) AND a test that
  pins it. Never assume; read the engine source.
- **Readiness is never a timer.** No delay/settle knobs, anywhere. The
  one hook is `MuralStage.ready(context)`.
- Tests are platform-blind batteries under `test/batteries/`, run
  identically by both runners (VM and wasm Chrome); VM-only mechanics
  are quarantined in `test/platform/native/`. Assertions are behavioral
  against declared truths — exact bytes, exact dimensions — never
  liveness. Read the test-architecture section in
  [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) before adding tests.

## Adding a capability

Step-by-step checklists in [`docs/UPDATING.md`](docs/UPDATING.md).
