import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Runs once at startup to backfill legacy records that are missing the
/// `sourceDeviceId` field required for LWW sync tie-breaking.
///
/// This is safe to call multiple times: only writes if a record actually
/// needs updating (missing or empty sourceDeviceId key).
class SyncMigration {
  SyncMigration._();

  // collection store name → sourceDeviceId key used in that collection's JSON
  static const _listCollections = <String, String>{
    'log'            : 'src',  // LogEntry
    'alarms'         : 'src',  // Alarm
    'issues'         : 'sdid', // IssueTicket (src is taken by IssueSource)
    'voyages'        : 'sdid', // VoyageSession (src is taken by VoyageSource)
    'task_instances' : 'src',  // TaskInstance (migrated from 'sd')
  };

  static const _kanbanStoreName = 'kanban';

  /// Backfill [deviceId] as sourceDeviceId into any stored record missing it.
  static Future<void> run(String deviceId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      for (final entry in _listCollections.entries) {
        await _migrateList(dir, entry.key, entry.value, deviceId);
      }
      await _migrateKanban(dir, deviceId);
    } catch (_) {
      // Migration is best-effort; never crash the app
    }
  }

  static Future<void> _migrateList(
    Directory dir,
    String storeName,
    String sdKey,
    String deviceId,
  ) async {
    final f = File('${dir.path}/yokuli_$storeName.json');
    if (!await f.exists()) return;
    try {
      final List<dynamic> rows = jsonDecode(await f.readAsString()) as List;
      var changed = false;
      final updated = rows.map((row) {
        final m = Map<String, dynamic>.from(row as Map);
        final existing = m[sdKey];
        if (existing == null || (existing as String?)?.isEmpty == true) {
          m[sdKey] = deviceId;
          changed = true;
        }
        return m;
      }).toList();
      if (changed) {
        await f.writeAsString(jsonEncode(updated));
      }
    } catch (_) {}
  }

  static Future<void> _migrateKanban(Directory dir, String deviceId) async {
    final f = File('${dir.path}/yokuli_$_kanbanStoreName.json');
    if (!await f.exists()) return;
    try {
      final Map<String, dynamic> data =
          jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      var changed = false;

      List<Map<String, dynamic>> migrateItems(List<dynamic> items) {
        return items.map((item) {
          final m = Map<String, dynamic>.from(item as Map);
          final existing = m['src'];
          if (existing == null || (existing as String?)?.isEmpty == true) {
            m['src'] = deviceId;
            changed = true;
          }
          return m;
        }).toList();
      }

      final columns = migrateItems(data['columns'] as List? ?? []);
      final cards   = migrateItems(data['cards']   as List? ?? []);

      if (changed) {
        await f.writeAsString(jsonEncode({'columns': columns, 'cards': cards}));
      }
    } catch (_) {}
  }
}
