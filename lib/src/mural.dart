import 'dart:async' show unawaited;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:mural/src/capture/capture_engine.dart';
import 'package:mural/src/capture/gpu_limits.dart';
import 'package:mural/src/capture/raster_policy.dart';
import 'package:mural/src/capture/readback.dart';
import 'package:mural/src/capture/scene_boundary.dart';
import 'package:mural/src/encode/png_worker.dart';
import 'package:mural/src/host/render_host.dart';
import 'package:mural/src/types/errors.dart';
import 'package:mural/src/types/image.dart';
import 'package:mural/src/types/options.dart';
import 'package:mural/src/types/progress.dart';
import 'package:mural/src/types/stage.dart';
import 'package:mural/src/types/task.dart';

/// Captures Flutter widgets as images at any size.
///
/// The GPU limits a single rasterization to its maximum texture size;
/// mural captures in tiles, assembles bands, and streams the encode, so
/// output dimensions are limited by neither the GPU nor memory.
///
/// ```dart
/// final mural = Mural();
///
/// // A widget that isn't on screen:
/// final shot = await mural.capture(
///   ReceiptView(order),
///   context: context,
///   options: const MuralOptions(pixelRatio: 3),
/// );
///
/// // A subtree that is on screen, wrapped in MuralBoundary:
/// final shot = await mural.captureBoundary(boundaryKey);
///
/// // A huge capture streamed to any sink:
/// await mural.captureInto(sink, TranscriptView(chat), context: context);
/// ```
///
/// Instances are cheap and hold one piece of state: the GPU texture
/// ceiling learned from captures on this device. Reusing one instance
/// lets later captures plan correctly without rediscovery.
class Mural {
  /// Creates a capturer with no learned GPU ceiling yet.
  Mural();

  final GpuLimits _limits = GpuLimits();

  // Progress budget per phase: layout finishes at 0.05, tile capture
  // spans to 0.95, the encode tail closes at 1.0.
  static const double _layoutShare = 0.05;
  static const double _captureShare = 0.90;

  /// Captures [widget] offscreen and returns the encoded image.
  ///
  /// [context] supplies the ambient scope the widget renders under —
  /// theme, media query, directionality, localizations. The widget never
  /// enters [context]'s tree; it lays out in an isolated render tree
  /// staged per [stage].
  MuralTask<MuralImage> capture(
    Widget widget, {
    required BuildContext context,
    MuralOptions options = const MuralOptions(),
    MuralStage stage = const MuralStage(),
  }) {
    final task = MuralTask<MuralImage>.internal();
    final collector = _CollectorSink();
    _drive(task, () async {
      final info = await _captureWidget(
        widget,
        context: context,
        options: options,
        stage: stage,
        task: task,
        sink: collector,
      );
      return MuralImage(
        bytes: (collector..close()).builder.takeBytes(),
        width: info.width,
        height: info.height,
        format: info.format,
      );
    });
    return task;
  }

  /// Captures [widget] offscreen, streaming encoded bytes into [sink].
  ///
  /// The image never exists in memory as a whole — bands stream from the
  /// GPU through the encoder into [sink], bounded by
  /// `options.memoryLimitBytes`. The sink is not closed; it belongs to
  /// the caller. Completes with the output's dimensions and byte count;
  /// the bytes themselves went to [sink].
  MuralTask<MuralImageInfo> captureInto(
    Sink<List<int>> sink,
    Widget widget, {
    required BuildContext context,
    MuralOptions options = const MuralOptions(),
    MuralStage stage = const MuralStage(),
  }) {
    final task = MuralTask<MuralImageInfo>.internal();
    _drive(
      task,
      () => _captureWidget(
        widget,
        context: context,
        options: options,
        stage: stage,
        task: task,
        sink: sink,
      ),
    );
    return task;
  }

