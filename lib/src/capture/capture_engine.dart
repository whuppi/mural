import 'dart:async' show unawaited;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:mural/src/capture/gpu_limits.dart';
import 'package:mural/src/capture/raster_policy.dart';
import 'package:mural/src/capture/readback.dart';
import 'package:mural/src/capture/scene_boundary.dart';
import 'package:mural/src/types/errors.dart';

/// Rasterizes a painted [MuralSceneBoundary] of any size into horizontal
/// bands of raw straight-alpha RGBA, within a fixed memory budget.
///
/// Capture is two-phase. [snapshot] runs synchronously at the moment of
/// the capture call: it plans an integer pixel grid of tiles no larger
/// than the GPU ceiling and builds one frozen scene per tile — cheap
/// display-list references, not pixels. From that instant the captured
/// content is immutable; a live boundary can repaint freely without
/// tearing the output. [run] then rasterizes the frozen scenes tile by
/// tile, assembling bands delivered top-to-bottom. Peak memory is one
/// band plus one tile readback, independent of output size.
///
/// The first capture on a device may discover the GPU ceiling mid-flight
/// via the shared `GpuLimits` tracker; the engine then replans and
/// restarts. Replanning re-snapshots the boundary — on a live boundary
/// that can land one frame later, and it happens at most once per
/// device because the learned ceiling persists on the `Mural` instance.
/// Discovery can only happen on the first tile, so no band is ever
/// emitted twice.
final class CaptureEngine {
  /// Creates an engine capturing [boundary] at [pixelRatio].
  CaptureEngine({
    required this.boundary,
    required this.pixelRatio,
    required this.memoryLimitBytes,
    required this.bleed,
    required this.limits,
    required this.isCancelled,
    required this.onTile,
  });

  /// The painted boundary to rasterize. Must have painted at least once.
  final MuralSceneBoundary boundary;

  /// Output pixels per logical pixel.
  final double pixelRatio;

  /// Budget for the band buffer; tile readbacks ride within the same
  /// order of magnitude.
  final int memoryLimitBytes;

  /// Seam margin in logical pixels — see `MuralOptions.bleed`.
  final double bleed;

  /// Shared ceiling knowledge, updated as captures teach it.
  final GpuLimits limits;

  /// Probed between tiles; a true return aborts with [MuralCancelled].
  final bool Function() isCancelled;

  /// Called after each tile with tiles completed, total tiles in the
  /// plan, and pixel rows already delivered to [run]'s band callback.
  final void Function(int tilesDone, int tileCount, int rowsDelivered) onTile;

  /// True until a first tile rasterizes at face value, proving the
  /// current ceiling; back-offs from failures reset the proof burden.
  bool _ceilingUnproven = true;

  int _width = 0;
  int _height = 0;
  _TilePlan? _plan;

  /// Both engines dither gradients with an 8x8 ordered matrix anchored
  /// to DEVICE coordinates (Skia's raster-pipeline `dither` stage;
  /// Impeller's IPOrderedDither8x8, which copies it). A tile whose
  /// origin is a multiple of 8 reproduces the single-shot pattern
  /// exactly; any other offset shifts the matrix and every dithered
  /// pixel drifts by one level. Interior tile origins therefore stay
  /// multiples of this.
  static const int _ditherPeriod = 8;

  /// The seam margin in device pixels, rounded UP to the dither period
  /// so cropping the margin preserves the alignment above.
  late final int _bleedPx =
      ((bleed * pixelRatio).ceil() + _ditherPeriod - 1) ~/
      _ditherPeriod *
      _ditherPeriod;

  /// Output width in pixels, fixed by [snapshot].
  int get outputWidth => _width;

  /// Output height in pixels, fixed by [snapshot].
  int get outputHeight => _height;

  /// Freezes the boundary's current painted state — synchronously, so
  /// the capture reflects this exact moment no matter what the boundary
  /// paints afterwards. Must be called before [run].
  void snapshot() {
    _width = (boundary.size.width * pixelRatio).ceil();
    _height = (boundary.size.height * pixelRatio).ceil();
    _plan = _buildPlan();
  }

