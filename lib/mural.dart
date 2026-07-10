/// Capture any Flutter widget as an image at any size.
///
/// The GPU caps a single rasterization at its maximum texture size —
/// the cause of blurry or truncated `RepaintBoundary.toImage` captures
/// of large widgets. Mural rasterizes in tiles, assembles bands, and
/// streams the encode, so output size is bounded by neither the GPU nor
/// memory.
library;

export 'src/capture/scene_boundary.dart' show MuralBoundary;
export 'src/mural.dart';
export 'src/types/errors.dart';
export 'src/types/image.dart';
export 'src/types/options.dart';
export 'src/types/progress.dart';
export 'src/types/stage.dart';
export 'src/types/task.dart';
