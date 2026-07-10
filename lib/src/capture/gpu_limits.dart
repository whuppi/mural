/// The GPU's usable texture ceiling, learned from real captures.
///
/// No Flutter API reports the raster context's maximum texture size, and
/// querying GL/Metal directly would interrogate a different context than
/// the engine rasterizes with. The engine itself is the only truthful
/// oracle, and it answers an oversize `Scene.toImage` request one of
/// three ways:
///
/// * **exact** — the request fit; nothing to learn;
/// * **clamped** — both engine backends scale the snapshot down
///   proportionally to fit the device maximum (Skia's
///   snapshot_controller_skia.cc and Impeller's
///   snapshot_controller_impeller.cc both compute
///   `min(1, max_size / longest side)` and scale), so the longest
///   returned side IS the maximum;
/// * **failed** — the `toImageSync` path throws
///   `PictureRasterizationException`, and some drivers return a
///   zero-sized image instead of clamping; neither carries a size, so
///   the ceiling backs off geometrically until a request succeeds.
///
/// A capture that fits therefore costs nothing extra; the first oversize
/// capture learns the exact ceiling in one attempt on the clamping paths
/// and converges within [maxRetries] cheap attempts on the failing ones.
class GpuLimits {
  /// Creates a limit tracker with no learned ceiling.
  GpuLimits();

  /// OpenGL ES 3.0 mandates at least 2048; every Flutter-capable GPU
  /// supports it. Back-off never goes below this.
  static const int specFloor = 2048;

  /// Upper bound on replans a single capture may need: enough for the
  /// back-off to walk any realistic ceiling (16384) down to [specFloor].
  static const int maxRetries = 4;

  int? _learnedMax;

  /// The learned ceiling in pixels, or null before the first oversize
  /// encounter.
  int? get learnedMax => _learnedMax;

  /// The tile ceiling to plan with. Before anything is learned, plans
  /// target the full requested size — the engine's response to that
  /// request is what teaches the ceiling.
  int planningCeiling(int requestedMax) => _learnedMax ?? requestedMax;

  /// Interprets a rasterization result against its requested size.
  /// Returns true when the result is usable at face value, false when
  /// the ceiling changed and the caller must replan.
  bool interpret({
    required int width,
    required int height,
    required int requestedWidth,
    required int requestedHeight,
  }) {
    if (width == requestedWidth && height == requestedHeight) {
      return true;
    }
    if (width <= 0 || height <= 0) {
      // A dead image instead of a clamp (seen on some MediaTek chipsets
      // at 16384): no size to read, so back off like a failure.
      _backOff(
        requestedWidth > requestedHeight ? requestedWidth : requestedHeight,
      );
      return false;
    }
    // Clamped. Skia scales the snapshot to fit, so the longest returned
    // side is the ceiling — under per-axis clamping the longest side is
    // the clamped one and reads the same.
    final revealed = width > height ? width : height;
    _learnedMax = revealed < specFloor ? specFloor : revealed;
    return false;
  }

  /// Records an outright rasterization failure of a request whose
  /// longest side was [requestedMax]: the ceiling backs off to half the
  /// request, never below [specFloor].
  void recordFailure(int requestedMax) => _backOff(requestedMax);

  void _backOff(int requestedMax) {
    final current = _learnedMax ?? requestedMax;
    final bounded = current < requestedMax ? current : requestedMax;
    final halved = bounded ~/ 2;
    _learnedMax = halved < specFloor ? specFloor : halved;
  }
}
