/// PNG container primitives (RFC 2083): signature, chunk framing, IHDR,
/// IEND. Shared by every encoder backend — the compressed stream inside
/// IDAT chunks is the only part that differs per platform.
library;

import 'dart:typed_data';

import 'package:mural/src/encode/crc32.dart';

const List<int> _signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// The PNG signature plus the IHDR chunk for an 8-bit RGBA image.
Uint8List pngHeader({required int width, required int height}) {
  final ihdr = Uint8List(13);
  final view = ByteData.view(ihdr.buffer);
  view.setUint32(0, width);
  view.setUint32(4, height);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // color type: truecolor with alpha
  ihdr[10] = 0; // compression: deflate
  ihdr[11] = 0; // filter method: adaptive
  ihdr[12] = 0; // interlace: none
  final out = BytesBuilder(copy: false)
    ..add(Uint8List.fromList(_signature))
    ..add(pngChunk('IHDR', ihdr));
  return out.takeBytes();
}

/// Frames [data] as one PNG chunk: length, type, data, CRC-32 over
/// type + data.
Uint8List pngChunk(String type, Uint8List data) {
  final out = Uint8List(12 + data.length);
  final view = ByteData.view(out.buffer);
  view.setUint32(0, data.length);
  for (var i = 0; i < 4; i++) {
    out[4 + i] = type.codeUnitAt(i);
  }
  out.setRange(8, 8 + data.length, data);
  final crc = Crc32()..add(out, 4, 8 + data.length);
  view.setUint32(8 + data.length, crc.value);
  return out;
}

/// The IEND chunk that closes every PNG.
Uint8List pngTrailer() => pngChunk('IEND', Uint8List(0));
