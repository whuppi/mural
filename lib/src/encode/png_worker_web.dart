import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:mural/src/encode/png_chunks.dart';
import 'package:mural/src/encode/png_encoder.dart';
import 'package:mural/src/encode/png_filter.dart';

/// Runs the PNG encode through the browser's built-in `CompressionStream`
/// — native-code deflate, streaming, without shipping a worker script.
/// Filtering stays in Dart (a cheap byte pass); compression, the heavy
/// stage, is the engine's own zlib.
///
/// `CompressionStream('deflate')` produces an RFC 1950 zlib stream —
/// exactly what PNG's IDAT carries — so compressed bytes are framed into
/// IDAT chunks as the browser emits them. On a browser without
/// CompressionStream, the pure-Dart encoder runs inline instead; the
/// output contract is identical either way.
final class PngWorker {
  PngFilter? _filter;
  _Writer? _writer;
  _Reader? _reader;
  final List<Uint8List> _drained = [];
  Future<void>? _pump;
  StreamingPngEncoder? _inline;

  static bool get _hasCompressionStream =>
      globalContext.has('CompressionStream');

  /// Starts an encode for a `width` × `height` image and returns the PNG
  /// signature + IHDR bytes.
  Future<Uint8List> start({required int width, required int height}) async {
    assert(_filter == null && _inline == null, 'start() called twice');
    if (!_hasCompressionStream) {
      _inline = StreamingPngEncoder(width: width, height: height);
      return _inline!.start();
    }
    _filter = PngFilter(width: width, height: height);
    final stream = _CompressionStream('deflate');
    _writer = stream.writable.getWriter();
    _reader = stream.readable.getReader();
    _pump = _drain();
    return pngHeader(width: width, height: height);
  }

  /// Moves compressed bytes out of the browser stream as they emerge,
  /// so the compressor never has to buffer the whole image.
  Future<void> _drain() async {
    while (true) {
      final result = await _reader!.read().toDart;
      if (result.done) {
        return;
      }
      _drained.add(result.value!.toDart);
    }
  }

  /// Filters + compresses one band, returning whatever compressed bytes
  /// the browser has emitted so far as one IDAT chunk — possibly empty
  /// while the compressor buffers.
  Future<Uint8List> addBand(Uint8List rgba, int rowCount) async {
    if (_inline != null) {
      final chunk = _inline!.addBand(rgba, rowCount);
      // Yield so a long inline encode cannot starve the event loop.
      await Future<void>.delayed(Duration.zero);
      return chunk;
    }
    final filtered = _filter!.filterBand(rgba, rowCount);
    await _writer!.write(filtered.toJS).toDart;
    return _takeDrained();
  }

  /// Finishes the stream and returns the final IDAT + IEND bytes.
  Future<Uint8List> finish() async {
    if (_inline != null) {
      return _inline!.finish();
    }
    await _writer!.close().toDart;
    await _pump;
    final out = BytesBuilder(copy: false);
    final tail = _takeDrained();
    if (tail.isNotEmpty) {
      out.add(tail);
    }
    out.add(pngTrailer());
    // The stream is fully consumed; make a later dispose() a no-op so
    // it can't abort an already-closed writer.
    _writer = null;
    _reader = null;
    _pump = null;
    _filter = null;
    return out.takeBytes();
  }

  Uint8List _takeDrained() {
    if (_drained.isEmpty) {
      return Uint8List(0);
    }
    final data = BytesBuilder(copy: false);
    for (final piece in _drained) {
      data.add(piece);
    }
    _drained.clear();
    return pngChunk('IDAT', data.takeBytes());
  }

  /// Releases the browser stream. Safe to call at any point, including
  /// after a failed capture.
  void dispose() {
    _inline = null;
    _filter = null;
    // Aborting resolves the drain loop's pending read; ignore() keeps a
    // rejection from an already-errored stream out of the uncaught zone.
    _writer?.abort();
    _reader?.cancel();
    _pump?.ignore();
    _writer = null;
    _reader = null;
    _drained.clear();
  }
}

@JS('CompressionStream')
extension type _CompressionStream._(JSObject _) implements JSObject {
  external _CompressionStream(String format);
  external _ReadableStream get readable;
  external _WritableStream get writable;
}

extension type _ReadableStream._(JSObject _) implements JSObject {
  external _Reader getReader();
}

extension type _Reader._(JSObject _) implements JSObject {
  external JSPromise<_ReadResult> read();
  external JSPromise<JSAny?> cancel();
}

extension type _ReadResult._(JSObject _) implements JSObject {
  external bool get done;
  external JSUint8Array? get value;
}

extension type _WritableStream._(JSObject _) implements JSObject {
  external _Writer getWriter();
}

extension type _Writer._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> write(JSUint8Array chunk);
  external JSPromise<JSAny?> close();
  external JSPromise<JSAny?> abort();
}
