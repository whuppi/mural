import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:mural/src/encode/png_encoder.dart';

/// Runs the PNG encoder on a dedicated worker isolate so filtering and
/// compression never block the UI thread.
///
/// Band buffers move to the worker as [TransferableTypedData] — an
/// ownership transfer, not a copy — and compressed chunks come back the
/// same way. One worker serves one capture; [dispose] kills it.
final class PngWorker {
  Isolate? _isolate;
  SendPort? _commands;
  final ReceivePort _responses = ReceivePort();
  StreamIterator<Object?>? _replies;

  Future<void> _ensureStarted() async {
    if (_isolate != null) {
      return;
    }
    _replies = StreamIterator<Object?>(_responses);
    _isolate = await Isolate.spawn(
      _workerMain,
      _responses.sendPort,
      debugName: 'mural-png-worker',
    );
    await _replies!.moveNext();
    _commands = _replies!.current! as SendPort;
  }

  Future<Uint8List> _request(Object message) async {
    _commands!.send(message);
    await _replies!.moveNext();
    final reply = _replies!.current;
    if (reply is TransferableTypedData) {
      return reply.materialize().asUint8List();
    }
    // The worker sends back (error, stackTraceString) on failure.
    final (Object error, String stack) = reply! as (Object, String);
    Error.throwWithStackTrace(error, StackTrace.fromString(stack));
  }

  /// Starts an encode for a `width` × `height` image and returns the PNG
  /// signature + IHDR bytes.
  Future<Uint8List> start({required int width, required int height}) async {
    await _ensureStarted();
    return _request((width, height));
  }

  /// Filters + compresses one band and returns its IDAT chunk.
  ///
  /// [rgba] is copied once into a transferable buffer at hand-off; the
  /// buffer then moves to the worker and the compressed chunk moves
  /// back, both without further copies.
  Future<Uint8List> addBand(Uint8List rgba, int rowCount) =>
      _request((TransferableTypedData.fromList([rgba]), rowCount));

  /// Finishes the stream and returns the final IDAT + IEND bytes.
  Future<Uint8List> finish() => _request(#finish);

  /// Kills the worker. Safe to call at any point, including after a
  /// failed capture.
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _responses.close();
  }

  static void _workerMain(SendPort responses) {
    final commands = ReceivePort();
    responses.send(commands.sendPort);
    StreamingPngEncoder? encoder;
    commands.listen((Object? message) {
      try {
        final Uint8List reply;
        switch (message) {
          case (final int width, final int height):
            encoder = StreamingPngEncoder(width: width, height: height);
            reply = encoder!.start();
          case (final TransferableTypedData band, final int rowCount):
            reply = encoder!.addBand(
              band.materialize().asUint8List(),
              rowCount,
            );
          case #finish:
            reply = encoder!.finish();
          default:
            throw StateError('unknown worker message: $message');
        }
        responses.send(TransferableTypedData.fromList([reply]));
      } catch (error, stackTrace) {
        final stack = stackTrace.toString();
        try {
          responses.send((error, stack));
        } on Object {
          // The error object can't cross the isolate boundary; a
          // description always can. Never leave the caller hanging.
          responses.send((StateError(error.toString()), stack));
        }
      }
    });
  }
}
