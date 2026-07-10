import 'dart:typed_data';

import 'package:mural/src/types/options.dart';

/// What a capture produced: dimensions, format, and encoded size.
///
/// Streaming captures (`Mural.captureInto`) complete with this — the
/// bytes went to the caller's sink, so there are none to return.
/// Buffered captures complete with [MuralImage], which adds the bytes.
class MuralImageInfo {
  /// Creates a capture description.
  const MuralImageInfo({
    required this.width,
    required this.height,
    required this.format,
    required this.byteCount,
  });

  /// Output width in pixels.
  final int width;

  /// Output height in pixels.
  final int height;

  /// The format the output is encoded in.
  final MuralFormat format;

  /// Total encoded output size in bytes.
  final int byteCount;

  @override
  String toString() =>
      '$runtimeType(${width}x$height ${format.name}, $byteCount bytes)';
}

/// The result of a buffered capture: the encoded bytes plus the
/// dimensions callers almost always need next.
final class MuralImage extends MuralImageInfo {
  /// Creates a capture result.
  MuralImage({
    required this.bytes,
    required super.width,
    required super.height,
    required super.format,
  }) : super(byteCount: bytes.length);

  /// The encoded image bytes ([MuralFormat.png]) or raw straight-alpha
  /// RGBA bytes ([MuralFormat.rawRgba]).
  final Uint8List bytes;
}
