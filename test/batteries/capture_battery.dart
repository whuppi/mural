/// The full facade spec: offscreen capture, boundary capture, banding
/// invisibility, streaming, progress, cancellation, and every typed
/// error. Platform-blind by design — both runners execute it.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mural/mural.dart';

import '../harness/quadrants.dart';

void runCaptureBattery() {
  group('capture', () {
    testWidgets('captureBoundary rasterizes an on-screen MuralBoundary', (
      tester,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: MuralBoundary(
              key: key,
              child: SizedBox(width: 200, height: 100, child: quadrants()),
            ),
          ),
        ),
      );

      final shot = await tester.runAsync(
        () => Mural().captureBoundary(
          key,
          options: const MuralOptions(pixelRatio: 2),
        ),
      );

      expect(shot!.width, 400);
      expect(shot.height, 200);
      expect(shot.byteCount, shot.bytes.length);
      expectQuadrants(decodeShot(shot), 400, 200);
    });

    testWidgets('offscreen capture renders a widget never put on screen', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));

      final shot = await tester.runAsync(
        () => Mural().capture(
          quadrants(),
          context: context,
          options: const MuralOptions(pixelRatio: 3),
        ),
      );

      expect(shot!.width, 600);
      expect(shot.height, 300);
      expectQuadrants(decodeShot(shot), 600, 300);
    });

    testWidgets(
      'a tiny memory budget produces identical pixels (banding is invisible)',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        final context = tester.element(find.byType(SizedBox));

        final (roomy, tight) = (await tester.runAsync(() async {
          final roomy = await Mural().capture(
            quadrants(),
            context: context,
            options: const MuralOptions(pixelRatio: 4),
          );
          // 1 MB budget forces many bands at 800px width.
          final tight = await Mural().capture(
            quadrants(),
            context: context,
            options: const MuralOptions(
              pixelRatio: 4,
              memoryLimitBytes: 1 << 20,
            ),
          );
          return (roomy, tight);
        }))!;

        final roomyPixels = decodeShot(roomy);
        final tightPixels = decodeShot(tight);
        expect(tight.width, roomy.width);
        expect(tight.height, roomy.height);
        for (var y = 0; y < roomy.height; y += 7) {
          for (var x = 0; x < roomy.width; x += 7) {
            expect(
              tightPixels.getPixel(x, y),
              roomyPixels.getPixel(x, y),
              reason: 'pixel ($x,$y) must not depend on band size',
            );
          }
        }
      },
    );

    testWidgets('rawRgba format returns straight-alpha pixels', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));

      final shot = await tester.runAsync(
        () => Mural().capture(
          const SizedBox(
            width: 4,
            height: 2,
            child: ColoredBox(color: Color(0x80FF0000)),
          ),
          context: context,
          options: const MuralOptions(format: MuralFormat.rawRgba),
        ),
      );

      expect(shot!.format, MuralFormat.rawRgba);
      expect(shot.bytes.length, 4 * 2 * 4);
      // Straight alpha: full-value red channel with half alpha — the
      // premultiplied encoding would read ~128 in the red channel.
      expect(
        shot.bytes[0],
        255,
        reason: 'red channel must be straight, not premultiplied',
      );
      expect(shot.bytes[3], 128);
    });

    testWidgets('the stage paints a background behind the widget', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));

      final shot = await tester.runAsync(
        () => Mural().capture(
          const SizedBox(width: 4, height: 2),
          context: context,
          options: const MuralOptions(format: MuralFormat.rawRgba),
          stage: const MuralStage(background: Color(0xFF00FF00)),
        ),
      );

      expect(shot!.bytes[1], 255, reason: 'background green must paint');
      expect(shot.bytes[3], 255, reason: 'background must be opaque');
    });

    testWidgets('capture streams into a caller sink via captureInto', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));

      final chunks = <List<int>>[];
      final sink = _RecordingSink(chunks);
      final info = await tester.runAsync(
        () => Mural().captureInto(
          sink,
          quadrants(),
          context: context,
          options: const MuralOptions(pixelRatio: 4, memoryLimitBytes: 1 << 20),
        ),
      );

      expect(info!.width, 800);
      expect(info.height, 400);
      expect(info.format, MuralFormat.png);
      final streamed = chunks.fold<int>(0, (total, c) => total + c.length);
      expect(info.byteCount, streamed);
      expect(
        chunks.length,
        greaterThan(1),
        reason: 'output must stream as multiple chunks, never one blob',
      );
      final assembled = BytesBuilder();
      for (final chunk in chunks) {
        assembled.add(chunk);
      }
      final decoded = img.decodePng(assembled.takeBytes());
      expect(decoded, isNotNull);
      expectQuadrants(decoded!, 800, 400);
    });

    testWidgets('progress runs layout → capture → encode with live detail', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));

      final reports = <MuralProgress>[];
      await tester.runAsync(() async {
        final task = Mural().capture(quadrants(), context: context);
        task.progress.listen(reports.add);
        await task;
      });

      expect(reports.first, isA<MuralLayoutProgress>());
      expect(reports.last, isA<MuralEncodeProgress>());
      expect(reports.last.fraction, 1.0);
      for (var i = 1; i < reports.length; i++) {
        expect(
          reports[i].fraction,
          greaterThanOrEqualTo(reports[i - 1].fraction),
          reason: 'progress must be monotonic',
        );
      }

      final captures = reports.whereType<MuralCaptureProgress>().toList();
      expect(captures, isNotEmpty);
      expect(
        captures.first.width,
        200,
        reason: 'output dimensions surface with the first capture report',
      );
      expect(captures.first.height, 100);
      expect(captures.last.tilesDone, captures.last.tileCount);
      expect(captures.last.rowsDelivered, lessThanOrEqualTo(100));

      final encodes = reports.whereType<MuralEncodeProgress>().toList();
      expect(encodes.last.bytesEmitted, greaterThan(0));
      for (var i = 1; i < encodes.length; i++) {
        expect(
          encodes[i].bytesEmitted,
          greaterThanOrEqualTo(encodes[i - 1].bytesEmitted),
          reason: 'emitted bytes must be monotonic',
        );
      }
    });

    testWidgets('cancellation completes the task with MuralCancelled', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));

      await tester.runAsync(() async {
        final task = Mural().capture(
          quadrants(),
          context: context,
          options: const MuralOptions(pixelRatio: 4, memoryLimitBytes: 1 << 20),
        )..cancel();
        await expectLater(task, throwsA(isA<MuralCancelled>()));
      });
    });

    testWidgets('an empty widget throws MuralLayoutError', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));

      await tester.runAsync(() async {
        await expectLater(
          Mural().capture(const SizedBox.shrink(), context: context),
          throwsA(isA<MuralLayoutError>()),
        );
      });
    });

    testWidgets(
      'a widget that throws in build surfaces MuralBuildError with the cause',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        final context = tester.element(find.byType(SizedBox));

        await tester.runAsync(() async {
          await expectLater(
            Mural().capture(
              Builder(builder: (_) => throw StateError('boom')),
              context: context,
            ),
            throwsA(
              isA<MuralBuildError>().having(
                (e) => e.cause,
                'cause',
                isA<StateError>(),
              ),
            ),
          );
        });
      },
    );

    testWidgets('an unmounted key throws MuralBoundaryError', (tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await expectLater(
          Mural().captureBoundary(GlobalKey()),
          throwsA(isA<MuralBoundaryError>()),
        );
      });
    });

    testWidgets('a plain RepaintBoundary captures within limits', (
      tester,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(width: 200, height: 100, child: quadrants()),
            ),
          ),
        ),
      );

      final shot = await tester.runAsync(() => Mural().captureBoundary(key));
      expectQuadrants(decodeShot(shot!), 200, 100);
    });

    testWidgets('theme and directionality flow into the offscreen tree', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            textTheme: const TextTheme(
              bodyMedium: TextStyle(color: Color(0xFFFF0000)),
            ),
          ),
          home: const SizedBox(),
        ),
      );
      final context = tester.element(find.byType(SizedBox));

      final shot = await tester.runAsync(
        () => Mural().capture(
          const Material(
            color: Color(0xFFFFFFFF),
            child: Text('X', style: TextStyle(fontSize: 40)),
          ),
          context: context,
        ),
      );

      // The glyph must render (non-white pixels exist) — proving text,
      // theme, and directionality resolved without a real View ancestor.
      final decoded = decodeShot(shot!);
      var inked = 0;
      for (final pixel in decoded) {
        if (pixel.r < 250 || pixel.g < 250 || pixel.b < 250) {
          inked++;
        }
      }
      expect(inked, greaterThan(10), reason: 'text glyph must have painted');
    });

    testWidgets('ready + precacheImage loads images before the shot', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));

      // A red PNG from the independent encoder, loaded through the real
      // async image pipeline.
      final source = img.Image(width: 2, height: 2);
      img.fill(source, color: img.ColorRgba8(255, 0, 0, 255));
      final photo = MemoryImage(Uint8List.fromList(img.encodePng(source)));

      final shot = await tester.runAsync(
        () => Mural().capture(
          Image(
            image: photo,
            width: 4,
            height: 2,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.none,
          ),
          context: context,
          options: const MuralOptions(
            format: MuralFormat.rawRgba,
            pixelRatio: 2,
          ),
          stage: MuralStage(
            // The offscreen context resolves the image at the capture's
            // pixel ratio — the documented image recipe, proven by the
            // exact 8x4 physical output below.
            ready: (context) => precacheImage(photo, context),
          ),
        ),
      );

      // The photo must arrive decoded AND correctly sized: a 4x2 image
      // at pixelRatio 2 is exactly 8x4, every pixel solid red — a blank
      // or shrunken placeholder fails loudly here.
      expect(shot!.width, 8);
      expect(shot.height, 4);
      expect(shot.byteCount, 8 * 4 * 4);
      for (var i = 0; i < shot.bytes.length; i += 4) {
        expect(
          (
            shot.bytes[i],
            shot.bytes[i + 1],
            shot.bytes[i + 2],
            shot.bytes[i + 3],
          ),
          (255, 0, 0, 255),
          reason: 'pixel ${i ~/ 4}: the decoded photo must fill the capture',
        );
      }
    });

    testWidgets('the ready signal gates capture on caller async work', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));

      final shot = await tester.runAsync(() {
        // The completer lives INSIDE runAsync: a future created in the
        // fake-async test zone would schedule its listeners on the
        // frozen fake clock and never deliver.
        final data = Completer<Color>();
        return Mural().capture(
          SizedBox(
            width: 4,
            height: 2,
            child: FutureBuilder<Color>(
              future: data.future,
              builder: (_, snap) =>
                  ColoredBox(color: snap.data ?? const Color(0xFF000000)),
            ),
          ),
          context: context,
          options: const MuralOptions(format: MuralFormat.rawRgba),
          stage: MuralStage(
            ready: (_) async {
              data.complete(const Color(0xFF00FF00));
              await data.future;
            },
          ),
        );
      });

      expect(
        shot!.bytes[1],
        255,
        reason: 'capture must wait for the ready signal, not the first frame',
      );
    });

    testWidgets('captureBoundary freezes the moment it is called', (
      tester,
    ) async {
      final key = GlobalKey();
      final color = ValueNotifier(const Color(0xFFFF0000));
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: MuralBoundary(
              key: key,
              child: SizedBox(
                width: 200,
                height: 100,
                child: ValueListenableBuilder<Color>(
                  valueListenable: color,
                  builder: (_, value, _) => ColoredBox(color: value),
                ),
              ),
            ),
          ),
        ),
      );

      final shot = await tester.runAsync(() async {
        // The tight budget forces many bands, so rasterization spans
        // many event-loop turns — all of which happen AFTER the repaint
        // below.
        final task = Mural().captureBoundary(
          key,
          options: const MuralOptions(
            pixelRatio: 4,
            memoryLimitBytes: 1 << 20,
            format: MuralFormat.rawRgba,
          ),
        );
        // Repaint the live tree green before a single tile rasterizes.
        // Driven manually — pump() cannot run inside runAsync.
        color.value = const Color(0xFF00FF00);
        final binding = tester.binding;
        binding.buildOwner!.buildScope(binding.rootElement!);
        binding.rootPipelineOwner
          ..flushLayout()
          ..flushCompositingBits()
          ..flushPaint();
        return task;
      });

      expect(
        shot!.bytes[0],
        255,
        reason: 'the capture must show the state at the call, not the repaint',
      );
      expect(
        shot.bytes[1],
        0,
        reason: 'the later green frame must not tear in',
      );
      // The LAST band is the most exposed to mid-capture repaints.
      expect(shot.bytes[shot.bytes.length - 4], 255);
      expect(shot.bytes[shot.bytes.length - 3], 0);
    });

    testWidgets('material widgets with internal GlobalKeys capture offscreen', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));

      // ListTile builds an Ink with an internal GlobalKey, and GlobalKeys
      // resolve against the BINDING's BuildOwner registry — this pins the
      // host to that owner. A private BuildOwner breaks exactly here.
      final shot = await tester.runAsync(
        () => Mural().capture(
          const Material(
            child: SizedBox(
              width: 240,
              child: Card(child: ListTile(title: Text('offscreen tile'))),
            ),
          ),
          context: context,
        ),
      );

      // Real outcome, not liveness: the exact bounded width, a
      // plausible tile height, and actual glyphs painted inside.
      expect(shot!.width, 240);
      expect(shot.height, inExclusiveRange(40, 120));
      final decoded = decodeShot(shot);
      var inked = 0;
      for (final pixel in decoded) {
        if (pixel.a.toInt() > 0 &&
            (pixel.r.toInt() < 250 ||
                pixel.g.toInt() < 250 ||
                pixel.b.toInt() < 250)) {
          inked++;
        }
      }
      expect(
        inked,
        greaterThan(100),
        reason: 'the tile text must have painted',
      );
    });

    testWidgets('directionality flows into the offscreen tree', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));

      // Two colored cells in a Row: RTL must mirror their order.
      const cells = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 4,
            height: 4,
            child: ColoredBox(color: Color(0xFFFF0000)),
          ),
          SizedBox(
            width: 4,
            height: 4,
            child: ColoredBox(color: Color(0xFF00FF00)),
          ),
        ],
      );

      final shot = await tester.runAsync(
        () => Mural().capture(
          const Directionality(textDirection: TextDirection.rtl, child: cells),
          context: context,
          options: const MuralOptions(format: MuralFormat.rawRgba),
        ),
      );

      // The FULL mirror: under RTL the green cell fills pixels 0-3 and
      // the red cell fills 4-7 on every row — not just the first pixel.
      expect(shot!.width, 8);
      expect(shot.height, 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 8; x++) {
          final i = (y * 8 + x) * 4;
          final expected = x < 4 ? (0, 255, 0) : (255, 0, 0);
          expect(
            (shot.bytes[i], shot.bytes[i + 1], shot.bytes[i + 2]),
            expected,
            reason: 'pixel ($x,$y) must be mirrored under RTL',
          );
        }
      }
    });

    testWidgets('band seams reassemble rows exactly', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));

      // 256x2400 px at pixelRatio 1: rowBytes is 1 KB, so a 1 MB budget
      // forces ~5 capture bands. Every row paints its own index into its
      // color (red = y & 255, green = y >> 8), so the assertion is
      // byte-exact per row: a band planned at the wrong offset, a
      // duplicated seam row, or a skipped row — even by ONE pixel —
      // breaks the encoding at that exact row.
      final shot = await tester.runAsync(
        () => Mural().capture(
          const SizedBox(
            width: 256,
            height: 2400,
            child: CustomPaint(painter: _RowIndexPainter()),
          ),
          context: context,
          options: const MuralOptions(
            format: MuralFormat.rawRgba,
            memoryLimitBytes: 1 << 20,
          ),
        ),
      );

      expect(shot!.width, 256);
      expect(shot.height, 2400);
      const rowBytes = 256 * 4;
      for (var y = 0; y < 2400; y++) {
        final i = y * rowBytes + 128 * 4;
        expect(
          (shot.bytes[i], shot.bytes[i + 1], shot.bytes[i + 2]),
          (y & 255, y >> 8, 0),
          reason:
              'row \$y must hold its own index — a mismatch means a band '
              'captured at the wrong offset or seam rows were '
              'duplicated/skipped',
        );
      }
    });

    testWidgets('tiled capture matches the framework single-shot '
        'ground truth byte for byte', (tester) async {
      // The differential test: the same widget rasterized through the
      // framework's OWN single-shot path (RenderRepaintBoundary.toImage,
      // via captureBoundary on a plain RepaintBoundary) and through
      // mural's offscreen multi-band pipeline must produce identical
      // bytes. Ground truth is live — any content regression the engine
      // introduces hits both sides equally, so only MURAL bugs fail it.
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(key: key, child: _diffContent),
          ),
        ),
      );
      final context = tester.element(find.byType(Center).first);

      // 220x300 logical at pixelRatio 4 = 880x1200 px, rowBytes 3.4 KB:
      // the 1 MB budget splits mural's pass into ~9 bands while the
      // ground truth rasterizes in one shot.
      const options = MuralOptions(format: MuralFormat.rawRgba, pixelRatio: 4);
      final results = await tester.runAsync(() async {
        final truth = await Mural().captureBoundary(key, options: options);
        final tiled = await Mural().capture(
          _diffContent,
          context: context,
          options: const MuralOptions(
            format: MuralFormat.rawRgba,
            pixelRatio: 4,
            memoryLimitBytes: 1 << 20,
          ),
        );
        return (truth, tiled);
      });

      final (truth, tiled) = results!;
      expect(tiled.width, truth.width);
      expect(tiled.height, truth.height);
      expect(truth.width, 880);
      expect(truth.height, 1200);
      final a = truth.bytes;
      final b = tiled.bytes;
      expect(b.length, a.length);
      // The contract: byte-identical, down to the float-rounding floor
      // of tiled rasterization. Tile origins stay dither-aligned and
      // bleed feeds seam-split effects their full neighborhood, so
      // every MECHANISM matches the single-shot render. What remains is
      // arithmetic: each tile evaluates the same geometry under a
      // different translation, so gradient and antialiasing math
      // re-rounds in the last ULP. Measured across these 4.2M pixels:
      // 5 differing bytes on the software rasterizer (two ±1 gradient
      // flips + one rounded-corner AA pixel at Δ8) and 66 on the web
      // GPU (all ±1). True zero needs an engine region-readback API (no
      // translation), which does not exist. Any real defect — a shifted
      // band, a truncated shadow, misaligned dither, lost theme, broken
      // alpha — diverges by whole levels across whole regions (measured
      // 360 to 48,793 bytes) and blows every gate below.
      var differingBytes = 0;
      final roundedPixels = <int>{};
      for (var i = 0; i < a.length; i++) {
        final delta = (a[i] - b[i]).abs();
        if (delta == 0) {
          continue;
        }
        differingBytes++;
        final px = i ~/ 4;
        if (delta > 16) {
          fail(
            'divergence beyond the rounding floor at pixel '
            '(${px % truth.width}, ${px ~/ truth.width}) byte ${i % 4}: '
            'ground truth ${a[i]}, tiled ${b[i]}',
          );
        }
        if (delta > 1) {
          roundedPixels.add(px);
        }
      }
      expect(
        differingBytes,
        lessThan(200),
        reason:
            'the rounding floor is 5 bytes (software) / 66 bytes (web '
            'GPU) in 4.2M pixels — widespread differences mean a real '
            'divergence',
      );
      expect(
        roundedPixels.length,
        lessThanOrEqualTo(4),
        reason:
            'multi-level rounding is confined to isolated '
            'antialiased edge pixels — clusters mean a real divergence',
      );
    });

    testWidgets('an unbounded widget fails typed', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));

      // In debug the framework's own layout assert fires first (surfaced
      // as MuralBuildError); in release the host's non-finite check throws
      // MuralLayoutError. Either way: a typed MuralError, never a redbox
      // image or a hang.
      await tester.runAsync(() async {
        await expectLater(
          Mural().capture(
            const Column(children: [Spacer(), Text('bottom')]),
            context: context,
          ),
          throwsA(isA<MuralError>()),
        );
      });
    });

    testWidgets('stage constraints bound the offscreen layout', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));

      // A row that would be 200 wide unconstrained; the stage caps it at
      // 120 and the output must obey the cap, not the intrinsic width.
      final shot = await tester.runAsync(
        () => Mural().capture(
          const SizedBox(
            width: 200,
            height: 10,
            child: ColoredBox(color: Color(0xFFFF0000)),
          ),
          context: context,
          options: const MuralOptions(format: MuralFormat.rawRgba),
          stage: const MuralStage(constraints: BoxConstraints(maxWidth: 120)),
        ),
      );

      expect(
        shot!.width,
        120,
        reason: 'MuralStage.constraints must bound width',
      );
      expect(shot.height, 10);
    });
  });
}

