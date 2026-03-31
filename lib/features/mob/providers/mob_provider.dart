import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/models/mob_alert.dart';
import '../../../core/models/mob_trigger_rule.dart';
import '../../../core/models/log_entry.dart';
import '../../../core/providers/lan_broadcast.dart';
import '../../../core/providers/log_provider.dart';
import '../../../core/providers/vessel_provider.dart';
import '../../../core/services/lan_sync/lan_sync_service.dart';
import '../../../core/services/telemetry_service.dart';
import '../../../core/utils/id_gen.dart';

const _kMobRuleSync = 'mob_rule_sync';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class MobState {
  final MobAlert? activeMob;
  final List<MobTriggerRule> rules;

  /// Most-recent cleared MOB events (newest first), capped at 50.
  final List<MobAlert> history;

  const MobState({
    this.activeMob,
    this.rules = const [],
    this.history = const [],
  });

  bool get isMobActive => activeMob?.isActive == true;

  MobState copyWith({
    MobAlert? activeMob,
    bool clearActiveMob = false,
    List<MobTriggerRule>? rules,
    List<MobAlert>? history,
  }) =>
      MobState(
        activeMob: clearActiveMob ? null : activeMob ?? this.activeMob,
        rules: rules ?? this.rules,
        history: history ?? this.history,
      );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class MobNotifier extends Notifier<MobState> {
  static const _storeRules = 'yokuli_mob_rules';
  static const _storeHistory = 'yokuli_mob_history';
  static const _historyLimit = 50;

  @override
  MobState build() => const MobState();

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> load() async {
    final rules = await _loadRules();
    final history = await _loadHistory();
    state = MobState(rules: rules, history: history);
  }

  Future<List<MobTriggerRule>> _loadRules() async {
    try {
      final f = await _file(_storeRules);
      if (!await f.exists()) return [];
      final raw = jsonDecode(await f.readAsString()) as List;
      return raw.map((e) => MobTriggerRule.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<MobAlert>> _loadHistory() async {
    try {
      final f = await _file(_storeHistory);
      if (!await f.exists()) return [];
      final raw = jsonDecode(await f.readAsString()) as List;
      return raw.map((e) => MobAlert.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveRules() async {
    try {
      (await _file(_storeRules))
          .writeAsString(jsonEncode(state.rules.map((r) => r.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      (await _file(_storeHistory))
          .writeAsString(jsonEncode(state.history.map((h) => h.toJson()).toList()));
    } catch (_) {}
  }

  static Future<File> _file(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name.json');
  }

  // ── MOB lifecycle ──────────────────────────────────────────────────────────

  void trigger({
    String triggerSource = 'manual',
    String? triggerRuleName,
  }) {
    if (state.isMobActive) return; // already active

    final vessel = ref.read(vesselProvider);
    final alert = MobAlert(
      id: generateId(),
      triggeredAt: DateTime.now(),
      position: vessel.position,
      triggeredByDevice: 'this device',
      triggerSource: triggerSource,
      triggerRuleName: triggerRuleName,
    );
    state = state.copyWith(activeMob: alert);
    TelemetryService.instance.recordMobActivated();

    ref.read(logProvider.notifier).log(
      type: LogEntryType.system,
      subtype: 'mob_start',
      message: triggerSource == 'manual'
          ? 'MOB ALERT — 本设备手动触发'
          : 'MOB ALERT — 自动规则触发: $triggerRuleName',
    );

    // Broadcast to LAN peers
    ref.read(lanSyncServiceProvider).triggerMob(alert);
  }

  void cancel() {
    final mob = state.activeMob;
    if (mob == null) return;

    final elapsed = mob.elapsed;
    final mins = elapsed.inMinutes;
    final secs = elapsed.inSeconds % 60;

    final cleared = mob.copyWith(
      isActive: false,
      clearedAt: DateTime.now(),
    );

    // Move to history
    final newHistory = [cleared, ...state.history].take(_historyLimit).toList();

    state = state.copyWith(clearActiveMob: true, history: newHistory);
    _saveHistory();

    TelemetryService.instance.recordMobCleared();

    ref.read(logProvider.notifier).log(
      type: LogEntryType.system,
      subtype: 'mob_end',
      message: 'MOB 已解除 — 历时 ${mins}分${secs}秒',
    );

    ref.read(lanBroadcastProvider)?.call({'type': 'mob_cancel'});
  }

  /// Receive a MOB alert from a LAN peer.
  void receiveMob(MobAlert alert) {
    if (state.isMobActive) return;
    state = state.copyWith(activeMob: alert);
    TelemetryService.instance.recordMobActivated();
    ref.read(logProvider.notifier).log(
      type: LogEntryType.system,
      subtype: 'mob_start',
      message: 'MOB ALERT — 接收自远程设备',
    );
  }

  /// Receive a MOB cancel from a LAN peer.
  void receiveMobCancel() {
    final mob = state.activeMob;
    if (mob == null) return;

    final cleared = mob.copyWith(
      isActive: false,
      clearedAt: DateTime.now(),
    );
    final newHistory = [cleared, ...state.history].take(_historyLimit).toList();
    state = state.copyWith(clearActiveMob: true, history: newHistory);
    _saveHistory();

    ref.read(logProvider.notifier).log(
      type: LogEntryType.system,
      subtype: 'mob_end',
      message: 'MOB 已解除 — 接收自远程设备',
    );
  }

  // ── Rule management ────────────────────────────────────────────────────────

  Future<void> addRule(MobTriggerRule rule) async {
    state = state.copyWith(rules: [...state.rules, rule]);
    await _saveRules();
    ref.read(lanBroadcastProvider)?.call({'type': _kMobRuleSync, 'data': rule.toJson()});
  }

  Future<void> updateRule(MobTriggerRule updated) async {
    final rules = state.rules.map((r) => r.id == updated.id ? updated : r).toList();
    state = state.copyWith(rules: rules);
    await _saveRules();
    ref.read(lanBroadcastProvider)?.call({'type': _kMobRuleSync, 'data': updated.toJson()});
  }

  Future<void> deleteRule(String id) async {
    state = state.copyWith(rules: state.rules.where((r) => r.id != id).toList());
    await _saveRules();
    // Broadcast a tombstone so peers also remove the rule.
    ref.read(lanBroadcastProvider)?.call({'type': _kMobRuleSync, 'data': {'id': id, '_deleted': true}});
  }

  Future<void> toggleRule(String id, {required bool enabled}) async {
    final rules = state.rules.map((r) {
      if (r.id != id) return r;
      return r.copyWith(enabled: enabled, updatedAt: DateTime.now());
    }).toList();
    state = state.copyWith(rules: rules);
    await _saveRules();
    final toggled = state.rules.firstWhere((r) => r.id == id, orElse: () => state.rules.first);
    ref.read(lanBroadcastProvider)?.call({'type': _kMobRuleSync, 'data': toggled.toJson()});
  }

  /// Apply a rule received from a LAN peer — LWW merge, no re-broadcast.
  Future<void> applyRuleRemote(Map<String, dynamic> data) async {
    try {
      final id = data['id'] as String?;
      if (id == null) return;
      // Tombstone → delete locally
      if (data['_deleted'] == true) {
        state = state.copyWith(rules: state.rules.where((r) => r.id != id).toList());
        await _saveRules();
        return;
      }
      final incoming = MobTriggerRule.fromJson(data);
      final idx = state.rules.indexWhere((r) => r.id == id);
      List<MobTriggerRule> rules;
      if (idx >= 0) {
        // LWW: keep whichever was updated more recently
        if (!incoming.updatedAt.isAfter(state.rules[idx].updatedAt)) return;
        rules = List.from(state.rules);
        rules[idx] = incoming;
      } else {
        rules = [...state.rules, incoming];
      }
      state = state.copyWith(rules: rules);
      await _saveRules();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final mobProvider = NotifierProvider<MobNotifier, MobState>(MobNotifier.new);