  _TilePlan _buildPlan() {
    final ceiling = limits.planningCeiling(_width > _height ? _width : _height);
    final rowBytes = _width * 4;

    // Columns first: a width beyond the ceiling splits into columns
    // whose interior seams need horizontal bleed and dither-aligned
    // origins. A single column has no vertical seams — no cost.
    final int tileWidth;
    final int hBleed;
    if (_width <= ceiling) {
      tileWidth = _width;
      hBleed = 0;
    } else {
      hBleed = _bleedPx;
      final inner = ceiling - 2 * hBleed;
      tileWidth = inner - inner % _ditherPeriod;
      if (tileWidth < _ditherPeriod) {
        throw MuralBudgetError(
          'A bleed of $hBleed px per side leaves no room inside the '
          '$ceiling px GPU tile ceiling — lower MuralOptions.bleed.',
        );
      }
    }
    final columns = (_width + tileWidth - 1) ~/ tileWidth;
    final rasterWidth = tileWidth + 2 * hBleed;

    // One band when the full height fits the ceiling AND the budget
    // (band buffer + one tile readback): no horizontal seams, no
    // vertical bleed, no alignment concern.
    var vBleed = 0;
    var bandRows = _height;
    final singleBandFits =
        _height <= ceiling &&
        _height * rowBytes + _height * rasterWidth * 4 <= memoryLimitBytes;
    if (!singleBandFits) {
      vBleed = _bleedPx;
      // Budget: one band buffer (bandRows tall) plus one tile readback
      // (bandRows + bleed on each interior edge). The GPU ceiling bounds
      // the readback's height too.
      final available = memoryLimitBytes - 2 * vBleed * rasterWidth * 4;
      final denominator = rowBytes + rasterWidth * 4;
      bandRows = available > 0 ? available ~/ denominator : 0;
      final ceilingRows = ceiling - 2 * vBleed;
      if (bandRows > ceilingRows) {
        bandRows = ceilingRows;
      }
      bandRows -= bandRows % _ditherPeriod;
      if (bandRows < _ditherPeriod) {
        throw MuralBudgetError(
          'memoryLimitBytes ($memoryLimitBytes) cannot hold even '
          '$_ditherPeriod pixel rows plus a $vBleed px bleed at '
          '$_width px output width — raise the budget or lower '
          'MuralOptions.bleed.',
        );
      }
    }

    final bands = (_height + bandRows - 1) ~/ bandRows;
    final plan = _TilePlan(
      tileWidth: tileWidth,
      bandRows: bandRows,
      columns: columns,
      bands: bands,
      hBleed: hBleed,
      vBleed: vBleed,
      scenes: List<ui.Scene?>.filled(columns * bands, null),
      frames: List<Future<ui.Image>?>.filled(columns * bands, null),
    );
    for (var band = 0; band < bands; band++) {
      for (var column = 0; column < columns; column++) {
        final g = _tileGeometry(plan, band, column);
        final scene = boundary.buildRegionScene(
          Rect.fromLTWH(
            (g.x0 - g.leftBleed) / pixelRatio,
            (g.y0 - g.topBleed) / pixelRatio,
            g.rasterWidth / pixelRatio,
            g.rasterHeight / pixelRatio,
          ),
          pixelRatio: pixelRatio,
        );
        final index = band * columns + column;
        if (eagerTileRasterization) {
          // The web engine samples the scene inside this call and a
          // later buildScene would hollow it out — rasterization must
          // begin here, inside the frozen snapshot loop.
          plan._frames[index] = scene.toImage(g.rasterWidth, g.rasterHeight);
          scene.dispose();
        } else {
          plan._scenes[index] = scene;
        }
      }
    }
    return plan;
  }

  /// One tile's full geometry: its output placement plus the bleed
  /// applied on each side. Bleed extends only into the image's interior
  /// — image borders coincide with the single-shot render's own surface
  /// edges, so they need (and get) none.
  _TileGeometry _tileGeometry(_TilePlan plan, int band, int column) {
    final y0 = band * plan.bandRows;
    final rows = (y0 + plan.bandRows <= _height) ? plan.bandRows : _height - y0;
    final x0 = column * plan.tileWidth;
    final cols = (x0 + plan.tileWidth <= _width) ? plan.tileWidth : _width - x0;
    final topBleed = y0 < plan.vBleed ? y0 : plan.vBleed;
    final below = _height - y0 - rows;
    final bottomBleed = below < plan.vBleed ? below : plan.vBleed;
    final leftBleed = x0 < plan.hBleed ? x0 : plan.hBleed;
    final right = _width - x0 - cols;
    final rightBleed = right < plan.hBleed ? right : plan.hBleed;
    return _TileGeometry(
      x0: x0,
      y0: y0,
      cols: cols,
      rows: rows,
      leftBleed: leftBleed,
      topBleed: topBleed,
      rasterWidth: cols + leftBleed + rightBleed,
      rasterHeight: rows + topBleed + bottomBleed,
    );
  }