final class _RecordingSink implements Sink<List<int>> {
  _RecordingSink(this.chunks);
  final List<List<int>> chunks;

  @override
  void add(List<int> data) => chunks.add(data);

  @override
  void close() {}
}

/// Paints every pixel row with its own index encoded in the color
/// (red = y & 255, green = y >> 8) so captures can be verified byte-exact
/// per row.
class _RowIndexPainter extends CustomPainter {
  const _RowIndexPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0; y < size.height; y++) {
      paint.color = Color.fromARGB(255, y & 255, y >> 8, 0);
      canvas.drawRect(Rect.fromLTWH(0, y.toDouble(), size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(_RowIndexPainter oldDelegate) => false;
}

/// Deterministic mixed content for the differential test: an opaque
/// root, a gradient that crosses band boundaries, antialiased text, and
/// an elevation shadow — the content classes a snapshot test would
/// cover, verified here against the framework's own rasterization
/// instead of a checked-in golden.
const _diffContent = SizedBox(
  width: 220,
  height: 300,
  child: ColoredBox(
    color: Color(0xFFFFFFFF),
    child: Column(
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE53935), Color(0xFF1E88E5)],
              ),
            ),
            child: SizedBox.expand(),
          ),
        ),
        Material(
          color: Color(0x00000000),
          child: Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Ground truth',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        Card(
          child: SizedBox(
            width: double.infinity,
            height: 60,
            child: Center(child: Text('mural')),
          ),
        ),
      ],
    ),
  ),
);
