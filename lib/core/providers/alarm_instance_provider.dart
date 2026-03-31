import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/alarm_action.dart';
import '../models/alarm_instance.dart';
import '../models/alarm_rule.dart';
import '../sync/sync_engine.dart';
import '../utils/id_gen.dart';
import 'alarm_action_provider.dart';
import 'device_provider.dart';
import 'lan_broadcast.dart';
import 'settings_provider.dart';

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
// AlarmInstanceNotifier
// ---------------------------------------------------------------------------

class AlarmInstanceNotifier extends Notifier<List<AlarmInstance>> {
  static const _storeName = 'yokuli_alarm_instances';

  @override
  List<AlarmInstance> build() => const [];

  // ---- Persistence ----------------------------------------------------------

  Future<void> load() async {
    final rows = await _JsonStore.load(_storeName);
    state = rows.map(AlarmInstance.fromJson).toList()
      ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
  }

  Future<void> _save() async {
    await _JsonStore.save(
        _storeName, state.map((i) => i.toJson()).toList());
  }

  // ---- Mutations ------------------------------------------------------------

  /// Trigger a new alarm instance for [ruleId].
  ///
  /// No-ops if there is already an active or snoozed instance for the same
  /// [ruleId] and the existing instance's [AlarmRule.condition.cooldownMs] has
  /// not elapsed since it was last updated.
  ///
  /// [cooldownMs] should be passed from the triggering rule so the check is
  /// accurate without needing to read the rule provider here.
  Future<AlarmInstance?> trigger({
    required String ruleId,
    required String ruleName,
    required AlarmLevel level,
    required String message,
    double? triggeredValue,
    required String deviceId,
    int cooldownMs = 300000,
  }) async {
    final now = DateTime.now();

    // Check for an existing active or snoozed instance for this rule.
    final existing = state.where((i) =>
        i.ruleId == ruleId &&
        !i.deleted &&
        (i.status == AlarmInstanceStatus.active ||
            i.status == AlarmInstanceStatus.snoozed));

    if (existing.isNotEmpty) {
      // There is already an unresolved instance. Check cooldown against the
      // most recently updated of those instances.
      final latest = existing.reduce((a, b) =>
          a.updatedAt.isAfter(b.updatedAt) ? a : b);
      final elapsed = now.difference(latest.updatedAt).inMilliseconds;
      if (elapsed < cooldownMs) {
        return null; // within cooldown — do not create a duplicate
      }
    }

    final instance = AlarmInstance(
      id: generateId(),
      ruleId: ruleId,
      ruleName: ruleName,
      level: level,
      status: AlarmInstanceStatus.active,
      triggeredAt: now,
      triggeredValue: triggeredValue,
      message: message,
      updatedAt: now,
      deleted: false,
      scope: 'global',
      sourceDeviceId: deviceId,
      schemaVersion: 1,
    );

    state = [instance, ...state];
    await _save();
    ref.read(lanBroadcastProvider)?.call({
      'type': 'alarm_instance_sync',
      'data': instance.toJson(),
    });
    return instance;
  }

  /// Acknowledge an active alarm instance.
  Future<void> acknowledge(
    String instanceId, {
    required String deviceId,
    required String deviceName,
  }) async {
    final idx = state.indexWhere((i) => i.id == instanceId);
    if (idx < 0) return;
    final now = DateTime.now();
    final updated = state[idx].copyWith(
      status: AlarmInstanceStatus.acknowledged,
      updatedAt: now,
      sourceDeviceId: deviceId,
    );
    final list = List<AlarmInstance>.from(state);
    list[idx] = updated;
    state = list;
    await _save();
    ref.read(lanBroadcastProvider)?.call({
      'type': 'alarm_instance_sync',
      'data': updated.toJson(),
    });

    // Record the action
    final action = AlarmAction(
      id: generateId(),
      instanceId: instanceId,
      action: AlarmActionType.acknowledged,
      deviceId: deviceId,
      deviceName: deviceName,
      at: now,
      updatedAt: now,
      deleted: false,
      scope: 'global',
      sourceDeviceId: deviceId,
      schemaVersion: 1,
    );
    await ref.read(alarmActionProvider.notifier).append(action);
  }

  /// Snooze an alarm instance for [minutes] minutes.
  Future<void> snooze(
    String instanceId,
    int minutes, {
    required String deviceId,
    required String deviceName,
  }) async {
    final idx = state.indexWhere((i) => i.id == instanceId);
    if (idx < 0) return;
    final now = DateTime.now();
    final snoozedUntil = now.add(Duration(minutes: minutes));
    final updated = state[idx].copyWith(
      status: AlarmInstanceStatus.snoozed,
      snoozedUntil: snoozedUntil,
      updatedAt: now,
      sourceDeviceId: deviceId,
    );
    final list = List<AlarmInstance>.from(state);
    list[idx] = updated;
    state = list;
    await _save();
    ref.read(lanBroadcastProvider)?.call({
      'type': 'alarm_instance_sync',
      'data': updated.toJson(),
    });

    // Record the action
    final action = AlarmAction(
      id: generateId(),
      instanceId: instanceId,
      action: AlarmActionType.snoozed,
      deviceId: deviceId,
      deviceName: deviceName,
      at: now,
      snoozeMinutes: minutes,
      updatedAt: now,
      deleted: false,
      scope: 'global',
      sourceDeviceId: deviceId,
      schemaVersion: 1,
    );
    await ref.read(alarmActionProvider.notifier).append(action);
  }