  /// Rasterizes the frozen scenes, delivering raw RGBA bands to [onBand]
  /// in order. [onBand] receives a buffer it owns and the row count.
  ///
  /// Throws [MuralCancelled] between tiles if the task was cancelled,
  /// and [MuralRasterError] when the engine cannot rasterize even at the
  /// spec-floor tile size.
  Future<void> run(
    Future<void> Function(Uint8List band, int rows) onBand,
  ) async {
    assert(_plan != null, 'snapshot() must run before run()');
    var restarts = 0;

    try {
      while (true) {
        try {
          await _runPlanned(onBand);
          return;
        } on _ReplanSignal {
          // The first tile taught us a smaller ceiling; replan from
          // scratch. Nothing has been emitted (discovery is
          // first-tile-only). Clamping engines reveal the exact ceiling
          // in one signal; failing engines back off geometrically, so a
          // few retries reach a workable plan or prove the device can't
          // rasterize at all.
          restarts++;
          if (restarts > GpuLimits.maxRetries) {
            throw const MuralRasterError(
              'The GPU kept rejecting tiles down to the spec-floor size; '
              'the device cannot rasterize this capture.',
            );
          }
          _plan!.dispose();
          _plan = _buildPlan();
        }
      }
    } finally {
      _plan?.dispose();
      _plan = null;
    }
  }

  Future<void> _runPlanned(
    Future<void> Function(Uint8List band, int rows) onBand,
  ) async {
    final plan = _plan!;
    final rowBytes = _width * 4;
    final totalTiles = plan.columns * plan.bands;
    var tilesDone = 0;
    var rowsDelivered = 0;
    // Verify the first tile whenever its size is not yet proven: nothing
    // learned and the plan exceeds the spec floor, or a failure-driven
    // back-off picked a ceiling no successful capture has confirmed.
    final mustLearn =
        _ceilingUnproven &&
        (plan.tileWidth + 2 * plan.hBleed > GpuLimits.specFloor ||
            plan.bandRows + 2 * plan.vBleed > GpuLimits.specFloor);
    if (!mustLearn) {
      _ceilingUnproven = false;
    }

    for (var band = 0; band < plan.bands; band++) {
      final rows = _tileGeometry(plan, band, 0).rows;
      final bandBuffer = Uint8List(rows * rowBytes);

      for (var column = 0; column < plan.columns; column++) {
        if (isCancelled()) {
          throw const MuralCancelled();
        }
        final g = _tileGeometry(plan, band, column);

        final index = band * plan.columns + column;
        final tile = eagerTileRasterization
            ? await _awaitFrame(
                plan.takeFrame(index),
                widthPx: g.rasterWidth,
                heightPx: g.rasterHeight,
                verifyCeiling: mustLearn && tilesDone == 0,
              )
            : await _rasterize(
                plan.takeScene(index),
                widthPx: g.rasterWidth,
                heightPx: g.rasterHeight,
                verifyCeiling: mustLearn && tilesDone == 0,
              );
        try {
          await _blit(tile, bandBuffer, rowBytes, g);
        } finally {
          tile.dispose();
        }

        tilesDone++;
        onTile(tilesDone, totalTiles, rowsDelivered);
        // Keep the event loop breathing between GPU readbacks. The
        // frozen scenes make this safe on a live boundary.
        await Future<void>.delayed(Duration.zero);
      }

      await onBand(bandBuffer, rows);
      rowsDelivered += rows;
    }
  }

  Future<ui.Image> _rasterize(
    ui.Scene scene, {
    required int widthPx,
    required int heightPx,
    required bool verifyCeiling,
  }) {
    final Future<ui.Image> frame;
    try {
      frame = scene.toImage(widthPx, heightPx);
    } finally {
      scene.dispose();
    }
    return _awaitFrame(
      frame,
      widthPx: widthPx,
      heightPx: heightPx,
      verifyCeiling: verifyCeiling,
    );
  }

