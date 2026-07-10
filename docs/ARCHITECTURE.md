# mural — Architecture

> **Type:** architecture · **Scope:** mural · **Status:** SHIPPED · **Last verified:** 2026-07-10
> **Companion docs:** [`CAPABILITY_ROADMAP.md`](CAPABILITY_ROADMAP.md) (status per capability) · [`UPDATING.md`](UPDATING.md) (maintenance recipes)

What the package IS: the contract, the capture pipeline, the file tree,
the platform seams, and the test architecture. When this doc and the
code disagree, the code wins — then fix this doc.

## The contract

- **Any size.** The GPU clamps a single rasterization to its maximum
  texture size (flutter/flutter#118024). Mural rasterizes in tiles no
  larger than the learned ceiling, assembles horizontal bands, and
  streams the encode — output dimensions are bounded by neither the GPU
  nor memory.
- **Bounded memory.** Peak working memory is one band buffer plus one
  tile readback, sized by `MuralOptions.memoryLimitBytes` — never by
  output size. `captureInto` streams encoded bytes to a caller sink so
  the whole image never exists in memory.
- **The frozen moment.** `captureBoundary` snapshots the boundary's
  painted state synchronously, inside the call — the result shows that
  exact instant even while the widget keeps animating. Scheduling (a
  timer, a gesture, the widget's own logic) is the caller's one-liner;
  moment-exactness is the package's guarantee.
- **Deterministic readiness, never timers.** Offscreen staging exposes
  one hook — `MuralStage.ready(context)`, called with a context inside
  the offscreen tree. Images are `precacheImage(provider, context)`;
  anything else uses its own widget's completion signal.
- **Typed everything.** Errors are a sealed `MuralError` family;
  progress is a sealed `MuralProgress` family (layout / capture /
  encode, each carrying its phase's data); a capture is a `MuralTask` —
  awaitable, observable, cancellable.
- **Straight alpha, everywhere.** Output is non-premultiplied RGBA (or
  PNG encoded from it), including on engines whose readback is
  premultiplied (see the seams below).
- **Zero runtime dependencies.** Flutter only. PNG is encoded
  in-package (RFC 2083/1950/1951), proven against an independent
  decoder in tests.

## The pipeline

```
capture(widget) ──► RenderHost           offscreen render tree: builds,
                    │                    lays out, paints, settles via
                    │                    MuralStage.ready — no timers
captureBoundary ──► MuralSceneBoundary   the painted boundary
                    │
                    ▼ snapshot()         SYNCHRONOUS: plan the tile grid
                    CaptureEngine        (GpuLimits ceiling × memory
                    │                    budget), build one frozen scene
                    │                    per tile
                    ▼ run()
                    tiles → bands        rasterize, read back straight
                    │                    RGBA, blit into band buffers
                    ▼
                    PngWorker            filter (Sub/Up) + deflate + IDAT
                    │                    framing, off the UI thread
                    ▼
                    Sink<List<int>>      caller sink (captureInto) or an
                                         in-memory collector (capture)
```

**GPU ceiling learning** (`GpuLimits`): no API reports the raster
context's maximum texture size, and querying GL/Metal directly would
interrogate a different context than the engine rasterizes with. The
engine's own responses are interpreted instead — an exact result
teaches nothing, a proportional clamp reveals the ceiling from the
longest returned side (both engine backends clamp proportionally:
`snapshot_controller_skia.cc`, `snapshot_controller_impeller.cc`), and
a failure backs off geometrically to the GLES 3.0 spec floor (2048).
The learned ceiling lives on the `Mural` instance; reuse one instance
and later captures plan correctly without rediscovery.

## The file tree

```
lib/
  mural.dart                    public barrel
  src/
    capture/
      capture_engine.dart       tile planning + frozen scenes + banding
      gpu_limits.dart           the ceiling learner
      raster_policy.dart        SEAM: native ↔ web engine constraints
      raster_policy_native.dart   lazy rasterization, straight readback
      raster_policy_web.dart      eager rasterization, premul readback
      readback.dart             straightenAlpha (premul → straight)
      scene_boundary.dart       MuralBoundary widget + region scenes
    encode/
      crc32.dart                incremental CRC-32
      png_chunks.dart           PNG container framing (shared)
      png_encoder.dart          streaming encoder (filter + Dart zlib)
      png_filter.dart           Sub/Up scanline filter (shared)
      png_worker.dart           SEAM: stub ↔ isolate ↔ CompressionStream
      png_worker_stub.dart        inline (fallback platforms)
      png_worker_native.dart      dedicated isolate (dart:io platforms)
      png_worker_web.dart         browser-native CompressionStream
      zlib_encoder.dart         pure-Dart RFC 1950/1951 stream
    host/
      render_host.dart          the isolated offscreen render tree
    types/
      errors.dart               sealed MuralError family
      image.dart                MuralImageInfo / MuralImage
      options.dart              MuralOptions + MuralFormat
      progress.dart             sealed MuralProgress family
      stage.dart                MuralStage (offscreen staging)
      task.dart                 MuralTask (Future + progress + cancel)
    mural.dart                  the Mural facade (three doors)
```

## The platform seams

Two conditional-export seams; everything else is one shared codebase.

| Seam | Native (`dart:io`) | Web (`dart:js_interop`) | Fallback |
|---|---|---|---|
| `png_worker.dart` | dedicated isolate, `TransferableTypedData` hand-offs | browser `CompressionStream('deflate')` — engine-native zlib, no worker script | inline cooperative encoder |
| `raster_policy.dart` | scenes rasterize lazily (bounded memory) | scenes rasterize eagerly inside the snapshot loop; readback is unpremultiplied | — |

The web constraints are verified engine behavior, not guesses: the web
engine flattens a scene synchronously inside `Scene.toImage`, building
the next scene from the same layer tree hollows out the previous one
(last-built wins), and readback returns premultiplied bytes regardless
of the requested format. All three behaviors are pinned by the web
batteries — if a future engine changes them, tests say so.

## Seam fidelity

The tiled output is byte-identical to what the engine's own single-shot
rasterization would produce, enforced by a differential test (same
widget through `RenderRepaintBoundary.toImage` and through the
multi-band pipeline, compared byte for byte). Three mechanisms make
that true:

1. **Dither alignment.** Both engines dither gradients with an 8x8
   ordered matrix anchored to device coordinates, so a tile whose origin
   is not a multiple of 8 shifts every dithered pixel by one level. The
   planner keeps interior band heights and tile widths multiples of 8.
2. **Bleed.** Shadows and blurs are computed against the surface being
   rasterized; a tile edge truncates their source, so a seam-split
   effect renders visibly wrong (measured up to 66 levels off). Each
   tile rasterizes `MuralOptions.bleed` extra margin on interior sides
   and the blit crops it, giving every effect the neighborhood the
   single-shot render has. Image borders get no bleed — they ARE the
   single-shot render's own surface edges.
3. **The float floor.** A tile must translate content to rasterize it
   (there is no region-readback API), and the same gradient/AA math
   re-rounds in the last ULP under a different translation. Measured
   per 4.2M pixels: 5 differing bytes on the software rasterizer (at
   most one antialiased edge pixel off by 8 levels) and 66 on the web
   GPU (all off by one). This is the floor of any tiled renderer; the
   differential test gates on it tightly.

A budget too small to hold a few aligned rows plus the bleed fails with
a typed `MuralBudgetError` — the plan never silently drops either
guarantee.

## Error physics

Nothing above the engine seams throws to the caller. `capture` and
`captureBoundary` validate and snapshot synchronously inside the call;
any failure — there or later in the pipeline — completes the returned
`MuralTask` with a typed `MuralError`. Unexpected exceptions are wrapped
(`MuralEncodeError` with the original as `cause`) rather than escaping
into the zone, so awaiting the task is the ONLY failure surface. Every
stop has a name; there is no `MuralUnknownError`.

## Test architecture

```
test/
  batteries/          platform-blind suites (run EVERYWHERE)
    capture_battery.dart      the facade spec: all three doors, freeze,
                              banding invisibility, readiness, errors
    encode_battery.dart       PNG round-trips vs an independent decoder
    gpu_limits_battery.dart   ceiling learning + back-off
    worker_battery.dart       the PngWorker contract per platform
  harness/            shared fixtures (the quadrants test card)
  platform/native/    VM-only mechanics (isolate hand-off semantics)
  runners/
    native_runner_test.dart   every battery on the VM
    web_runner_test.dart      the IDENTICAL batteries in wasm Chrome
```

One spec, two worlds: a platform-dependent result is a red build, not
an unknown. The web lane runs through `flutter test --platform chrome
--wasm` — the lane Flutter's own framework CI uses; the DDC lane has a
module-emission bug that hangs suite loading (upstream report tracked
in the repo tasks).

Above the package suites sit the example app's lanes — a host-VM
journey matrix across six device profiles (pixel-verifying the captures
it pulls off screen) and an on-device integration smoke. Those are
documented in [`example/README.md`](../example/README.md) and run via
`make test-example-matrix` / `make test-example-macos`.

## The one-line summary

> Three doors on one facade; a synchronous freeze; tiles under a
> learned GPU ceiling; bands under a memory budget; a streaming
> in-package PNG encoder; two verified platform seams; one battery
> spec that must pass on the VM and in a real browser.
