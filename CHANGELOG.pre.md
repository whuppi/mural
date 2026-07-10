# Prerelease Changelog

<!--
═══════════════════════════════════════════════════════════════════════
CHANGELOG STANDARD — read before editing. Applies to both changelogs.
═══════════════════════════════════════════════════════════════════════
Two INDEPENDENT lane changelogs — do NOT mirror one from the other:
  • CHANGELOG.pre.md — the prerelease lane (`## X.Y.Z-dev.N`). Add an
    entry per prerelease you cut on dev.
  • CHANGELOG.md — the stable lane (`## X.Y.Z`). Add an entry per stable
    release, CONSOLIDATING the prerelease entries that ship under it.
They share prose but track their OWN version sequences. There is no
`cp + sed` regen: that mirror falsely assumed every prerelease becomes a
same-numbered stable, so it manufactured stable headings for versions
that never shipped — which the release tooling's `--check-versions` flags.
Hand-edit each lane's file directly.

ADDING A VERSION
  Add a heading at the TOP (newest first) of the right lane's file and
  write the summary. Exactly ONE new (untagged) version may sit at the
  top of each file — every heading BELOW it must already have its git tag
  (or a verified `release: no-tag` HTML-comment directive). `--check-versions`
  enforces this at PR + release time: a second un-released version is
  rejected, since it would collapse into the one release the merge cuts.
  Versions, commit lists, tags, publishing — the release tooling owns all
  of it; you only write the human summary.

ENTRY SHAPE
  ## X.Y.Z-dev.0
  <one-line prose lead — only to frame a big release or signal "no
   behavior change"; omit when the bullets speak for themselves>
  - **Breaking:** <what changed> → <migration step, INLINE>   ← always first
  - <upgrade action>                                          ← any required action next
  - Added/Changed <capability or improvement>                ← then improvements
  - Fixed <bug> ([#N](issue-url) reported by [@user](abs-url), [PR #N](abs-url))  ← fixes last

  Order IS the grouping — Breaking → action → added/changed → fixed. No
  `###` subsections: bullet order carries the categories. Only Breaking
  is bold-tagged; everything else is verb-led. Fixes start with "Fixed".

  EXCEPTION — the genesis entry (a ground-up build, no prior published
  version) uses facet tags instead of deltas: **API:** / **Platforms:** /
  etc., describing the new package's dimensions. See the 1.0.0-dev.0 entry.

CONTENT RULES (never change)
  • Migrate from the entry ALONE — breaking changes inline, old → new.
    (pub.dev freezes each version's CHANGELOG as a snapshot, so an entry
    can't rely on anything that later moves.)
  • NEVER link a living doc (README, docs/*) from an entry — it rots when
    the doc moves on.
  • Links point only at IMMUTABLE targets — a PR, commit, or issue:
    ([#N](https://github.com/whuppi/mural/issues/N) reported by
    [@user](https://github.com/user), [PR #N](https://github.com/whuppi/mural/pull/N)).
    Credit the issue + reporter when a reported issue drove the fix; the PR
    (or commit) link alone otherwise.
  • No capability inventories — "what's shipped" lives in README +
    docs/CAPABILITY_ROADMAP.md; the changelog says only what CHANGED.
═══════════════════════════════════════════════════════════════════════
-->

<!-- Add new versions below, newest first. -->

## 1.0.0-dev.0

First release — capture any Flutter widget as an image, at any size: offscreen widgets, on-screen snapshots, and captures beyond the GPU texture limit (flutter/flutter#118024), streamed in constant memory.

- **Capture:** three doors on one `Mural` facade — `capture` (offscreen, staged with the caller's theme and text direction), `captureBoundary` (on-screen, snapshotted synchronously at the call), `captureInto` (streams into any `Sink<List<int>>`)
- **Any size:** captures in strips under a GPU limit learned from the engine's own responses; output size bounded by neither the GPU nor memory
- **Fidelity:** strip output byte-identical to a one-shot render — strip origins aligned to the engines' 8x8 dither matrix, `bleed` margin around interior seams for shadows and blurs; verified by a differential test against the framework's own rasterization
- **Memory:** peak working memory is one band plus one strip readback, set by `memoryLimitBytes`, independent of output size
- **Readiness:** one deterministic signal, `MuralStage.ready(context)` — no timer options
- **Tasks:** every door returns a `MuralTask` — awaitable, live progress (sealed `MuralProgress` family), cooperative cancellation
- **Output:** in-package streaming PNG (RFC 2083/1950/1951) encoded off the UI thread (isolate on native, `CompressionStream` on web); raw straight-alpha RGBA as the escape hatch
- **Errors:** sealed `MuralError` family — every failure typed and named, including `MuralBudgetError` when the memory budget and bleed cannot form a plan
- **Platforms:** Android, iOS, macOS, Windows, Linux, web — one codebase, zero runtime dependencies
- **SDK:** requires Dart >=3.11.0
