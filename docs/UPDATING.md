# Updating mural

The maintenance bible: the engine behaviors mural is built on and must
re-verify when dependencies move, plus the recipes for common changes.
For the architecture see [`ARCHITECTURE.md`](ARCHITECTURE.md). For
capability status see [`CAPABILITY_ROADMAP.md`](CAPABILITY_ROADMAP.md).

---

## The pinned-behavior watchlist

Mural's correctness rests on verified engine behavior, not API
contracts. Re-check each row on every Flutter SDK bump; each is pinned
by a test that fails if the behavior changes.

| Pinned behavior | Where verified | Pinned by |
|---|---|---|
| Oversize snapshots clamp PROPORTIONALLY — `scale = min(1, maxSize / longestSide)` — on both backends | `engine/src/flutter/shell/common/snapshot_controller_skia.cc`, `snapshot_controller_impeller.cc` | `gpu_limits_battery` (max-side learning) |
| Async `Scene.toImage` does not throw on oversize (the throw is the `toImageSync` path) | same files | first-capture learning path |
| GLES 3.0 mandates ≥2048 max texture size | Khronos GLES 3.0 spec §6.1.4 | `GpuLimits.specFloor` |
| Web: `Scene.toImage` flattens synchronously inside the call | `engine/.../web_ui/lib/src/engine/layer/layer_scene_builder.dart` (`toImage` → `layerTree.flatten`) | freeze battery on the web runner |
| Web: building a second scene from the same layer tree hollows out the first (last-built wins) | empirically pinned (see `raster_policy_web.dart`) | multi-band batteries on the web runner |
| Web: readback is premultiplied regardless of the requested `ImageByteFormat` | empirically pinned | `rawRgba` battery on the web runner |
| `RootElementMixin.assignOwner` installs a `BuildScope`, so out-of-scope `setState` in the isolated tree queues silently | `flutter/lib/src/widgets/framework.dart` | readiness batteries |
| Web tests must run the `--wasm` lane; the DDC lane hangs on a module-emission bug | flutter-tools (upstream report tracked in repo tasks) | `make test-web` runs `--wasm` |
| Gradients dither via an 8x8 ordered matrix anchored to DEVICE coordinates — tile origins must stay multiples of 8 | Skia `src/opts/SkRasterPipeline_opts.h` (`HIGHP_STAGE(dither)`); Impeller `impeller/compiler/shader_lib/impeller/dithering.glsl` (`IPOrderedDither8x8`, a copy of Skia's) | differential ground-truth battery |
| Raster effects (shadows, blurs) compute against the surface being rasterized — an effect split by a tile edge is truncated without bleed | Skia `SkMaskFilterBase.filterMask` (device-space masks, clip-relative margins); pinned empirically by the split-shadow measurement | differential ground-truth battery |
| Tiled rasterization has a float-rounding floor: the same geometry under a different translation re-rounds gradient/AA math in the last ULP (measured floor in `ARCHITECTURE.md` "Seam fidelity") | inherent to `Scene.toImage` (no region-readback API — a tile MUST translate) | differential battery's floor gates |

## S1 — Flutter SDK bump

1. Update `.fvmrc`; `fvm install && fvm flutter pub get`.
2. `make check` — the batteries pin every engine behavior above; a red
   web runner usually means a web-engine behavior in the watchlist
   moved. Update the seam (`raster_policy_*.dart`) and its watchlist
   row together, never one without the other.
3. Re-read the two snapshot-controller files if capture sizes behave
   differently; update `gpu_limits.dart`'s doc if the clamp semantics
   changed.

## S2 — Add an output format

1. New encoder under `lib/src/encode/` composing `png_chunks.dart` /
   `png_filter.dart`-style shared pieces where applicable.
2. Extend `MuralFormat` and the `_encodeBands` switch in
   `lib/src/mural.dart` — the compiler walks you to every site.
3. Add a round-trip battery against an independent decoder; both
   runners must pass.

## S3 — Toolchain pins

`tool/versions.env` pins PANA_VERSION (the exact analyzer pub.dev
runs). `tool/ci/upgrade.sh` — driven by the daily `upgrade-check.yml` —
bumps it in its own reviewed PR. The `tool/*.sh` gates are stamped
verbatim from `whuppi/ci`; never edit a stamped copy in place
(`pr-checks` fails on drift), change the canonical and re-stamp.

## S4 — Release

The release tooling owns versions, tags, and publishing. You write the
human summary in the right lane's changelog (`CHANGELOG.pre.md` for
`-dev.N` prereleases, `CHANGELOG.md` for stables) per the STANDARD
block at the top of each file, and trigger `release.yml`.

The pipeline itself — gate → discover → publish across the two lanes,
and the GitHub environment approval that gates every pub.dev push — is
the shared engine; see whuppi/ci/docs/ARCHITECTURE.md "The release
surface".

## Troubleshooting

- **Web suite hangs at "loading" forever, 0% CPU** — you ran the DDC
  lane. Use `make test-web` (wasm). If wasm itself hangs, a stale
  incremental build is the usual cause: `fvm flutter clean` and never
  reuse a test filename for different contents.
- **Web failure output is empty ("See exception logs above")** — the
  wasm lane drops browser console output. Make the failing test carry
  its evidence in a plain `test()`'s failure message (the one channel
  the JSON reporter keeps), or attach Chrome DevTools.
- **Capture is blank where an image should be** — the image hadn't
  decoded when the shot was taken. Offscreen: use
  `MuralStage(ready: (context) => precacheImage(provider, context))`.
  On-screen: what's painted is what you get; capture after the image
  is visible.