  /// Clear (resolve) an alarm instance.
  Future<void> clear(
    String instanceId, {
    required String deviceId,
    required String deviceName,
    String? note,
  }) async {
    final idx = state.indexWhere((i) => i.id == instanceId);
    if (idx < 0) return;
    final now = DateTime.now();
    final updated = state[idx].copyWith(
      status: AlarmInstanceStatus.cleared,
      clearedAt: now,
      updatedAt: now,
      sourceDeviceId: deviceId,
    );
    final list = List<AlarmInstance>.from(state);
    list[idx] = updated;
    state = list;
    await _save();
    ref.read(lanBroadcastProvider)?.call({
      'type': 'alarm_instance_sync',
      'data': updated.toJson(),
    });

    // Record the action
    final action = AlarmAction(
      id: generateId(),
      instanceId: instanceId,
      action: AlarmActionType.cleared,
      deviceId: deviceId,
      deviceName: deviceName,
      at: now,
      note: note,
      updatedAt: now,
      deleted: false,
      scope: 'global',
      sourceDeviceId: deviceId,
      schemaVersion: 1,
    );
    await ref.read(alarmActionProvider.notifier).append(action);
  }

  /// System-triggered clear when a rule's condition recovers automatically.
  ///
  /// Transitions the instance to [AlarmInstanceStatus.cleared] and sets
  /// [clearedAt] without creating an [AlarmAction] — the evaluator appends
  /// the `autoClear` action separately so it can supply the device name.
  Future<void> autoClear(
    String instanceId, {
    required String deviceId,
  }) async {
    final idx = state.indexWhere((i) => i.id == instanceId);
    if (idx < 0) return;
    final now = DateTime.now();
    final updated = state[idx].copyWith(
      status: AlarmInstanceStatus.cleared,
      clearedAt: now,
      updatedAt: now,
      sourceDeviceId: deviceId,
    );
    final list = List<AlarmInstance>.from(state);
    list[idx] = updated;
    state = list;
    await _save();
    ref.read(lanBroadcastProvider)?.call({
      'type': 'alarm_instance_sync',
      'data': updated.toJson(),
    });
  }

  /// Apply an instance record received from a remote peer (LWW merge, no rebroadcast).
  Future<void> upsertRemote(Map<String, dynamic> json) async {
    try {
      final incoming = AlarmInstance.fromJson(json);
      final idx = state.indexWhere((i) => i.id == incoming.id);
      if (idx >= 0) {
        final existingJson = state[idx].toJson();
        final merged = SyncEngine.merge(existingJson, json);
        final mergedInstance = AlarmInstance.fromJson(merged);
        final list = List<AlarmInstance>.from(state);
        list[idx] = mergedInstance;
        state = list;
      } else {
        state = [incoming, ...state];
      }
      await _save();
    } catch (_) {}
  }

  /// Check for snoozed instances whose snooze period has expired and
  /// transition them back to active. Writes a [AlarmActionType.reactivate]
  /// action for each reactivated instance.
  Future<void> checkSnoozedExpired() async {
    final now = DateTime.now();
    final deviceId = ref.read(deviceProvider).deviceId;
    final deviceName = ref.read(settingsProvider).deviceName;
    final reactivatedIds = <String>[];

    final list = state.map((instance) {
      if (instance.status != AlarmInstanceStatus.snoozed) return instance;
      final until = instance.snoozedUntil;
      if (until == null || now.isBefore(until)) return instance;
      reactivatedIds.add(instance.id);
      return instance.copyWith(
        status: AlarmInstanceStatus.active,
        snoozedUntil: null,
        updatedAt: now,
        sourceDeviceId: deviceId,
      );
    }).toList();

    if (reactivatedIds.isEmpty) return;
    state = list;
    await _save();

    // Broadcast each reactivated instance and append a reactivate action.
    for (final id in reactivatedIds) {
      final inst = state.firstWhere((i) => i.id == id);
      ref.read(lanBroadcastProvider)?.call({
        'type': 'alarm_instance_sync',
        'data': inst.toJson(),
      });
      final action = AlarmAction(
        id: generateId(),
        instanceId: id,
        action: AlarmActionType.reactivate,
        deviceId: deviceId,
        deviceName: deviceName,
        at: now,
        note: '静音时间已到期',
        updatedAt: now,
        deleted: false,
        scope: 'global',
        sourceDeviceId: deviceId,
        schemaVersion: 1,
      );
      await ref.read(alarmActionProvider.notifier).append(action);
    }
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final alarmInstanceProvider =
    NotifierProvider<AlarmInstanceNotifier, List<AlarmInstance>>(
        AlarmInstanceNotifier.new);

/// Instances that are currently active or snoozed (not cleared/acknowledged).
final activeAlarmInstancesProvider = Provider<List<AlarmInstance>>((ref) {
  return ref
      .watch(alarmInstanceProvider)
      .where((i) =>
          !i.deleted &&
          (i.status == AlarmInstanceStatus.active ||
              i.status == AlarmInstanceStatus.snoozed))
      .toList()
    ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
});

/// Count of instances that are strictly active (not snoozed, not resolved).
final alarmInstanceCountProvider = Provider<int>((ref) {
  return ref
      .watch(alarmInstanceProvider)
      .where((i) =>
          !i.deleted && i.status == AlarmInstanceStatus.active)
      .length;
});
