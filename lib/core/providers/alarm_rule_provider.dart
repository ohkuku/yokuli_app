import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alarm_rule.dart';
import '../sync/sync_engine.dart';
import 'lan_broadcast.dart';
import 'device_provider.dart';

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
// Default/built-in rules
// ---------------------------------------------------------------------------

List<AlarmRule> _defaultRules(String deviceId) {
  final now = DateTime.fromMillisecondsSinceEpoch(0); // epoch so any real write wins
  return [
    AlarmRule(
      id: 'builtin_depth',
      name: 'Shallow Water',
      enabled: true,
      level: AlarmLevel.critical,
      condition: const AlarmCondition(
        source: AlarmConditionSource.vesselMetric,
        metric: 'depth_keel',
        operator: AlarmOperator.lessEqual,
        threshold: 3.0,
        sustainMs: 3000,
        cooldownMs: 60000,
      ),
      responsePlan: const AlarmResponsePlan(inApp: true, sound: true),
      snoozeMins: 5,
      isBuiltIn: false,
      updatedAt: now,
      sourceDeviceId: deviceId,
    ),
    AlarmRule(
      id: 'builtin_speed',
      name: 'High Speed',
      enabled: true,
      level: AlarmLevel.warning,
      condition: const AlarmCondition(
        source: AlarmConditionSource.vesselMetric,
        metric: 'sog',
        operator: AlarmOperator.greaterEqual,
        threshold: 20.0,
        cooldownMs: 300000,
      ),
      responsePlan: const AlarmResponsePlan(inApp: true, sound: true),
      snoozeMins: 15,
      isBuiltIn: false,
      updatedAt: now,
      sourceDeviceId: deviceId,
    ),
    AlarmRule(
      id: 'builtin_battery_warn',
      name: 'Battery Low',
      enabled: true,
      level: AlarmLevel.warning,
      condition: const AlarmCondition(
        source: AlarmConditionSource.vesselMetric,
        metric: 'battery_voltage_main',
        operator: AlarmOperator.lessEqual,
        threshold: 11.8,
        cooldownMs: 300000,
      ),
      responsePlan: const AlarmResponsePlan(inApp: true, sound: true),
      snoozeMins: 15,
      isBuiltIn: true,
      updatedAt: now,
      sourceDeviceId: deviceId,
    ),
    AlarmRule(
      id: 'builtin_battery_crit',
      name: 'Battery Critical',
      enabled: true,
      level: AlarmLevel.critical,
      condition: const AlarmCondition(
        source: AlarmConditionSource.vesselMetric,
        metric: 'battery_voltage_main',
        operator: AlarmOperator.lessEqual,
        threshold: 11.5,
        cooldownMs: 300000,
      ),
      responsePlan: const AlarmResponsePlan(inApp: true, sound: true),
      snoozeMins: 0,
      isBuiltIn: true,
      updatedAt: now,
      sourceDeviceId: deviceId,
    ),
    AlarmRule(
      id: 'builtin_wind',
      name: 'High Wind',
      enabled: true,
      level: AlarmLevel.warning,
      condition: const AlarmCondition(
        source: AlarmConditionSource.vesselMetric,
        metric: 'wind_true_speed',
        operator: AlarmOperator.greaterEqual,
        threshold: 20.0,
        cooldownMs: 300000,
      ),
      responsePlan: const AlarmResponsePlan(inApp: true, sound: true),
      snoozeMins: 15,
      isBuiltIn: false,
      updatedAt: now,
      sourceDeviceId: deviceId,
    ),
  ];
}

// ---------------------------------------------------------------------------
// AlarmRuleNotifier
// ---------------------------------------------------------------------------

class AlarmRuleNotifier extends Notifier<List<AlarmRule>> {
  static const _storeName = 'yokuli_alarm_rules';

  @override
  List<AlarmRule> build() => const [];

  // ---- Persistence ----------------------------------------------------------

