import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/rendering.dart' show BoxConstraints;
import 'package:flutter/widgets.dart' show BuildContext;

/// How an offscreen widget is staged before capture: the constraints it
/// lays out under, what's painted behind it, and the caller's readiness
/// signal for asynchronous content.
///
/// Only `Mural.capture` and `Mural.captureInto` take a stage — an
/// on-screen boundary is already laid out, so `Mural.captureBoundary`
/// has nothing to stage.
class MuralStage {
  /// Creates a stage. The defaults lay the widget out at its intrinsic
  /// size on a transparent background and capture the first frame.
  const MuralStage({
    this.constraints = const BoxConstraints(),
    this.background,
    this.ready,
  });

  /// Layout constraints for the widget.
  ///
  /// Defaults to fully loose (unbounded), letting the widget pick its
  /// intrinsic size. Bound one axis for content that grows: a chat
  /// transcript is typically `BoxConstraints(maxWidth: 400)` — fixed
  /// width, intrinsic height. The widget must resolve to a finite size
  /// or the capture throws `MuralLayoutError`.
  final BoxConstraints constraints;

  /// Color painted behind the widget.
  ///
  /// `null` (the default) captures with a transparent background.
  final Color? background;

  /// The readiness signal for the widget's asynchronous content. Only
  /// the widget's author knows what it loads — images, documents,
  /// anything — so readiness is the caller's signal, never a timed
  /// guess by the package.
  ///
  /// Called once after the widget's first offscreen frame with a
  /// context INSIDE the offscreen tree; the capture waits for the
  /// returned future, rebuilds, and shoots. For images, the framework's
  /// own completion signal is one line — and using the offscreen
  /// context matters, because assets resolve at the capture's pixel
  /// ratio, not the screen's:
  ///
  /// ```dart
  /// MuralStage(ready: (context) => precacheImage(photo, context))
  /// ```
  ///
  /// Widgets that load internally expose their own signal the same way:
  ///
  /// ```dart
  /// MuralStage(ready: (_) => chartController.dataLoaded)
  /// ```
  ///
  /// Prefer loading data before building the widget — a widget handed
  /// complete data needs no signal at all.
  final Future<void> Function(BuildContext context)? ready;
}
