import 'dart:math';

/// Generates a UUID v4 string (RFC 4122).
///
/// Uses `dart:math` [Random.secure] so no external package is required.
String generateId() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));

  // Version 4: bits 12-15 of byte 6 are 0100
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  // Variant: bits 6-7 of byte 8 are 10
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  String hex(int b) => b.toRadixString(16).padLeft(2, '0');
  return '${hex(bytes[0])}${hex(bytes[1])}${hex(bytes[2])}${hex(bytes[3])}'
      '-${hex(bytes[4])}${hex(bytes[5])}'
      '-${hex(bytes[6])}${hex(bytes[7])}'
      '-${hex(bytes[8])}${hex(bytes[9])}'
      '-${hex(bytes[10])}${hex(bytes[11])}${hex(bytes[12])}${hex(bytes[13])}${hex(bytes[14])}${hex(bytes[15])}';
}
