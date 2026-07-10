import 'dart:typed_data';

/// A streaming zlib (RFC 1950) encoder over fixed-Huffman deflate
/// (RFC 1951), tuned for PNG scanlines.
///
/// Compression strategy: literals plus distance-1 run matches. After PNG's
/// Up/Sub filtering, UI imagery is dominated by runs of identical bytes
/// (mostly zeros), which distance-1 matches encode at ~13 bits per 258
/// bytes — the bulk of full deflate's win at a fraction of its cost, in
/// pure Dart with no lookback window.
///
/// Feed uncompressed bytes with [add]; each call returns the compressed
/// bytes produced so far as one deflate block. Call [finish] once for the
/// final block and the Adler-32 trailer. Instances are single-use.
final class StreamingZlib {
  /// Creates an encoder. The zlib header is emitted by the first [add].
  StreamingZlib();

  // ── bit writer (LSB-first packing, per RFC 1951) ───────────────────
  final BytesBuilder _out = BytesBuilder(copy: false);
  int _bitBuffer = 0;
  int _bitCount = 0;
  bool _headerWritten = false;
  bool _finished = false;

  // Adler-32 state (RFC 1950 §8.2). Modulo 65521.
  int _adlerA = 1;
  int _adlerB = 0;

  void _writeBits(int value, int count) {
    _bitBuffer |= value << _bitCount;
    _bitCount += count;
    while (_bitCount >= 8) {
      _out.addByte(_bitBuffer & 0xFF);
      _bitBuffer >>= 8;
      _bitCount -= 8;
    }
  }

  /// Huffman codes are transmitted MSB-first; reverse into the LSB-first
  /// bit stream.
  void _writeCode(int code, int length) {
    var reversed = 0;
    for (var i = 0; i < length; i++) {
      reversed = (reversed << 1) | ((code >> i) & 1);
    }
    _writeBits(reversed, length);
  }

  // ── fixed-Huffman alphabets (RFC 1951 §3.2.6) ──────────────────────

  void _writeLiteral(int byte) {
    if (byte < 144) {
      _writeCode(0x30 + byte, 8);
    } else {
      _writeCode(0x190 + (byte - 144), 9);
    }
  }

  /// Length symbol table: (base length, extra bits) per symbol 257..285.
  static const List<int> _lengthBase = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, //
    35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
  ];
  static const List<int> _lengthExtra = [
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, //
    3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
  ];

  void _writeLengthSymbol(int symbol) {
    // Symbols 256..279 are 7-bit codes 0x00..0x17; 280..287 are 8-bit
    // codes 0xC0..0xC7.
    if (symbol < 280) {
      _writeCode(symbol - 256, 7);
    } else {
      _writeCode(0xC0 + (symbol - 280), 8);
    }
  }

  /// Emits a distance-1 match of [length] (3..258): run of the previous
  /// byte.
  void _writeRun(int length) {
    assert(length >= 3 && length <= 258);
    var symbol = _lengthBase.length - 1;
    while (_lengthBase[symbol] > length) {
      symbol--;
    }
    _writeLengthSymbol(257 + symbol);
    final extra = _lengthExtra[symbol];
    if (extra > 0) {
      _writeBits(length - _lengthBase[symbol], extra);
    }
    // Distance symbol 0 (distance 1), 5-bit fixed code, no extra bits.
    _writeCode(0, 5);
  }

  void _updateAdler(Uint8List data) {
    var a = _adlerA;
    var b = _adlerB;
    var i = 0;
    while (i < data.length) {
      // Largest chunk where b cannot overflow 2^53 between reductions.
      var chunkEnd = i + 3800;
      if (chunkEnd > data.length) {
        chunkEnd = data.length;
      }
      for (; i < chunkEnd; i++) {
        a += data[i];
        b += a;
      }
      a %= 65521;
      b %= 65521;
    }
    _adlerA = a;
    _adlerB = b;
  }

  /// Compresses [data] as one non-final deflate block and returns the
  /// bytes produced (may be empty if everything is buffered in bits).
  Uint8List add(Uint8List data) {
    assert(!_finished, 'add() after finish()');
    if (!_headerWritten) {
      // CMF 0x78 (deflate, 32K window), FLG 0x01 → (0x7801 % 31) == 0.
      _out.addByte(0x78);
      _out.addByte(0x01);
      _headerWritten = true;
    }
    if (data.isEmpty) {
      return _out.takeBytes();
    }
    _updateAdler(data);

    // Block header: BFINAL=0, BTYPE=01 (fixed Huffman).
    _writeBits(0, 1);
    _writeBits(1, 2);

    var i = 0;
    final n = data.length;
    while (i < n) {
      final byte = data[i];
      // Measure the run of identical bytes starting here.
      var runEnd = i + 1;
      while (runEnd < n && data[runEnd] == byte && runEnd - i < 259) {
        runEnd++;
      }
      final runLength = runEnd - i;
      if (runLength >= 6) {
        // Literal for the first byte, distance-1 match for the rest.
        _writeLiteral(byte);
        _writeRun(runLength - 1);
        i = runEnd;
      } else {
        _writeLiteral(byte);
        i++;
      }
    }

    // End of block.
    _writeCode(0, 7);
    return _out.takeBytes();
  }

  /// Writes the final (empty) block, flushes bits, appends the Adler-32
  /// trailer, and returns the tail bytes. The encoder is unusable after.
  Uint8List finish() {
    assert(!_finished, 'finish() called twice');
    _finished = true;
    if (!_headerWritten) {
      _out.addByte(0x78);
      _out.addByte(0x01);
      _headerWritten = true;
    }
    // Final empty fixed-Huffman block: BFINAL=1, BTYPE=01, end-of-block.
    _writeBits(1, 1);
    _writeBits(1, 2);
    _writeCode(0, 7);
    // Flush remaining bits, zero-padded.
    if (_bitCount > 0) {
      _out.addByte(_bitBuffer & 0xFF);
      _bitBuffer = 0;
      _bitCount = 0;
    }
    // Adler-32, big-endian.
    final adler = (_adlerB << 16) | _adlerA;
    _out.addByte((adler >> 24) & 0xFF);
    _out.addByte((adler >> 16) & 0xFF);
    _out.addByte((adler >> 8) & 0xFF);
    _out.addByte(adler & 0xFF);
    return _out.takeBytes();
  }
}
