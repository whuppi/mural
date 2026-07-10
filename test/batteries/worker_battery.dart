/// The PngWorker contract — encode off the caller's thread, propagate
/// failures, dispose safely. The conditional export resolves to the
/// isolate worker on the VM and the inline worker in a browser; the
/// SAME battery must pass over both.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mural/src/encode/png_worker.dart';

void runWorkerBattery() {
  group('png worker', () {
    test('encodes bands into a decodable PNG off the main isolate', () async {
      const width = 8;
      const height = 6;
      const bandRows = 3;
      final pixels = Uint8List(width * height * 4);
      for (var i = 0; i < width * height; i++) {
        pixels[i * 4] = (i * 7) & 0xFF;
        pixels[i * 4 + 1] = (i * 13) & 0xFF;
        pixels[i * 4 + 2] = (i * 29) & 0xFF;
        pixels[i * 4 + 3] = 0xFF;
      }

      final worker = PngWorker();
      final out = BytesBuilder();
      try {
        out.add(await worker.start(width: width, height: height));
        const bandBytes = width * bandRows * 4;
        for (var offset = 0; offset < pixels.length; offset += bandBytes) {
          // addBand takes ownership of its buffer, so hand it a copy.
          final band = Uint8List.fromList(
            Uint8List.sublistView(pixels, offset, offset + bandBytes),
          );
          out.add(await worker.addBand(band, bandRows));
        }
        out.add(await worker.finish());
      } finally {
        worker.dispose();
      }

      final decoded = img.decodePng(out.takeBytes());
      expect(decoded, isNotNull);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final p = decoded!.getPixel(x, y);
          final i = (y * width + x) * 4;
          expect(
            (p.r.toInt(), p.g.toInt(), p.b.toInt(), p.a.toInt()),
            (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]),
            reason: 'pixel ($x,$y) must round-trip',
          );
        }
      }
    });

    test('a worker-side failure propagates to the caller', () async {
      final worker = PngWorker();
      try {
        await worker.start(width: 4, height: 4);
        // Three bytes cannot fill a 16-byte row; the encoder's guard
        // must cross back from the worker isolate with its message.
        await expectLater(
          worker.addBand(Uint8List(3), 1),
          throwsA(
            isA<Error>().having(
              (e) => e.toString(),
              'message',
              contains('16 required'),
            ),
          ),
        );
      } finally {
        worker.dispose();
      }
    });

    test('dispose is safe to call twice', () async {
      final worker = PngWorker();
      await worker.start(width: 2, height: 2);
      worker.dispose();
      worker.dispose();
    });
  });
}
