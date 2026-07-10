/// Pins the VM-only mechanics of the isolate PNG worker that the
/// platform-blind worker battery cannot express: how band buffers cross
/// the isolate boundary. The web worker runs inline and never hands a
/// buffer to anyone.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mural/src/encode/png_worker.dart';

void main() {
  test('the caller keeps a usable buffer after the isolate hand-off', () async {
    final worker = PngWorker();
    try {
      await worker.start(width: 2, height: 2);
      final band = Uint8List.fromList([
        1, 2, 3, 4, 5, 6, 7, 8, //
      ]);
      await worker.addBand(band, 1);
      // TransferableTypedData.fromList copies into the transferable
      // buffer; the caller's own buffer stays intact. The engine
      // allocates a fresh band per hand-off either way — this test
      // exists so a Dart SDK behavior change is a red build, not a
      // silent data corruption.
      expect(band.length, 8);
      expect(band.first, 1);
    } finally {
      worker.dispose();
    }
  });

  test('two workers encode concurrently without interference', () async {
    final a = PngWorker();
    final b = PngWorker();
    try {
      final headers = await Future.wait([
        a.start(width: 4, height: 1),
        b.start(width: 9, height: 1),
      ]);
      final chunks = await Future.wait([
        a.addBand(Uint8List(4 * 4), 1),
        b.addBand(Uint8List(9 * 4), 1),
      ]);
      final tails = await Future.wait([a.finish(), b.finish()]);
      expect(headers[0], isNot(equals(headers[1])));
      expect(chunks[0], isNotEmpty);
      expect(chunks[1], isNotEmpty);
      expect(tails[0], isNotEmpty);
    } finally {
      a.dispose();
      b.dispose();
    }
  });
}
