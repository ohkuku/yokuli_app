import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alarm.dart';
import '../models/alarm_rule.dart';
import 'lan_broadcast.dart';

// ---------------------------------------------------------------------------
// Default rules
// ---------------------------------------------------------------------------

Map<AlarmType, AlarmRuleConfig> _defaultRules() => {
      AlarmType.battery: AlarmRuleConfig(
        type: AlarmType.battery,
        channels: {NotifyChannel.inApp, NotifyChannel.sound},
        snoozeMins: 15,
      ),
      AlarmType.depth: AlarmRuleConfig(
        type: AlarmType.depth,
        channels: {NotifyChannel.inApp, NotifyChannel.sound},
        snoozeMins: 5,
      ),
      AlarmType.speed: AlarmRuleConfig(
        type: AlarmType.speed,
        channels: {NotifyChannel.inApp, NotifyChannel.sound},
        snoozeMins: 15,
      ),
      AlarmType.ais: AlarmRuleConfig(
        type: AlarmType.ais,
        channels: {NotifyChannel.inApp, NotifyChannel.sound},
        snoozeMins: 5,
      ),
      AlarmType.mob: AlarmRuleConfig(
        type: AlarmType.mob,
        channels: {NotifyChannel.inApp, NotifyChannel.sound},
        snoozeMins: 0,
      ),
      AlarmType.solar: AlarmRuleConfig(
        type: AlarmType.solar,
        channels: {NotifyChannel.inApp},
        snoozeMins: 30,
      ),
      AlarmType.connection: AlarmRuleConfig(
        type: AlarmType.connection,
        channels: {NotifyChannel.inApp},
        snoozeMins: 60,
      ),
    };

// ---------------------------------------------------------------------------
// AlarmRuleNotifier
// ---------------------------------------------------------------------------

class AlarmRuleNotifier extends Notifier<Map<AlarmType, AlarmRuleConfig>> {
  static const _prefsKey = 'alarm_rules_v1';

  @override
  Map<AlarmType, AlarmRuleConfig> build() {
    load(); // unawaited
    return _defaultRules();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final result = Map<AlarmType, AlarmRuleConfig>.from(_defaultRules());
      for (final entry in map.entries) {
        final typeIndex = int.tryParse(entry.key);
        if (typeIndex == null || typeIndex >= AlarmType.values.length) continue;
        final type = AlarmType.values[typeIndex];
        result[type] = AlarmRuleConfig.fromJson(
            type, entry.value as Map<String, dynamic>);
      }
      state = result;
    } catch (_) {}
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final map = _toJsonMap();
    await prefs.setString(_prefsKey, jsonEncode(map));
  }

  Map<String, dynamic> _toJsonMap() {
    final map = <String, dynamic>{};
    for (final entry in state.entries) {
      map[entry.key.index.toString()] = entry.value.toJson();
    }
    return map;
  }

  /// Update a single rule and broadcast the full rules set to all peers.
  void updateRule(AlarmType type, AlarmRuleConfig config) {
    state = {...state, type: config};
    save();
    _broadcast();
  }

  /// Apply rules received from a remote peer — saves locally, no re-broadcast.
  void applySync(Map<String, dynamic> rulesJson) {
    final result = Map<AlarmType, AlarmRuleConfig>.from(_defaultRules());
    for (final entry in rulesJson.entries) {
      final typeIndex = int.tryParse(entry.key);
      if (typeIndex == null || typeIndex >= AlarmType.values.length) continue;
      final type = AlarmType.values[typeIndex];
      try {
        result[type] = AlarmRuleConfig.fromJson(
            type, entry.value as Map<String, dynamic>);
      } catch (_) {}
    }
    state = result;
    save();
  }

  void _broadcast() {
    ref.read(lanBroadcastProvider)?.call({
      'type': 'settings_sync',
      'data': {'alarmRules': _toJsonMap()},
    });
  }
}

// ---------------------------------------------------------------------------
// NotifyChannelNotifier
// ---------------------------------------------------------------------------

class NotifyChannelNotifier extends Notifier<NotifyChannelConfig> {
  static const _prefsKey = 'notify_channel_cfg_v1';

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

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.toJson()));
  }

  /// Update config and broadcast to all peers.
  void update(NotifyChannelConfig config) {
    state = config;
    save();
    _broadcast();
  }

  /// Apply config received from a remote peer — saves locally, no re-broadcast.
  void applySync(Map<String, dynamic> json) {
    try {
      state = NotifyChannelConfig.fromJson(json);
      save();
    } catch (_) {}
  }

  void _broadcast() {
    ref.read(lanBroadcastProvider)?.call({
      'type': 'settings_sync',
      'data': {'notifyChannel': state.toJson()},
    });
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final alarmRuleProvider =
    NotifierProvider<AlarmRuleNotifier, Map<AlarmType, AlarmRuleConfig>>(
        AlarmRuleNotifier.new);

final notifyChannelProvider =
    NotifierProvider<NotifyChannelNotifier, NotifyChannelConfig>(
        NotifyChannelNotifier.new);