  Future<void> load() async {
    final deviceId = ref.read(deviceProvider).deviceId;
    final defaults = _defaultRules(deviceId);

    final rows = await _JsonStore.load(_storeName);
    if (rows.isEmpty) {
      state = defaults;
      return;
    }

    // Build a map from stored data, keyed by id
    final stored = <String, Map<String, dynamic>>{
      for (final r in rows) r['id'] as String: r,
    };

    // Apply LWW merge: defaults that have no stored version are kept as-is;
    // defaults that have a stored counterpart are LWW-merged.
    final merged = Map<String, Map<String, dynamic>>.from(stored);
    for (final def in defaults) {
      final defJson = def.toJson();
      final id = def.id;
      if (!merged.containsKey(id)) {
        merged[id] = defJson;
      } else {
        merged[id] = SyncEngine.merge(merged[id], defJson);
      }
    }

    state = merged.values.map(AlarmRule.fromJson).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> _save() async {
    await _JsonStore.save(
        _storeName, state.map((r) => r.toJson()).toList());
  }

  // ---- Mutations ------------------------------------------------------------

  /// Upsert a rule locally. Broadcasts the change to peers.
  Future<void> upsert(AlarmRule rule) async {
    final idx = state.indexWhere((r) => r.id == rule.id);
    if (idx >= 0) {
      final updated = List<AlarmRule>.from(state);
      updated[idx] = rule;
      state = updated;
    } else {
      state = [...state, rule];
    }
    await _save();
    ref.read(deviceProvider.notifier).bump();
    ref.read(lanBroadcastProvider)?.call({
      'type': 'alarm_rules_sync',
      'rules': [rule.toJson()],
    });
  }

  /// Apply a batch of records received from LAN sync (LWW merge, no rebroadcast).
  Future<void> applyRemote(List<Map<String, dynamic>> records) async {
    final existing = <String, Map<String, dynamic>>{
      for (final r in state) r.id: r.toJson(),
    };
    final result = SyncEngine.applyBatch(existing, records);
    state = result.values.map(AlarmRule.fromJson).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    await _save();
  }

  /// Soft-delete a non-built-in rule. Built-in rules are ignored.
  Future<void> delete(String id) async {
    final idx = state.indexWhere((r) => r.id == id);
    if (idx < 0) return;
    final rule = state[idx];
    if (rule.isBuiltIn) return;
    final deleted = rule.copyWith(
      deleted: true,
      updatedAt: DateTime.now(),
    );
    final updated = List<AlarmRule>.from(state);
    updated[idx] = deleted;
    state = updated;
    await _save();
    ref.read(deviceProvider.notifier).bump();
    ref.read(lanBroadcastProvider)?.call({
      'type': 'alarm_rules_sync',
      'rules': [deleted.toJson()],
    });
  }

  // ---- Derived helpers (available but prefer derived provider below) --------

  /// Rules that are not deleted and are enabled, sorted by name.
  List<AlarmRule> get activeRules => state
      .where((r) => !r.deleted && r.enabled)
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
}

// ---------------------------------------------------------------------------
// NotifyChannelNotifier
// ---------------------------------------------------------------------------

class NotifyChannelNotifier extends Notifier<NotifyChannelConfig> {
  static const _prefsKey = 'notify_channel_v2';

  @override
  NotifyChannelConfig build() {
    load(); // unawaited
    return const NotifyChannelConfig();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      state = NotifyChannelConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.toJson()));
  }

  /// Update the channel configuration and broadcast to peers.
  Future<void> update(NotifyChannelConfig config) async {
    state = config;
    await _save();
    ref.read(deviceProvider.notifier).bump();
    ref.read(lanBroadcastProvider)?.call({
      'type': 'notify_channel_sync',
      'data': config.toJson(),
    });
  }

  /// Apply configuration received from a remote peer (no rebroadcast).
  Future<void> applySync(Map<String, dynamic> json) async {
    try {
      state = NotifyChannelConfig.fromJson(json);
      await _save();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final alarmRuleProvider =
    NotifierProvider<AlarmRuleNotifier, List<AlarmRule>>(AlarmRuleNotifier.new);

/// Rules that are not deleted and are enabled, sorted by name.
final activeAlarmRulesProvider = Provider<List<AlarmRule>>((ref) {
  return ref
      .watch(alarmRuleProvider)
      .where((r) => !r.deleted && r.enabled)
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
});

final notifyChannelProvider =
    NotifierProvider<NotifyChannelNotifier, NotifyChannelConfig>(
        NotifyChannelNotifier.new);