  /// Captures an on-screen boundary identified by [key].
  ///
  /// The boundary's visual state is frozen synchronously, in this call —
  /// the result shows this exact moment even while the widget keeps
  /// animating, so captures compose with any trigger the app chooses:
  ///
  /// ```dart
  /// // At a gesture, on a timer, or from the widget's own logic:
  /// onPressed: () => saves.add(mural.captureBoundary(boundaryKey));
  /// Timer.periodic(interval, (_) => shoot(mural.captureBoundary(key)));
  /// ```
  ///
  /// Wrap the subtree in [MuralBoundary] for any-size capture. A plain
  /// [RepaintBoundary] also works within the GPU texture limit, but an
  /// oversize one throws [MuralBoundaryError] — the framework offers no
  /// region path into a foreign boundary's layer.
  MuralTask<MuralImage> captureBoundary(
    GlobalKey key, {
    MuralOptions options = const MuralOptions(),
  }) {
    final task = MuralTask<MuralImage>.internal();
    final collector = _CollectorSink();
    // Validation and the snapshot run synchronously so the frozen
    // moment is the call itself, not some later event-loop turn.
    try {
      final target = key.currentContext?.findRenderObject();
      if (target == null) {
        throw const MuralBoundaryError(
          'The key has no mounted render object. Capture after the widget '
          'is built and painted.',
        );
      }
      if (target is! RenderBox || !target.hasSize || target.size.isEmpty) {
        throw const MuralBoundaryError(
          'The boundary has no laid-out size. Capture after layout has '
          'completed (for example after the first frame).',
        );
      }
      if (target is MuralSceneBoundary) {
        if (!target.hasPainted) {
          throw const MuralBoundaryError(
            'The boundary has not painted yet. Capture after the first '
            'frame.',
          );
        }
        final (engine, fractionNow) = _tileEngine(target, options, task);
        engine.snapshot();
        _drive(task, () async {
          task.report(const MuralLayoutProgress(fraction: _layoutShare));
          final (width, height, _) = await _encodeBands(
            engine,
            fractionNow,
            options: options,
            task: task,
            sink: collector,
          );
          return MuralImage(
            bytes: (collector..close()).builder.takeBytes(),
            width: width,
            height: height,
            format: options.format,
          );
        });
      } else if (target is RenderRepaintBoundary) {
        _captureForeignBoundary(target, options, collector, task);
      } else {
        throw const MuralBoundaryError(
          'The key does not identify a repaint boundary. Wrap the '
          'subtree in MuralBoundary (or RepaintBoundary) and key that '
          'widget.',
        );
      }
    } on MuralError catch (error, stackTrace) {
      task.fail(error, stackTrace);
    }
    return task;
  }

  // ── shared drive path ──────────────────────────────────────────────

  void _drive<T>(MuralTask<T> task, Future<T> Function() body) {
    // Deliberately not awaited: the returned task IS the completion
    // surface; this function only launches the work.
    unawaited(
      Future<void>(() async {
        try {
          task.complete(await body());
        } on MuralError catch (error, stackTrace) {
          task.fail(error, stackTrace);
        } catch (error, stackTrace) {
          task.fail(
            MuralEncodeError(
              'Capture failed unexpectedly.',
              cause: error,
              stackTrace: stackTrace,
            ),
            stackTrace,
          );
        }
      }),
    );
  }

  Future<MuralImageInfo> _captureWidget(
    Widget widget, {
    required BuildContext context,
    required MuralOptions options,
    required MuralStage stage,
    required MuralTask<MuralImageInfo> task,
    required Sink<List<int>> sink,
  }) async {
    task.report(const MuralLayoutProgress(fraction: 0));
    final host = await RenderHost.mount(
      widget,
      context: context,
      pixelRatio: options.pixelRatio,
      stage: stage,
    );
    try {
      task.report(const MuralLayoutProgress(fraction: _layoutShare));
      final (engine, fractionNow) = _tileEngine(host.boundary, options, task);
      engine.snapshot();
      final (width, height, byteCount) = await _encodeBands(
        engine,
        fractionNow,
        options: options,
        task: task,
        sink: sink,
      );
      return MuralImageInfo(
        width: width,
        height: height,
        format: options.format,
        byteCount: byteCount,
      );
    } finally {
      host.dispose();
    }
  }

  /// Builds a tiling engine wired to [task]'s progress stream. The
  /// returned closure reports the latest capture fraction so encode
  /// reports ride at it, keeping the interleaved stream monotonic.
  (CaptureEngine, double Function()) _tileEngine(
    MuralSceneBoundary boundary,
    MuralOptions options,
    MuralTask<Object?> task,
  ) {
    var fraction = _layoutShare;
    late final CaptureEngine engine;
    engine = CaptureEngine(
      boundary: boundary,
      pixelRatio: options.pixelRatio,
      memoryLimitBytes: options.memoryLimitBytes,
      bleed: options.bleed,
      limits: _limits,
      isCancelled: () => task.isCancelled,
      onTile: (tilesDone, tileCount, rowsDelivered) {
        fraction = _layoutShare + tilesDone / tileCount * _captureShare;
        task.report(
          MuralCaptureProgress(
            fraction: fraction,
            width: engine.outputWidth,
            height: engine.outputHeight,
            tilesDone: tilesDone,
            tileCount: tileCount,
            rowsDelivered: rowsDelivered,
          ),
        );
      },
    );
    return (engine, () => fraction);
  }

