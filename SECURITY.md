# Security Policy

## Reporting a vulnerability

Report privately via [GitHub Security Advisories](https://github.com/whuppi/mural/security/advisories/new). Do not open a public issue.

## The surface

Mural takes a widget tree in and produces image bytes out. It is pure Dart with zero runtime dependencies: no filesystem access, no network access, no paths, no permissions, no native code. The package never writes a file — not even a temporary one; output goes only to the caller's sink or return value. `dart:io` cannot compile into the package (`make test-guards` enforces it mechanically).

## What's in scope

- **Cross-capture pixel leaks** — any pixels from a previous capture, another strip, or uninitialized buffer memory appearing in a capture's output (buffer reuse, bleed-cropping errors, padding rows).
- **Spec-violating PNG output** — the encoder is in-package (RFC 2083/1950/1951); output that is malformed in a way that could trigger vulnerabilities in downstream decoders is our bug.
- **Memory-budget bypasses** — a capture whose working memory grows past `memoryLimitBytes` plus the documented tile readback, or unbounded allocations from crafted widget or option values.
- **Isolate/worker mishandling** — captured bytes taking any path other than the documented one (worker in, encoded bytes out).

## What's NOT in scope

- **What your app chooses to capture.** Mural rasterizes the widget the caller passes, with the caller's own privileges. If your app can show it, your app can capture it — capturing sensitive UI is an app decision, not a package vulnerability.
- **Engine rasterization bugs** not caused by how this package drives the engine — report to [flutter/flutter](https://github.com/flutter/flutter/issues).
- **Platform views rendering blank** — a documented Flutter limitation (no drawing instructions exist to rasterize), not an information leak.
- **Resource use the caller configured** — a huge capture with a matching `memoryLimitBytes` uses the memory the caller granted; that is the contract working, not a denial of service.
- **Crashes from unusual widgets or option values** — bugs, not vulnerabilities. Report them as [regular issues](https://github.com/whuppi/mural/issues).

## Operational notes (known, accepted)

These are conscious trade-offs, documented so they aren't mistaken for oversights:

- **Captured pixels live in ordinary heap memory.** Band buffers, readbacks, and the finished image are normal Dart allocations; mural does not zero or lock them. A secret rendered into a capture exists in RAM exactly like any image the app renders on screen.
- **`rawRgba` hands the caller unencoded pixels.** Everything downstream of that hand-off — storage, transmission, redaction — is the caller's responsibility.
- **The fidelity tests guarantee correctness, not confidentiality.** Byte-identical output is a rendering promise; protecting the resulting image is the app's job.

## Response

Valid reports are fixed and shipped as patch versions.
