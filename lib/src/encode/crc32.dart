import 'dart:typed_data';

/// Incremental CRC-32 (reflected, polynomial 0xEDB88320) as PNG chunks use.
final class Crc32 {
  static final Uint32List _table = _buildTable();

  static Uint32List _buildTable() {
    final table = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      table[n] = c;
    }
    return table;
  }

  int _crc = 0xFFFFFFFF;

  /// Folds [data] into the running checksum.
  void add(Uint8List data, [int start = 0, int? end]) {
    var c = _crc;
    final table = _table;
    final stop = end ?? data.length;
    for (var i = start; i < stop; i++) {
      c = table[(c ^ data[i]) & 0xFF] ^ (c >> 8);
    }
    _crc = c;
  }

  /// The finalized checksum of everything added so far.
  int get value => _crc ^ 0xFFFFFFFF;
}
