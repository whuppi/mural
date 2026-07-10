/// Typed failures thrown by mural captures.
///
/// Every failure is a subclass of [MuralError], so callers can catch the
/// family or pattern-match a specific case:
///
/// ```dart
/// try {
///   final shot = await mural.capture(widget, context: context);
/// } on MuralCancelled {
///   // user cancelled — not an error state
/// } on MuralError catch (e) {
///   log('capture failed: $e');
/// }
/// ```
library;

/// Base class for every failure mural can throw.
sealed class MuralError implements Exception {
  const MuralError(this.message, {this.cause, this.stackTrace});

  /// Human-readable description of what failed.
  final String message;

  /// The underlying error, when the failure wraps one.
  final Object? cause;

  /// The stack trace of [cause], when available.
  final StackTrace? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer('$runtimeType: $message');
    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }
    return buffer.toString();
  }
}

/// The widget threw while building or laying out inside the capture tree.
///
/// [cause] carries the original exception from the widget's own code.
final class MuralBuildError extends MuralError {
  /// Creates a build failure wrapping the widget's own [cause].
  const MuralBuildError(super.message, {super.cause, super.stackTrace});
}

/// The widget laid out to a size that cannot be captured.
///
/// Thrown when the laid-out size is empty (zero width or height) or
/// non-finite. An unbounded widget (for example a `Column` of unconstrained
/// height inside loose constraints) must be given finite bounds via
/// `MuralOptions.constraints`.
final class MuralLayoutError extends MuralError {
  /// Creates a layout failure.
  const MuralLayoutError(super.message);
}

/// The engine failed to rasterize a capture region.
///
/// This surfaces GPU-side failures: no surface available, a lost context,
/// or a device that rejects even the spec-minimum texture size.
final class MuralRasterError extends MuralError {
  /// Creates a rasterization failure.
  const MuralRasterError(super.message, {super.cause, super.stackTrace});
}

/// Encoding the captured pixels to the output format failed.
final class MuralEncodeError extends MuralError {
  /// Creates an encoding failure.
  const MuralEncodeError(super.message, {super.cause, super.stackTrace});
}

/// The capture was cancelled via `MuralTask.cancel()`.
///
/// Cancellation is cooperative: the task stops at the next band boundary
/// and the awaited future completes with this error.
final class MuralCancelled extends MuralError {
  /// Creates a cancellation marker.
  const MuralCancelled() : super('capture cancelled');
}

/// The memory budget and bleed cannot form a valid tile plan.
///
/// Thrown when `MuralOptions.memoryLimitBytes` is too small to hold even
/// a few pixel rows plus the seam bleed at the capture's width. Raise the
/// budget or lower `MuralOptions.bleed`; the message carries the numbers.
final class MuralBudgetError extends MuralError {
  /// Creates a budget-planning failure.
  const MuralBudgetError(super.message);
}

/// The target of `captureBoundary` is not capturable.
///
/// Thrown when the key has no mounted render object, the render object is
/// not a repaint boundary, or the boundary has not painted yet.
final class MuralBoundaryError extends MuralError {
  /// Creates a boundary-target failure.
  const MuralBoundaryError(super.message);
}
