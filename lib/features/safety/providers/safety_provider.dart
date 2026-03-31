import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/models/alarm.dart';
import '../../../core/models/vessel_state.dart';
import '../../../core/providers/alarm_provider.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/providers/vessel_provider.dart';
import '../../../core/providers/lan_broadcast.dart';

class SafetyState {
  final bool depthAlarmEnabled;
  final double depthAlarmThreshold; // meters
  final bool depthAlarmTriggered;
  final bool speedAlarmEnabled;
  final double speedAlarmThreshold; // knots
  final bool speedAlarmTriggered;

  const SafetyState({
    this.depthAlarmEnabled = false,
    this.depthAlarmThreshold = 2.0,
    this.depthAlarmTriggered = false,
    this.speedAlarmEnabled = false,
    this.speedAlarmThreshold = 15.0,
    this.speedAlarmTriggered = false,
  });

  SafetyState copyWith({
    bool? depthAlarmEnabled,
    double? depthAlarmThreshold,
    bool? depthAlarmTriggered,
    bool? speedAlarmEnabled,
    double? speedAlarmThreshold,
    bool? speedAlarmTriggered,
  }) =>
      SafetyState(
        depthAlarmEnabled: depthAlarmEnabled ?? this.depthAlarmEnabled,
        depthAlarmThreshold: depthAlarmThreshold ?? this.depthAlarmThreshold,
        depthAlarmTriggered: depthAlarmTriggered ?? this.depthAlarmTriggered,
        speedAlarmEnabled: speedAlarmEnabled ?? this.speedAlarmEnabled,
        speedAlarmThreshold: speedAlarmThreshold ?? this.speedAlarmThreshold,
        speedAlarmTriggered: speedAlarmTriggered ?? this.speedAlarmTriggered,
      );
}

class SafetyNotifier extends Notifier<SafetyState> {
  static const _keyDepthEnabled   = 'safety_depth_enabled';
  static const _keyDepthThreshold = 'safety_depth_threshold';
  static const _keySpeedEnabled   = 'safety_speed_enabled';
  static const _keySpeedThreshold = 'safety_speed_threshold';

  @override
  SafetyState build() {
    ref.listen(vesselProvider, (prev, vessel) => _checkAlarms(vessel));
    return const SafetyState();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      depthAlarmEnabled:   prefs.getBool(_keyDepthEnabled)      ?? false,
      depthAlarmThreshold: prefs.getDouble(_keyDepthThreshold)  ?? 2.0,
      speedAlarmEnabled:   prefs.getBool(_keySpeedEnabled)      ?? false,
      speedAlarmThreshold: prefs.getDouble(_keySpeedThreshold)  ?? 15.0,
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDepthEnabled,      state.depthAlarmEnabled);
    await prefs.setDouble(_keyDepthThreshold,  state.depthAlarmThreshold);
    await prefs.setBool(_keySpeedEnabled,      state.speedAlarmEnabled);
    await prefs.setDouble(_keySpeedThreshold,  state.speedAlarmThreshold);
  }

  void setDepthAlarm({required bool enabled, double? threshold}) {
    state = state.copyWith(
      depthAlarmEnabled: enabled,
      depthAlarmThreshold: threshold,
    );
    _save();
    _broadcastAlarmSettings();
    ref.read(deviceProvider.notifier).bump();
  }

  void setSpeedAlarm({required bool enabled, double? threshold}) {
    state = state.copyWith(
      speedAlarmEnabled: enabled,
      speedAlarmThreshold: threshold,
    );
    _save();
    _broadcastAlarmSettings();
    ref.read(deviceProvider.notifier).bump();
  }

  void applyAlarmSync(Map<String, dynamic> data) {
    final depthEnabled = data['depthAlarmEnabled'] as bool?;
    final depthThreshold = (data['depthAlarmThreshold'] as num?)?.toDouble();
    final speedEnabled = data['speedAlarmEnabled'] as bool?;
    final speedThreshold = (data['speedAlarmThreshold'] as num?)?.toDouble();
    state = state.copyWith(
      depthAlarmEnabled: depthEnabled,
      depthAlarmThreshold: depthThreshold,
      speedAlarmEnabled: speedEnabled,
      speedAlarmThreshold: speedThreshold,
    );
    _save();
  }

  void _broadcastAlarmSettings() {
    ref.read(lanBroadcastProvider)?.call({
      'type': 'settings_sync',
      'data': {
        'depthAlarmEnabled': state.depthAlarmEnabled,
        'depthAlarmThreshold': state.depthAlarmThreshold,
        'speedAlarmEnabled': state.speedAlarmEnabled,
        'speedAlarmThreshold': state.speedAlarmThreshold,
      },
    });
  }

  void _checkAlarms(VesselState vessel) {
    bool changed = false;
    SafetyState next = state;

    if (state.depthAlarmEnabled && vessel.depthBelowKeel != null) {
      final triggered = vessel.depthBelowKeel! < state.depthAlarmThreshold;
      if (triggered != state.depthAlarmTriggered) {
        next = next.copyWith(depthAlarmTriggered: triggered);
        changed = true;
        if (triggered) {
          ref.read(alarmProvider.notifier).trigger(
                type: AlarmType.depth,
                level: AlarmLevel.critical,
                message:
                    'Depth below keel: ${vessel.depthBelowKeel!.toStringAsFixed(1)} m'
                    ' (threshold ${state.depthAlarmThreshold.toStringAsFixed(1)} m)',
              );
        } else {
          ref.read(alarmProvider.notifier).clearActiveByType(AlarmType.depth);
        }
      }
    }

    if (state.speedAlarmEnabled && vessel.speedOverGround != null) {
      final triggered = vessel.speedOverGround! > state.speedAlarmThreshold;
      if (triggered != state.speedAlarmTriggered) {
        next = next.copyWith(speedAlarmTriggered: triggered);
        changed = true;
        if (triggered) {
          ref.read(alarmProvider.notifier).trigger(
                type: AlarmType.speed,
                level: AlarmLevel.warning,
                message:
                    'Speed over ground: ${vessel.speedOverGround!.toStringAsFixed(1)} kn'
                    ' (threshold ${state.speedAlarmThreshold.toStringAsFixed(1)} kn)',
              );
        } else {
          ref.read(alarmProvider.notifier).clearActiveByType(AlarmType.speed);
        }
      }
    }

    if (changed) state = next;
  }
}

final safetyProvider = NotifierProvider<SafetyNotifier, SafetyState>(
  SafetyNotifier.new,
);
