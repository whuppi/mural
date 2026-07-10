import 'dart:typed_data';

import 'package:mural/src/encode/png_chunks.dart';
import 'package:mural/src/encode/png_filter.dart';
import 'package:mural/src/encode/zlib_encoder.dart';

/// A streaming PNG (RFC 2083) encoder for 8-bit RGBA pixels, compressing
/// with the pure-Dart zlib stream.
///
/// Emits the file in three stages so the full image never has to exist in
/// memory:
///
/// ```dart
/// final encoder = StreamingPngEncoder(width: w, height: h);
/// sink.add(encoder.start());                 // signature + IHDR
/// sink.add(encoder.addBand(rgba, rowCount)); // one IDAT per band
/// sink.add(encoder.finish());                // final IDAT + IEND
/// ```
///
/// Bands must arrive top-to-bottom and total exactly `height` rows.
/// Input is straight (non-premultiplied) RGBA, row-major, 4 bytes per
/// pixel. Instances are single-use and safe to run inside an isolate.
final class StreamingPngEncoder {
  /// Creates an encoder for a `width` × `height` RGBA image.
  StreamingPngEncoder({required this.width, required this.height})
    : _filter = PngFilter(width: width, height: height);

  /// Output width in pixels.
  final int width;

  /// Output height in pixels.
  final int height;

  final PngFilter _filter;
  final StreamingZlib _zlib = StreamingZlib();
  bool _started = false;
  bool _finished = false;

  /// Returns the PNG signature and IHDR chunk. Call exactly once, first.
  Uint8List start() {
    assert(!_started, 'start() called twice');
    _started = true;
    return pngHeader(width: width, height: height);
  }

  /// Filters and compresses [rowCount] rows of [rgba], returning one IDAT
  /// chunk. [rgba] must hold at least `rowCount * width * 4` bytes.
  Uint8List addBand(Uint8List rgba, int rowCount) {
    assert(_started, 'call start() before addBand()');
    assert(!_finished, 'addBand() after finish()');
    return pngChunk('IDAT', _zlib.add(_filter.filterBand(rgba, rowCount)));
  }

  /// Flushes the compressor and returns the final IDAT plus IEND. The
  /// encoder is unusable afterwards.
  Uint8List finish() {
    assert(_started, 'call start() before finish()');
    assert(!_finished, 'finish() called twice');
    assert(
      _filter.rowsWritten == height,
      'finished after ${_filter.rowsWritten} of $height rows',
    );
    _finished = true;
    final out = BytesBuilder(copy: false)
      ..add(pngChunk('IDAT', _zlib.finish()))
      ..add(pngTrailer());
    return out.takeBytes();
  }
}
