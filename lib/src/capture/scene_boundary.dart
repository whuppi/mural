import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A repaint boundary that can rasterize arbitrary sub-regions of itself.
///
/// [RenderRepaintBoundary.toImage] only captures full bounds, which the
/// engine clamps to the GPU's maximum texture size. Region capture is the
/// primitive that lifts that limit: any number of within-limit tiles can
/// cover an image of any size.
///
/// Subclassing is what makes this clean — [RenderObject.layer] is
/// `@protected`, so reading it here is sanctioned inheritance rather than
/// an analyzer suppression at a call site.
class MuralSceneBoundary extends RenderRepaintBoundary {
  /// Builds a scene of [bounds] (in this boundary's logical
  /// coordinates) at [pixelRatio] output pixels per logical pixel —
  /// synchronously, so the returned scene is a frozen snapshot of the
  /// boundary's CURRENT painted state. Later repaints cannot alter it;
  /// rasterizing it with `Scene.toImage` can happen any time after.
  ///
  /// Mirrors the scene construction of `OffsetLayer.toImage` — a scale +
  /// translate transform pushed over this boundary's retained layer.
  /// The boundary must have painted at least once. Callers own the
  /// returned scene and must dispose it.
  ui.Scene buildRegionScene(Rect bounds, {required double pixelRatio}) {
    final offsetLayer = layer! as OffsetLayer;
    final builder = ui.SceneBuilder();
    final transform = Matrix4.diagonal3Values(pixelRatio, pixelRatio, 1)
      ..translateByDouble(
        -(bounds.left + offsetLayer.offset.dx),
        -(bounds.top + offsetLayer.offset.dy),
        0,
        1,
      );
    builder.pushTransform(transform.storage);
    return offsetLayer.buildScene(builder);
  }

  /// Whether the boundary has a retained layer to capture from — false
  /// until the first paint.
  bool get hasPainted => layer != null;
}

/// Marks an on-screen subtree as capturable at any size.
///
/// A drop-in replacement for [RepaintBoundary] whose subtree
/// `Mural.captureBoundary` can rasterize beyond the GPU texture limit:
///
/// ```dart
/// final boundaryKey = GlobalKey();
///
/// MuralBoundary(
///   key: boundaryKey,
///   child: TranscriptView(messages),
/// )
///
/// final shot = await mural.captureBoundary(boundaryKey);
/// ```
///
/// A plain [RepaintBoundary] can also be captured, but only up to the
/// device's texture limit — the framework exposes no oversize path for
/// foreign boundaries.
class MuralBoundary extends SingleChildRenderObjectWidget {
  /// Creates a capturable boundary around [child].
  const MuralBoundary({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => MuralSceneBoundary();
}
