import 'dart:async';
import 'dart:typed_data';

import 'package:mural/src/encode/png_encoder.dart';

/// Runs the PNG encoder on the calling isolate, yielding to the event
/// loop after each band so the UI stays responsive.
///
/// This is the web implementation — web Flutter has no worker isolates —
/// and the fallback wherever `dart:isolate` is unavailable.
final class PngWorker {
  StreamingPngEncoder? _encoder;

  /// Starts an encode for a `width` × `height` image and returns the PNG
  /// signature + IHDR bytes.
  Future<Uint8List> start({required int width, required int height}) async {
    assert(_encoder == null, 'start() called twice');
    _encoder = StreamingPngEncoder(width: width, height: height);
    return _encoder!.start();
  }

  /// Filters + compresses one band and returns its IDAT chunk.
  ///
  /// Takes ownership of [rgba]; callers must not reuse the buffer.
  Future<Uint8List> addBand(Uint8List rgba, int rowCount) async {
    final chunk = _encoder!.addBand(rgba, rowCount);
    // Yield so a long encode cannot starve the event loop between bands.
    await Future<void>.delayed(Duration.zero);
    return chunk;
  }

  /// Finishes the stream and returns the final IDAT + IEND bytes.
  Future<Uint8List> finish() async => _encoder!.finish();

  /// Releases resources. Safe to call at any point, including after a
  /// failed capture.
  void dispose() {
    _encoder = null;
  }
}
