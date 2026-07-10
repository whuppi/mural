/// Output format of a capture.
enum MuralFormat {
  /// PNG, encoded as a stream — the whole image never sits in memory.
  png,

  /// Raw straight (non-premultiplied) RGBA bytes, 8 bits per channel,
  /// row-major. For piping into your own encoder or video pipeline.
  rawRgba,
}

/// Options every capture accepts: output scale, working-memory budget,
/// and format.
///
/// Offscreen staging (constraints, background, settle time) is a
/// separate concern — see `MuralStage`, accepted only by the methods
/// that stage a widget offscreen.
class MuralOptions {
  /// Creates capture options. The defaults capture at 1:1
  /// logical-to-output pixels as PNG, within a ~64 MB working-memory
  /// budget.
  const MuralOptions({
    this.pixelRatio = 1.0,
    this.memoryLimitBytes = 64 << 20,
    this.format = MuralFormat.png,
    this.bleed = 16.0,
  }) : assert(pixelRatio > 0, 'pixelRatio must be positive'),
       assert(memoryLimitBytes >= 1 << 20, 'memoryLimitBytes must be ≥ 1 MB'),
       assert(bleed >= 0, 'bleed must be ≥ 0');

  /// The scale between logical pixels and output pixels — the same
  /// meaning as `RenderRepaintBoundary.toImage`'s parameter.
  ///
  /// A widget laid out 400 logical pixels wide captured at [pixelRatio]
  /// 3.0 produces a 1200-pixel-wide image. Asset images inside the
  /// widget resolve at this ratio, so a 3.0 capture picks 3x assets.
  final double pixelRatio;

  /// Upper bound on the capture's working memory, in bytes.
  ///
  /// The capture streams the image in horizontal bands sized to fit this
  /// budget, so output dimensions do not affect peak memory. Smaller
  /// budgets trade throughput for footprint.
  final int memoryLimitBytes;

  /// Output format. See [MuralFormat].
  final MuralFormat format;

  /// Extra logical margin rasterized around interior tile seams, in
  /// logical pixels, so raster-space effects see their full
  /// neighborhood.
  ///
  /// Shadows and blurs are computed against the pixels of the surface
  /// being rasterized. A tile edge truncates that source, so an effect
  /// SPLIT by a seam renders differently than it would in one shot.
  /// Bleed rasterizes each tile that much larger and crops the margin
  /// away, giving every seam-adjacent effect the same neighborhood the
  /// single-shot render has — the output is then byte-identical to it.
  ///
  /// The default covers Material shadows up to about elevation 8 and
  /// blurs up to about sigma 5. For stronger effects, set at least the
  /// largest raster reach in the content: ≈3× the largest blur sigma,
  /// or ≈2× the highest Material elevation. `0` disables the margin.
  ///
  /// Bleed costs raster area only near seams; single-tile captures
  /// never pay it. A budget too small to hold even a few rows plus the
  /// bleed fails with a typed `MuralBudgetError` instead of silently
  /// weakening either promise.
  final double bleed;
}