  /// Runs a snapshotted [engine], routing bands through the format's
  /// encoder into [sink]. Returns the output dimensions and the total
  /// bytes emitted.
  Future<(int, int, int)> _encodeBands(
    CaptureEngine engine,
    double Function() fractionNow, {
    required MuralOptions options,
    required MuralTask<Object?> task,
    required Sink<List<int>> sink,
  }) async {
    var bytesEmitted = 0;
    void emit(List<int> chunk) {
      // A streaming compressor may buffer a band and emit nothing yet.
      if (chunk.isEmpty) {
        return;
      }
      sink.add(chunk);
      bytesEmitted += chunk.length;
      task.report(
        MuralEncodeProgress(
          fraction: fractionNow(),
          bytesEmitted: bytesEmitted,
        ),
      );
    }

    switch (options.format) {
      case MuralFormat.rawRgba:
        await engine.run((band, rows) async => emit(band));
      case MuralFormat.png:
        final worker = PngWorker();
        try {
          emit(
            await worker.start(
              width: engine.outputWidth,
              height: engine.outputHeight,
            ),
          );
          await engine.run(
            (band, rows) async => emit(await worker.addBand(band, rows)),
          );
          emit(await worker.finish());
        } catch (error, stackTrace) {
          if (error is MuralError) {
            rethrow;
          }
          throw MuralEncodeError(
            'PNG encoding failed.',
            cause: error,
            stackTrace: stackTrace,
          );
        } finally {
          worker.dispose();
        }
    }
    task.report(MuralEncodeProgress(fraction: 1, bytesEmitted: bytesEmitted));
    return (engine.outputWidth, engine.outputHeight, bytesEmitted);
  }

  /// Full-bounds capture of a boundary mural does not own. Limited by
  /// the GPU ceiling and the memory budget; beyond either, the answer is
  /// [MuralBoundary].
  void _captureForeignBoundary(
    RenderRepaintBoundary boundary,
    MuralOptions options,
    _CollectorSink collector,
    MuralTask<MuralImage> task,
  ) {
    final size = boundary.size;
    final width = (size.width * options.pixelRatio).ceil();
    final height = (size.height * options.pixelRatio).ceil();
    if (width * height * 4 > options.memoryLimitBytes) {
      throw const MuralBoundaryError(
        'This capture exceeds the memory budget, and a plain '
        'RepaintBoundary only supports full-bounds capture. Wrap the '
        'subtree in MuralBoundary for banded any-size capture.',
      );
    }

    // toImage builds its scene synchronously — the frozen moment is
    // this call; only the rasterization is awaited later.
    final Future<ui.Image> frame;
    try {
      frame = boundary.toImage(pixelRatio: options.pixelRatio);
    } catch (error, stackTrace) {
      throw MuralRasterError(
        'The engine failed to rasterize the boundary.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    _drive(task, () async {
      task.report(const MuralLayoutProgress(fraction: _layoutShare));
      final ui.Image image;
      try {
        image = await frame;
      } catch (error, stackTrace) {
        throw MuralRasterError(
          'The engine failed to rasterize the boundary.',
          cause: error,
          stackTrace: stackTrace,
        );
      }
      try {
        if (image.width < width || image.height < height) {
          throw const MuralBoundaryError(
            'The engine clamped this capture to the GPU texture limit. '
            'Wrap the subtree in MuralBoundary for any-size capture.',
          );
        }
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        if (data == null) {
          throw const MuralRasterError(
            'The engine returned no pixel data for the boundary.',
          );
        }
        final rgba = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        if (unpremultiplyReadback) {
          straightenAlpha(rgba);
        }
        task.report(
          MuralCaptureProgress(
            fraction: _layoutShare + _captureShare,
            width: image.width,
            height: image.height,
            tilesDone: 1,
            tileCount: 1,
            rowsDelivered: image.height,
          ),
        );

        var bytesEmitted = 0;
        void emit(List<int> chunk) {
          // A streaming compressor may buffer and emit nothing yet.
          if (chunk.isEmpty) {
            return;
          }
          collector.add(chunk);
          bytesEmitted += chunk.length;
          task.report(
            MuralEncodeProgress(
              fraction: _layoutShare + _captureShare,
              bytesEmitted: bytesEmitted,
            ),
          );
        }

        switch (options.format) {
          case MuralFormat.rawRgba:
            emit(rgba);
          case MuralFormat.png:
            final worker = PngWorker();
            try {
              emit(
                await worker.start(width: image.width, height: image.height),
              );
              emit(await worker.addBand(rgba, image.height));
              emit(await worker.finish());
            } finally {
              worker.dispose();
            }
        }
        task.report(
          MuralEncodeProgress(fraction: 1, bytesEmitted: bytesEmitted),
        );
        return MuralImage(
          bytes: (collector..close()).builder.takeBytes(),
          width: image.width,
          height: image.height,
          format: options.format,
        );
      } finally {
        image.dispose();
      }
    });
  }
}

/// Adapts an in-memory byte collector to the band-sink shape the encode
/// path streams into.
final class _CollectorSink implements Sink<List<int>> {
  final BytesBuilder builder = BytesBuilder(copy: false);

  @override
  void add(List<int> data) => builder.add(data);

  @override
  void close() {}
}