  Future<ui.Image> _awaitFrame(
    Future<ui.Image> frame, {
    required int widthPx,
    required int heightPx,
    required bool verifyCeiling,
  }) async {
    final ui.Image image;
    try {
      image = await frame;
    } catch (error, stackTrace) {
      if (verifyCeiling) {
        // Engines that throw on oversize (Impeller's documented
        // PictureRasterizationException path) reveal no size; back the
        // ceiling off and replan.
        limits.recordFailure(widthPx > heightPx ? widthPx : heightPx);
        throw const _ReplanSignal();
      }
      throw MuralRasterError(
        'The engine failed to rasterize a ${widthPx}x$heightPx tile.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (verifyCeiling) {
      _ceilingUnproven = false;
    }
    if (verifyCeiling &&
        !limits.interpret(
          width: image.width,
          height: image.height,
          requestedWidth: widthPx,
          requestedHeight: heightPx,
        )) {
      image.dispose();
      throw const _ReplanSignal();
    }
    return image;
  }

  /// Copies a tile's output region into the band buffer, cropping the
  /// bleed margins away.
  Future<void> _blit(
    ui.Image tile,
    Uint8List band,
    int bandRowBytes,
    _TileGeometry g,
  ) async {
    final ByteData? data = await tile.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) {
      throw const MuralRasterError(
        'The engine returned no pixel data for a tile.',
      );
    }
    final src = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (unpremultiplyReadback) {
      straightenAlpha(src);
    }
    final srcRowBytes = tile.width * 4;
    final copyBytes = g.cols * 4;
    final available = tile.height - g.topBleed;
    final copyRows = available < g.rows ? available : g.rows;
    for (var row = 0; row < copyRows; row++) {
      final dst = row * bandRowBytes + g.x0 * 4;
      final from = (row + g.topBleed) * srcRowBytes + g.leftBleed * 4;
      band.setRange(dst, dst + copyBytes, src, from);
    }
  }
}

/// The placement and bleed of one tile: `x0/y0/cols/rows` locate its
/// output region; the bleeds say how much extra was rasterized on each
/// interior side and must be cropped by the blit.
final class _TileGeometry {
  const _TileGeometry({
    required this.x0,
    required this.y0,
    required this.cols,
    required this.rows,
    required this.leftBleed,
    required this.topBleed,
    required this.rasterWidth,
    required this.rasterHeight,
  });

  final int x0;
  final int y0;
  final int cols;
  final int rows;
  final int leftBleed;
  final int topBleed;
  final int rasterWidth;
  final int rasterHeight;
}

/// A frozen capture plan: the tile grid plus one pre-built scene per
/// tile, consumed left-to-right, top-to-bottom.
final class _TilePlan {
  _TilePlan({
    required this.tileWidth,
    required this.bandRows,
    required this.columns,
    required this.bands,
    required this.hBleed,
    required this.vBleed,
    required List<ui.Scene?> scenes,
    required List<Future<ui.Image>?> frames,
  }) : _scenes = scenes,
       _frames = frames;

  final int tileWidth;
  final int bandRows;
  final int columns;
  final int bands;
  final int hBleed;
  final int vBleed;
  final List<ui.Scene?> _scenes;
  final List<Future<ui.Image>?> _frames;

  /// Hands ownership of one tile's scene to the caller.
  ui.Scene takeScene(int index) {
    final scene = _scenes[index]!;
    _scenes[index] = null;
    return scene;
  }

  /// Hands ownership of one tile's in-flight rasterization to the caller.
  Future<ui.Image> takeFrame(int index) {
    final frame = _frames[index]!;
    _frames[index] = null;
    return frame;
  }

  /// Disposes every scene and settles every frame not yet taken.
  void dispose() {
    for (var i = 0; i < _scenes.length; i++) {
      _scenes[i]?.dispose();
      _scenes[i] = null;
      final frame = _frames[i];
      _frames[i] = null;
      // A discarded in-flight tile still owns a GPU image on arrival;
      // dispose it whenever it lands, and swallow its failure — the
      // plan it belonged to is already gone.
      if (frame != null) {
        unawaited(
          frame.then((image) => image.dispose(), onError: (Object _) {}),
        );
      }
    }
  }
}

/// Internal control flow: the first tile revealed a smaller ceiling and
/// the plan must be rebuilt. Never escapes [CaptureEngine.run].
final class _ReplanSignal implements Exception {
  const _ReplanSignal();
}
