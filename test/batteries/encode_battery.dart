/// Round-trips the streaming PNG encoder through package:image — an
/// independent decoder — over gradients, flats, noise, alpha, and every
/// band split. Platform-blind: both runners execute it.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mural/src/encode/png_encoder.dart';

/// Encodes [rgba] in bands of [bandRows] and decodes the result with
/// package:image — an independent PNG implementation — returning the
/// round-tripped pixels.
Uint8List _roundTrip(Uint8List rgba, int width, int height, int bandRows) {
  final encoder = StreamingPngEncoder(width: width, height: height);
  final out = BytesBuilder()..add(encoder.start());
  var row = 0;
  while (row < height) {
    final rows = min(bandRows, height - row);
    final band = Uint8List.sublistView(
      rgba,
      row * width * 4,
      (row + rows) * width * 4,
    );
    out.add(encoder.addBand(band, rows));
    row += rows;
  }
  out.add(encoder.finish());

  final decoded = img.decodePng(out.takeBytes());
  expect(decoded, isNotNull, reason: 'independent decoder rejected the PNG');
  expect(decoded!.width, width);
  expect(decoded.height, height);
  final result = Uint8List(width * height * 4);
  var i = 0;
  for (final pixel in decoded) {
    result[i++] = pixel.r.toInt();
    result[i++] = pixel.g.toInt();
    result[i++] = pixel.b.toInt();
    result[i++] = pixel.a.toInt();
  }
  return result;
}

Uint8List _gradient(int width, int height) {
  final rgba = Uint8List(width * height * 4);
  var i = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      rgba[i++] = (x * 255) ~/ max(1, width - 1);
      rgba[i++] = (y * 255) ~/ max(1, height - 1);
      rgba[i++] = (x ^ y) & 0xFF;
      rgba[i++] = 255;
    }
  }
  return rgba;
}

void runEncodeBattery() {
  group('streaming png encoder', () {
    test('gradient round-trips pixel-exact through an independent decoder', () {
      final rgba = _gradient(97, 61);
      expect(_roundTrip(rgba, 97, 61, 61), rgba);
    });

    test('band boundaries are seamless (Up filter carries across bands)', () {
      final rgba = _gradient(64, 100);
      for (final bandRows in [1, 3, 7, 33, 100]) {
        expect(
          _roundTrip(rgba, 64, 100, bandRows),
          rgba,
          reason: 'bandRows=$bandRows must not change output pixels',
        );
      }
    });

    test('flat color exercises the distance-1 run path', () {
      final rgba = Uint8List(80 * 80 * 4);
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = 30;
        rgba[i + 1] = 144;
        rgba[i + 2] = 255;
        rgba[i + 3] = 255;
      }
      expect(_roundTrip(rgba, 80, 80, 16), rgba);
    });

    test(
      'transparent and semi-transparent alpha survives (straight alpha)',
      () {
        final rgba = Uint8List(16 * 16 * 4);
        var i = 0;
        for (var y = 0; y < 16; y++) {
          for (var x = 0; x < 16; x++) {
            rgba[i++] = 200;
            rgba[i++] = 10;
            rgba[i++] = 10;
            rgba[i++] = (x * 17) & 0xFF; // includes 0 and 255
          }
        }
        expect(_roundTrip(rgba, 16, 16, 5), rgba);
      },
    );

    test('random noise round-trips (worst case for the run matcher)', () {
      final random = Random(42);
      final rgba = Uint8List(51 * 37 * 4);
      for (var i = 0; i < rgba.length; i++) {
        rgba[i] = random.nextInt(256);
      }
      expect(_roundTrip(rgba, 51, 37, 8), rgba);
    });

    test('single pixel image', () {
      final rgba = Uint8List.fromList([1, 2, 3, 4]);
      expect(_roundTrip(rgba, 1, 1, 1), rgba);
    });

    test('long runs beyond one match length (>259 identical bytes)', () {
      // 200 pixels per row -> 800 identical bytes per run region.
      final rgba = Uint8List(200 * 10 * 4);
      expect(_roundTrip(rgba, 200, 10, 10), rgba);
    });

    test('flat color compresses far below raw size', () {
      const width = 256;
      const height = 256;
      final rgba = Uint8List(width * height * 4);
      final encoder = StreamingPngEncoder(width: width, height: height);
      final out = BytesBuilder()
        ..add(encoder.start())
        ..add(encoder.addBand(rgba, height))
        ..add(encoder.finish());
      final png = out.takeBytes();
      expect(
        png.length,
        lessThan(width * height * 4 ~/ 50),
        reason: 'run-length coding should crush a flat image',
      );
    });
  });
}
