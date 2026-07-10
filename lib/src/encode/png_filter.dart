import 'dart:typed_data';

/// Applies PNG scanline filters (RFC 2083 §6.2) to bands of straight
/// RGBA, carrying the previous raw row across bands so where the bands
/// split never affects the output bytes.
///
/// The first image row takes the Sub filter (delta against the pixel to
/// the left); every other row takes Up (delta against the row above) —
/// the pair that turns gradients and flats into long runs for any
/// deflate implementation downstream.
final class PngFilter {
  /// Creates a filter for a `width` × `height` image.
  PngFilter({required this.width, required this.height})
    : assert(width > 0 && height > 0, 'image dimensions must be positive'),
      _rowBytes = width * 4,
      _previousRow = Uint8List(width * 4);

  /// Output width in pixels.
  final int width;

  /// Output height in pixels.
  final int height;

  final int _rowBytes;
  final Uint8List _previousRow;
  int _rowsWritten = 0;

  // PNG filter type bytes.
  static const int _filterSub = 1;
  static const int _filterUp = 2;

  /// Rows filtered so far, across all bands.
  int get rowsWritten => _rowsWritten;

  /// Filters [rowCount] rows of [rgba], returning the scanlines with
  /// their leading filter-type bytes — the exact byte stream PNG
  /// compresses. [rgba] must hold at least `rowCount * width * 4` bytes.
  Uint8List filterBand(Uint8List rgba, int rowCount) {
    assert(rowCount > 0, 'rowCount must be positive');
    assert(
      rgba.length >= rowCount * _rowBytes,
      'band holds ${rgba.length} bytes; ${rowCount * _rowBytes} required',
    );
    assert(
      _rowsWritten + rowCount <= height,
      'band exceeds image height ($_rowsWritten + $rowCount > $height)',
    );

    final filtered = Uint8List(rowCount * (1 + _rowBytes));
    var src = 0;
    var dst = 0;
    for (var row = 0; row < rowCount; row++) {
      final isFirstImageRow = _rowsWritten == 0 && row == 0;
      if (isFirstImageRow) {
        filtered[dst++] = _filterSub;
        for (var i = 0; i < _rowBytes; i++) {
          final left = i >= 4 ? rgba[src + i - 4] : 0;
          filtered[dst++] = (rgba[src + i] - left) & 0xFF;
        }
      } else {
        // For a band's first row the row above is the previous band's
        // last row, carried over.
        filtered[dst++] = _filterUp;
        final prior = row == 0 ? _previousRow : rgba;
        final priorOffset = row == 0 ? 0 : src - _rowBytes;
        for (var i = 0; i < _rowBytes; i++) {
          filtered[dst++] = (rgba[src + i] - prior[priorOffset + i]) & 0xFF;
        }
      }
      src += _rowBytes;
    }
    _previousRow.setRange(0, _rowBytes, rgba, (rowCount - 1) * _rowBytes);
    _rowsWritten += rowCount;
    return filtered;
  }
}
