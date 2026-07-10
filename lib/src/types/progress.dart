/// The phase a capture is currently in.
enum MuralPhase {
  /// Building and laying out the widget tree.
  layout,

  /// Rasterizing tiles and assembling bands.
  capture,

  /// Emitting encoded bytes.
  encode,
}

/// A progress report emitted on `MuralTask.progress`.
///
/// Each phase reports its own data — a layout report has no tile counts,
/// an encode report has no layout data — so switch on the subtype for
/// detail, or read [fraction] for a plain progress bar:
///
/// ```dart
/// task.progress.listen((p) {
///   bar.value = p.fraction;
///   if (p case MuralCaptureProgress(:final width, :final height)) {
///     label.text = '$width x $height';
///   }
/// });
/// ```
sealed class MuralProgress {
  const MuralProgress({required this.fraction})
    : assert(fraction >= 0 && fraction <= 1);

  /// Overall completion, 0.0 → 1.0 across all phases. Monotonic.
  final double fraction;

  /// The phase this report belongs to.
  MuralPhase get phase;

  @override
  String toString() => '$runtimeType(${(fraction * 100).toStringAsFixed(0)}%)';
}

/// The widget tree is building, laying out, and settling.
final class MuralLayoutProgress extends MuralProgress {
  /// Creates a layout-phase report.
  const MuralLayoutProgress({required super.fraction});

  @override
  MuralPhase get phase => MuralPhase.layout;
}

/// Tiles are rasterizing; the first report carries the final output
/// dimensions, available here before the capture completes.
final class MuralCaptureProgress extends MuralProgress {
  /// Creates a capture-phase report.
  const MuralCaptureProgress({
    required super.fraction,
    required this.width,
    required this.height,
    required this.tilesDone,
    required this.tileCount,
    required this.rowsDelivered,
  });

  /// Output width in pixels.
  final int width;

  /// Output height in pixels.
  final int height;

  /// Tiles rasterized so far.
  final int tilesDone;

  /// Total tiles in the capture plan.
  final int tileCount;

  /// Pixel rows already assembled and handed to the encoder.
  final int rowsDelivered;

  @override
  MuralPhase get phase => MuralPhase.capture;
}

/// Encoded bytes are flowing to the output.
final class MuralEncodeProgress extends MuralProgress {
  /// Creates an encode-phase report.
  const MuralEncodeProgress({
    required super.fraction,
    required this.bytesEmitted,
  });

  /// Encoded bytes emitted so far. For streaming captures this is the
  /// live output size.
  final int bytesEmitted;

  @override
  MuralPhase get phase => MuralPhase.encode;
}
