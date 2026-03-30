import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/alarm.dart';
import '../models/vessel_state.dart';
import '../utils/id_gen.dart';
import 'lan_broadcast.dart';
import 'vessel_provider.dart';

// ---------------------------------------------------------------------------
// _JsonStore — private file-based JSON persistence helper
// ---------------------------------------------------------------------------

class _JsonStore {
  static Future<File> _file(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/yokuli_$name.json');
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
// Alarm thresholds
// ---------------------------------------------------------------------------

/// Battery voltage below which a battery alarm is raised (Volts).
const double _batteryLowVoltageThreshold = 11.8;

// ---------------------------------------------------------------------------
// AlarmNotifier
// ---------------------------------------------------------------------------

class AlarmNotifier extends Notifier<List<Alarm>> {
  static const String _storeName = 'alarms';

  @override
  List<Alarm> build() {
    // Watch vessel state and check battery voltages on every update.
    ref.listen(vesselProvider, (_, vessel) => _checkBatteries(vessel));
    return const [];
  }

  // ---- Persistence --------------------------------------------------------

  Future<void> load() async {
    final rows = await _JsonStore.load(_storeName);
    state = rows.map(Alarm.fromJson).toList();
  }

  Future<void> save() async {
    await _JsonStore.save(
        _storeName, state.map((a) => a.toJson()).toList());
  }

  Future<void> importAll(List<Map<String, dynamic>> rows) async {
    state = rows.map(Alarm.fromJson).toList();
    await save();
  }

  // ---- Trigger / lifecycle ------------------------------------------------

  /// Trigger a new alarm. Returns the new alarm's ID.
  ///
  /// If an alarm of the same [type] is already active, the call is a no-op
  /// and the existing alarm's ID is returned.
  String trigger({
    required AlarmType type,
    required AlarmLevel level,
    required String message,
    String? linkedLogId,
  }) {
    // Deduplicate: don't raise the same alarm type twice while active.
    final existing = state.where(
        (a) => a.type == type && a.status == AlarmStatus.active);
    if (existing.isNotEmpty) {
      return existing.first.id;
    }

    final now = DateTime.now();
    final alarm = Alarm(
      id: generateId(),
      type: type,
      level: level,
      status: AlarmStatus.active,
      triggeredAt: now,
      message: message,
      linkedLogId: linkedLogId,
      updatedAt: now,
    );

    state = [...state, alarm];
    save(); // fire-and-forget
    ref.read(lanBroadcastProvider)?.call(
        {'type': 'alarm', 'data': alarm.toJson()});
    return alarm.id;
  }

  /// Acknowledge an active alarm (moves it to acknowledged state).
  void acknowledge(String id, {String? by}) {
    final now = DateTime.now();
    state = state.map((a) {
      if (a.id != id || a.status != AlarmStatus.active) return a;
      return a.copyWith(
        status: AlarmStatus.acknowledged,
        acknowledgedBy: by,
        updatedAt: now,
      );
    }).toList();
    save();
    final updated = state.firstWhere((a) => a.id == id);
    ref.read(lanBroadcastProvider)?.call(
        {'type': 'alarm', 'data': updated.toJson()});
  }

  /// Clear an alarm (moves it to cleared state and records the time).
  void clear(String id) {
    final now = DateTime.now();
    state = state.map((a) {
      if (a.id != id) return a;
      if (a.status == AlarmStatus.cleared) return a;
      return a.copyWith(
        status: AlarmStatus.cleared,
        clearedAt: now,
        updatedAt: now,
      );
    }).toList();
    save();
    final updated = state.firstWhere((a) => a.id == id, orElse: () => state.first);
    ref.read(lanBroadcastProvider)?.call(
        {'type': 'alarm', 'data': updated.toJson()});
  }

  // ---- Auto-check vessel state --------------------------------------------

  /// Inspect live [vessel] data and raise alarms when thresholds are breached.
  ///
  /// Called by the service layer whenever a new VesselState arrives.
  void checkVesselState(VesselState vessel) {
    _checkBatteries(vessel);
  }

  void _checkBatteries(VesselState vessel) {
    if (vessel.batteries.isEmpty) return;

    String? firstLowName;
    double? firstLowVoltage;
    var level = AlarmLevel.warning;

    for (final b in vessel.batteries.values) {
      final v = b.voltage;
      if (v == null) continue;
      if (v < _batteryLowVoltageThreshold) {
        firstLowName ??= b.name;
        firstLowVoltage ??= v;
        if (v < 11.5) level = AlarmLevel.critical;
      }
    }

    if (firstLowVoltage != null) {
      // Rising edge: trigger only if no active/snoozed battery alarm exists.
      final hasAlarm = state.any((a) =>
          a.type == AlarmType.battery &&
          (a.status == AlarmStatus.active ||
              a.status == AlarmStatus.snoozed));
      if (!hasAlarm) {
        trigger(
          type: AlarmType.battery,
          level: level,
          message:
              'Battery "$firstLowName" voltage low: ${firstLowVoltage.toStringAsFixed(1)} V',
        );
      }
    } else {
      // Falling edge: all batteries recovered — clear any active battery alarm.
      clearActiveByType(AlarmType.battery);
    }
  }

  // ---- Snooze / reactivate ------------------------------------------------

  /// Snooze an alarm for [mins] minutes.
  void snooze(String id, int mins) {
    final now = DateTime.now();
    state = state.map((a) {
      if (a.id != id) return a;
      if (a.status == AlarmStatus.cleared) return a;
      return a.copyWith(
        status: AlarmStatus.snoozed,
        snoozedUntil: now.add(Duration(minutes: mins)),
        updatedAt: now,
      );
    }).toList();
    save();
    final updated = state.firstWhere((a) => a.id == id, orElse: () => state.first);
    ref.read(lanBroadcastProvider)?.call(
        {'type': 'alarm', 'data': updated.toJson()});
  }

  /// Reactivate a snoozed alarm (snooze period expired).
  void reactivate(String id) {
    final now = DateTime.now();
    state = state.map((a) {
      if (a.id != id || a.status != AlarmStatus.snoozed) return a;
      return a.copyWith(
        status: AlarmStatus.active,
        snoozedUntil: null,
        updatedAt: now,
      );
    }).toList();
    save();
  }

  /// Clear all active alarms of a given [type] (used by SafetyNotifier).
  void clearActiveByType(AlarmType type) {
    for (final a in state.where(
        (a) => a.type == type && a.status == AlarmStatus.active).toList()) {
      clear(a.id);
    }
  }

  // ---- Accessors ----------------------------------------------------------

  /// All alarms currently in the [AlarmStatus.active] state.
  List<Alarm> get active =>
      state.where((a) => a.status == AlarmStatus.active && !a.deleted).toList();

  /// All alarms currently in the [AlarmStatus.acknowledged] state.
  List<Alarm> get acknowledged =>
      state.where((a) => a.status == AlarmStatus.acknowledged && !a.deleted).toList();

  /// All alarms currently in the [AlarmStatus.snoozed] state.
  List<Alarm> get snoozed =>
      state.where((a) => a.status == AlarmStatus.snoozed && !a.deleted).toList();

  /// Active + snoozed + acknowledged alarms (i.e. not yet cleared).
  List<Alarm> get uncleared =>
      state.where((a) => a.status != AlarmStatus.cleared && !a.deleted).toList();

  /// Upsert an [Alarm] received from a remote device (LAN sync).
  /// Per-record LWW: only overwrites if incoming updatedAt is strictly newer.
  Future<void> upsertRemote(Map<String, dynamic> data) async {
    try {
      final alarm = Alarm.fromJson(data);
      final idx = state.indexWhere((a) => a.id == alarm.id);
      if (idx >= 0) {
        if (!alarm.updatedAt.isAfter(state[idx].updatedAt)) return;
        final updated = List<Alarm>.from(state);
        updated[idx] = alarm;
        state = updated;
      } else {
        state = [...state, alarm];
      }
      await save();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final alarmProvider =
    NotifierProvider<AlarmNotifier, List<Alarm>>(AlarmNotifier.new);

/// All currently active alarms (status == active).
final activeAlarmsProvider = Provider<List<Alarm>>(
  (ref) => ref.watch(alarmProvider.notifier).active,
);

/// Active + acknowledged alarms (not yet cleared).
final unclearedAlarmsProvider = Provider<List<Alarm>>(
  (ref) => ref.watch(alarmProvider.notifier).uncleared,
);

/// Count of active (and snoozed) alarms — useful for badge indicators.
final activeAlarmCountProvider = Provider<int>(
  (ref) => ref
      .watch(alarmProvider)
      .where((a) =>
          !a.deleted &&
          (a.status == AlarmStatus.active || a.status == AlarmStatus.snoozed))
      .length,
);
