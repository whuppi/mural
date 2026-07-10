# mural example

A Flutter app exercising every `mural` capability — offscreen widget
capture, on-screen freeze shots, and streamed captures far beyond the
GPU texture limit. Tap Run on an op card, watch the status line, and
inspect the result on a checkerboard card (tap it to zoom). Every
demo widget is built in code; nothing touches assets or the network.
Runs on macOS, iOS, Android, Windows, Linux, and web.

## Run

```bash
cd example

# desktop
fvm flutter run -d macos

# web
fvm flutter run -d chrome

# any connected device
fvm flutter run -d <device>
```

## Tests

```bash
# host-VM journey matrix — the UI driven end to end across six device
# profiles; captures are pulled back off the screen and their PIXELS
# verified (RTL mirroring, decoded-photo coverage, exact output sizes);
# no device needed:
cd example
fvm flutter test test/journeys

# integration smoke — one pass through every door on a REAL target,
# plus a direct capture decoded through an independent PNG decoder:
fvm flutter test integration_test/mural_smoke_test.dart -d macos
fvm flutter test integration_test/mural_smoke_test.dart -d <device>

# or from the package root:
cd ..
make test-example-matrix
make test-example-macos

# one real target at a time (CI's full-test runs each of these):
make test-example-android   # also: -ios, -linux, -windows, -web
make verify-macos           # release build; also: -android, -ios, -linux, -windows, -web
```

The journeys drive the real package — every capture rasterizes on the
test environment's actual engine. Their robots live in
`test_support/`, a local package shared by `test/journeys` and
`integration_test` through one `package:` import, so neither root
reaches across the other with `../` paths.

## What's inside

Three tabs, one per capture door:

| Tab | API | What it covers |
|---|---|---|
| **Offscreen** | `capture()` | A transcript that is never on screen, at 1x and 3x; narrow stage constraints; transparent background over the checkerboard; theme inheritance (toggle dark and re-run); right-to-left directionality; the two readiness recipes (`precacheImage` and a widget that signals its own data); and every typed error — zero-size layout, unbounded height, a throwing build |
| **On screen** | `captureBoundary()` | The synchronous freeze — a shot mid-animation with no tearing; a burst of three calls from one trigger; a plain `RepaintBoundary` within the GPU limit; and the typed error for an unmounted key |
| **Stream** | `captureInto()` | A poster streamed through a 1 MB working budget; a 10,000-row capture far beyond the GPU texture limit (the flutter#118024 case); cooperative cancellation from the status bar; and the raw straight-RGBA escape hatch |

The status bar above the tabs reports every op — live progress with a
Cancel button while a task runs, then the result's dimensions and byte
count, or the typed `MuralError` when an error op fires. Results render
on a checkerboard so alpha is visible; tap one to inspect it zoomed.

## One file on purpose

The whole app lives in `lib/main.dart` because pub.dev renders that
file as the package's Example tab — splitting it would hide everything
else from that page.

## No `dart:io`

Every demo widget is generated in code and every capture stays in
memory. The same code compiles unchanged for native and web.
