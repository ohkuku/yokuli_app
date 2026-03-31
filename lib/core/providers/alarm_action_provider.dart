import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/alarm_action.dart';
import '../sync/sync_engine.dart';
import 'lan_broadcast.dart';

// ---------------------------------------------------------------------------
// _JsonStore — private file-based JSON persistence helper
// ---------------------------------------------------------------------------

class _JsonStore {
  static Future<File> _file(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name.json');
  }

  static Future<List<Map<String, dynamic>>> load(String name) async {
    try {
      final f = await _file(name);
      if (!await f.exists()) return [];
      final data = jsonDecode(await f.readAsString());
      return List<Map<String, dynamic>>.from(data as List);
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(
      String name, List<Map<String, dynamic>> data) async {
    try {
      (await _file(name)).writeAsString(jsonEncode(data));
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// AlarmActionNotifier
// ---------------------------------------------------------------------------

class AlarmActionNotifier extends Notifier<List<AlarmAction>> {
  static const _storeName = 'yokuli_alarm_actions';

  @override
  List<AlarmAction> build() => const [];

  // ---- Persistence ----------------------------------------------------------

  Future<void> load() async {
    final rows = await _JsonStore.load(_storeName);
    state = rows.map(AlarmAction.fromJson).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
  }

  Future<void> _save() async {
    await _JsonStore.save(
        _storeName, state.map((a) => a.toJson()).toList());
  }

  // ---- Mutations ------------------------------------------------------------

  /// Append a new action to the log. Saves and broadcasts the change.
  Future<void> append(AlarmAction action) async {
    // Deduplicate by id: if an action with the same id already exists, skip.
    if (state.any((a) => a.id == action.id)) return;
    state = [...state, action]..sort((a, b) => a.at.compareTo(b.at));
    await _save();
    ref.read(lanBroadcastProvider)?.call({
      'type': 'alarm_action_sync',
      'data': action.toJson(),
    });
  }

  /// Apply an action record received from a remote peer (LWW merge, no rebroadcast).
  Future<void> applyRemote(Map<String, dynamic> json) async {
    try {
      final incoming = AlarmAction.fromJson(json);
      final existing = <String, Map<String, dynamic>>{
        for (final a in state) a.id: a.toJson(),
      };
      final merged = SyncEngine.merge(existing[incoming.id], json);
      final mergedAction = AlarmAction.fromJson(merged);
      final idx = state.indexWhere((a) => a.id == incoming.id);
      if (idx >= 0) {
        final updated = List<AlarmAction>.from(state);
        updated[idx] = mergedAction;
        state = updated;
      } else {
        state = [...state, mergedAction]..sort((a, b) => a.at.compareTo(b.at));
      }
      await _save();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final alarmActionProvider =
    NotifierProvider<AlarmActionNotifier, List<AlarmAction>>(
        AlarmActionNotifier.new);

/// Derived provider: actions for a specific alarm instance, sorted by time.
final alarmActionsForInstanceProvider =
    Provider.family<List<AlarmAction>, String>((ref, instanceId) {
  return ref
      .watch(alarmActionProvider)
      .where((a) => a.instanceId == instanceId && !a.deleted)
      .toList()
    ..sort((a, b) => a.at.compareTo(b.at));
});
