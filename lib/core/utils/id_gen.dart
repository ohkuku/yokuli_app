import 'dart:math';

/// Generates a UUID v7 string (draft-ietf-uuidrev-rfc4122bis).
///
/// Structure: 48-bit unix_ts_ms | version 7 | rand_a | variant | rand_b
/// Time-ordered: lexicographic sort ≈ chronological sort.
/// Uses [Random.secure] — no external package required.
String generateId() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));

  // Embed current timestamp in the upper 48 bits
  final ms = DateTime.now().millisecondsSinceEpoch;
  bytes[0] = (ms >> 40) & 0xff;
  bytes[1] = (ms >> 32) & 0xff;
  bytes[2] = (ms >> 24) & 0xff;
  bytes[3] = (ms >> 16) & 0xff;
  bytes[4] = (ms >> 8) & 0xff;
  bytes[5] = ms & 0xff;

  // Version 7: bits 12-15 of byte 6 are 0111
  bytes[6] = (bytes[6] & 0x0f) | 0x70;
  // Variant: bits 6-7 of byte 8 are 10
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  String hex(int b) => b.toRadixString(16).padLeft(2, '0');
  return '${hex(bytes[0])}${hex(bytes[1])}${hex(bytes[2])}${hex(bytes[3])}'
      '-${hex(bytes[4])}${hex(bytes[5])}'
      '-${hex(bytes[6])}${hex(bytes[7])}'
      '-${hex(bytes[8])}${hex(bytes[9])}'
      '-${hex(bytes[10])}${hex(bytes[11])}${hex(bytes[12])}${hex(bytes[13])}${hex(bytes[14])}${hex(bytes[15])}';
}
