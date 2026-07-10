import 'dart:typed_data';

/// Converts premultiplied RGBA bytes to straight alpha in place:
/// `c = round(c * 255 / a)`, skipping fully-transparent and fully-opaque
/// pixels. Used on engines whose readback ignores the straight-alpha
/// byte format (see `raster_policy.dart`).
void straightenAlpha(Uint8List rgba) {
  for (var i = 0; i < rgba.length; i += 4) {
    final a = rgba[i + 3];
    if (a == 0 || a == 255) {
      continue;
    }
    final half = a >> 1;
    for (var c = 0; c < 3; c++) {
      final v = (rgba[i + c] * 255 + half) ~/ a;
      rgba[i + c] = v > 255 ? 255 : v;
    }
  }
}
