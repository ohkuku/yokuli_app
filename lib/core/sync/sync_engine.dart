/// Unified LWW (Last-Write-Wins) merge engine for all synced collections.
///
/// All synced records are plain [Map<String, dynamic>] with these required keys:
///   - 'id'  : String  — unique identifier
///   - 'ua'  : String  — ISO-8601 updatedAt timestamp
///   - 'del' : bool?   — soft-delete flag (absent means false)
///   - 'src' : String? — sourceDeviceId for tie-breaking (absent means '')
///
/// Note: models that already use 'src' for another purpose (voyage, issue)
/// store sourceDeviceId under 'sdid'. The engine is field-agnostic; callers
/// normalise to 'src' before calling merge if needed, or use the raw key form.
///
/// Conflict resolution (LWW):
///   1. Newer 'ua' wins.
///   2. Equal 'ua': tombstone (del=true) wins.
///   3. Equal 'ua' + equal tombstone flag: larger 'src'/'sdid' (lexicographic) wins.
class SyncEngine {
  SyncEngine._();

  // ---- Merge -----------------------------------------------------------------

  /// Merge [incoming] into [existing].
  ///
  /// Returns whichever record should be kept, or [incoming] if [existing] is null.
  /// The [srcKey] param lets callers specify which key holds sourceDeviceId
  /// (default 'src'; voyages/issues use 'sdid').
  static Map<String, dynamic> merge(
    Map<String, dynamic>? existing,
    Map<String, dynamic> incoming, {
    String srcKey = 'src',
  }) {
    if (existing == null) return incoming;

    final existingUa = _parseUa(existing['ua']);
    final incomingUa = _parseUa(incoming['ua']);

    if (incomingUa.isAfter(existingUa)) return incoming;
    if (existingUa.isAfter(incomingUa)) return existing;

    // Tie: tombstone wins
    final existingDel = existing['del'] as bool? ?? false;
    final incomingDel = incoming['del'] as bool? ?? false;
    if (incomingDel && !existingDel) return incoming;
    if (existingDel && !incomingDel) return existing;

    // Tie: larger sourceDeviceId wins (lexicographic)
    final existingSrc = existing[srcKey] as String? ?? '';
    final incomingSrc = incoming[srcKey] as String? ?? '';
    return incomingSrc.compareTo(existingSrc) > 0 ? incoming : existing;
  }

  /// Apply a batch of [incomingRecords] into [existing] map (keyed by 'id').
  static Map<String, Map<String, dynamic>> applyBatch(
    Map<String, Map<String, dynamic>> existing,
    List<Map<String, dynamic>> incomingRecords, {
    String srcKey = 'src',
  }) {
    final result = Map<String, Map<String, dynamic>>.from(existing);
    for (final record in incomingRecords) {
      final id = record['id'] as String?;
      if (id == null) continue;
      result[id] = merge(result[id], record, srcKey: srcKey);
    }
    return result;
  }

  // ---- Cursor helpers --------------------------------------------------------

  /// Compute the high-watermark cursor from a list of records.
  ///
  /// Returns the maximum 'ua' found across all [records], or [current] if all
  /// records are older.
  static DateTime computeCursor(
    List<Map<String, dynamic>> records,
    DateTime current,
  ) {
    var cursor = current;
    for (final r in records) {
      final ua = _parseUa(r['ua']);
      if (ua.isAfter(cursor)) cursor = ua;
    }
    return cursor;
  }

  /// Filter [records] to only those with 'ua' strictly after [cursor].
  ///
  /// Pass null [cursor] to return ALL records (first-ever sync).
  static List<Map<String, dynamic>> missingFor(
    List<Map<String, dynamic>> records,
    DateTime? cursor,
  ) {
    if (cursor == null) return List.from(records);
    return records.where((r) => _parseUa(r['ua']).isAfter(cursor)).toList();
  }

  // ---- Internal helpers ------------------------------------------------------

  static DateTime _parseUa(dynamic value) {
    if (value is String && value.isNotEmpty) {
      try {
        return DateTime.parse(value);
      } catch (_) {}
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
