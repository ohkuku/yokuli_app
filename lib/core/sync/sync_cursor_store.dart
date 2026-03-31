import 'package:shared_preferences/shared_preferences.dart';

/// Well-known collection names for all synced data.
class SyncCollections {
  static const logs          = 'logs';
  static const alarms        = 'alarms';
  static const tasks         = 'tasks';
  static const issues        = 'issues';
  static const voyages       = 'voyages';
  static const kanbanColumns = 'kanban_columns';
  static const kanbanCards   = 'kanban_cards';
  static const alarmRules    = 'alarm_rules';
  static const alarmInstances = 'alarm_instances';
  static const alarmActions  = 'alarm_actions';

  static const all = <String>[
    logs,
    alarms,
    tasks,
    issues,
    voyages,
    kanbanColumns,
    kanbanCards,
    alarmRules,
    alarmInstances,
    alarmActions,
  ];
}

/// Persists per-collection sync cursors using [SharedPreferences].
///
/// A cursor is the high-watermark 'updatedAt' ISO-8601 string — the newest
/// record this device has confirmed seeing for a given collection.
/// A missing cursor means the collection has never been synced (→ send all).
class SyncCursorStore {
  static const _prefix = 'sync_cursor_';

  /// Returns the stored cursor for [collection], or null if never synced.
  static Future<DateTime?> getCursor(String collection) async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString('$_prefix$collection');
    if (iso == null || iso.isEmpty) return null;
    try {
      return DateTime.parse(iso);
    } catch (_) {
      return null;
    }
  }

  /// Persists [cursor] for [collection].
  static Future<void> setCursor(String collection, DateTime cursor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$collection', cursor.toIso8601String());
  }

  /// Returns all stored cursors as a map of collection → ISO-8601 string.
  /// Collections that have never been synced are omitted.
  static Future<Map<String, String>> getAllCursors([
    List<String> collections = SyncCollections.all,
  ]) async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, String>{};
    for (final col in collections) {
      final iso = prefs.getString('$_prefix$col');
      if (iso != null && iso.isNotEmpty) result[col] = iso;
    }
    return result;
  }

  /// Advance cursor only if [newCursor] is strictly newer than stored.
  static Future<void> advance(String collection, DateTime newCursor) async {
    final existing = await getCursor(collection);
    if (existing == null || newCursor.isAfter(existing)) {
      await setCursor(collection, newCursor);
    }
  }

  /// Reset the cursor for [collection] (forces full resync on next connect).
  static Future<void> reset(String collection) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$collection');
  }

  /// Reset ALL collection cursors (forces full resync on next connect).
  static Future<void> resetAll([
    List<String> collections = SyncCollections.all,
  ]) async {
    for (final col in collections) {
      await reset(col);
    }
  }
}
