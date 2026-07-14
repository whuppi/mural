# Capability Roadmap

Every capability mural offers or plans, with status. Statuses: `DONE`
(shipped + tested), `BUILDING` (in flight), `PLANNED` (committed, not
started), `BLOCKED` (waiting on something upstream, named), `WONT_DO`
(decided against, with the reason). Nothing ships while an active row
is not `DONE` or `WONT_DO`.

For the architecture see [`ARCHITECTURE.md`](ARCHITECTURE.md). For
maintenance recipes see [`UPDATING.md`](UPDATING.md).

---

## Capture

| Capability | Status | Notes |
|---|---|---|
| Offscreen widget capture (`capture`) | DONE | Isolated render tree; theme/media-query/directionality/localizations inherited from the caller's context |
| Streaming capture (`captureInto`) | DONE | Bands stream to any `Sink<List<int>>`; completes with `MuralImageInfo` |
| On-screen boundary capture (`captureBoundary`) | DONE | `MuralBoundary` for any-size; plain `RepaintBoundary` within the GPU limit |
| Synchronous freeze at the call | DONE | Pinned by the freeze battery test — mid-animation captures show the trigger moment |
| Any-size output (beyond GPU texture limit) | DONE | Tiling under the learned ceiling |
| Bounded memory (`memoryLimitBytes`) | DONE | One band + one tile readback, independent of output size |
| GPU ceiling learning | DONE | Engine-response interpretation; geometric back-off to the GLES 3.0 floor |
| Deterministic readiness (`MuralStage.ready`) | DONE | Offscreen context handed to the callback; images via `precacheImage` |
| Cancellation (`MuralTask.cancel`) | DONE | Cooperative, at tile boundaries; completes with `MuralCancelled` |
| Live progress (`MuralTask.progress`) | DONE | Sealed family: layout / capture (dims, tiles, rows) / encode (bytes) |
| Platform-view detection + typed signal | PLANNED | Platform views have no drawing instructions any Flutter capture can rasterize (flutter/flutter#102866); detect and signal instead of silent blanks |
| Platform-view compositing via native satellite | PLANNED | Core+satellite pattern: OS-level pixels (PixelCopy / drawViewHierarchy) composited into the capture for on-screen boundaries. DRM/protected surfaces stay impossible by OS design |

## Output

| Capability | Status | Notes |
|---|---|---|
| Streaming PNG (in-package encoder) | DONE | RFC 2083/1950/1951; one IDAT per band; proven against `package:image` |
| Raw straight-alpha RGBA | DONE | The escape hatch into any external encoder or video pipeline |
| Straight alpha on premul-readback engines | DONE | `straightenAlpha` on the web seam |
| Seam-exact tiling (single-shot fidelity) | DONE | Dither-aligned tile origins + `bleed` around interior seams; differential test vs the framework's own rasterization gates at the float-rounding floor |
| Off-main-thread encode — native | DONE | Dedicated isolate, `TransferableTypedData` transfers |
| Off-main-thread encode — web | DONE | Browser-native `CompressionStream('deflate')`; inline fallback where absent |
| WebP / JPEG output | WONT_DO | No pure-Dart encoder exists worth shipping; `rawRgba` feeds any external encoder. Revisit only as an FFI satellite if demand is real |

## Platforms

| Capability | Status | Notes |
|---|---|---|
| Android / iOS / macOS / Windows / Linux | DONE | One codebase; pana attributes all six platforms (`make platforms`) |
| Web (wasm lane) | DONE | Full battery suite green in wasm Chrome |
| Web (DDC lane) | WONT_DO | The `--platform chrome` (non-wasm) lane hangs at suite load on Flutter 3.44.4 stable; verified fixed on master (3.46 pre) by the web-test loader rewrite (require.js → DDC library-bundle `$dartLoader`). Stable-only, self-resolving next stable, and the `--wasm` lane is unaffected, so mural runs web tests there. No fix needed |

## Infrastructure

| Capability | Status | Notes |
|---|---|---|
| Strict lints + zero-issue analyzer | DONE | |
| Makefile gates (format / analyze / analyze-floor / platforms / test-guards) | DONE | `make check` is the local mirror of CI |
| Test suite (batteries × runners + differential ground truth) | DONE | Platform-blind batteries run identically on the VM and in wasm Chrome; the differential test compares tiled output against the framework's own rasterization byte for byte. Shape in `ARCHITECTURE.md` |
| Example app | DONE | Three tabs covering every door, every readiness recipe, every typed error; host journeys across six device profiles pixel-verify the captures they pull off screen; the integration smoke decodes a real capture on-device. See `example/README.md` |
| CI (whuppi/ci reusable workflows) | DONE | ci / pr-checks / full-test / release + supporting workflows |
| Published to pub.dev | PLANNED | Banner, description, and topics shipped; `.pubignore` trims the archive. Remaining: run the release train and verify pana 160/160 |
| Upstream reports (DDC hang, web scene semantics, wasm console, region-readback ask) | PLANNED | Evidence collected — including the tiled-fidelity float floor that a `Scene` region-readback API would remove; minimal repros next |
