import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/models/alarm.dart';
import '../../../core/models/mob_alert.dart';
import '../../../core/models/vessel_state.dart';
import '../../../core/models/log_entry.dart';
import '../../../core/providers/alarm_provider.dart';
import '../../../core/providers/log_provider.dart';
import '../../../core/providers/vessel_provider.dart';
import '../../../core/providers/lan_broadcast.dart';
import '../../../core/services/lan_sync/lan_sync_service.dart';
import '../../../core/utils/id_gen.dart';
import '../../../core/services/telemetry_service.dart';

class SafetyState {
  final MobAlert? activeMob;
  final bool depthAlarmEnabled;
  final double depthAlarmThreshold; // meters
  final bool depthAlarmTriggered;
  final bool speedAlarmEnabled;
  final double speedAlarmThreshold; // knots
  final bool speedAlarmTriggered;

  const SafetyState({
    this.activeMob,
    this.depthAlarmEnabled = false,
    this.depthAlarmThreshold = 2.0,
    this.depthAlarmTriggered = false,
    this.speedAlarmEnabled = false,
    this.speedAlarmThreshold = 15.0,
    this.speedAlarmTriggered = false,
  });

  bool get isMobActive => activeMob?.isActive == true;

  SafetyState copyWith({
    MobAlert? activeMob,
    bool clearMob = false,
    bool? depthAlarmEnabled,
    double? depthAlarmThreshold,
    bool? depthAlarmTriggered,
    bool? speedAlarmEnabled,
    double? speedAlarmThreshold,
    bool? speedAlarmTriggered,
  }) =>
      SafetyState(
        activeMob: clearMob ? null : activeMob ?? this.activeMob,
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
    // Watch vessel state for alarm checks
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

  void triggerMob() {
    final vessel = ref.read(vesselProvider);
    final alert = MobAlert(
      id: generateId(),
      triggeredAt: DateTime.now(),
      position: vessel.position,
      triggeredByDevice: 'this device',
    );
    state = state.copyWith(activeMob: alert);
    TelemetryService.instance.recordMobActivated();
    // Log MOB start
    ref.read(logProvider.notifier).log(
      type: LogEntryType.system,
      subtype: 'mob_start',
      message: 'MOB ALERT — person overboard triggered on this device',
    );
    // Broadcast to LAN peers
    ref.read(lanSyncServiceProvider).triggerMob(alert);
  }

  void cancelMob() {
    if (state.activeMob != null) {
      final elapsed = state.activeMob!.elapsed;
      final mins = elapsed.inMinutes;
      final secs = elapsed.inSeconds % 60;
      state.activeMob!.isActive = false;
      state = state.copyWith(clearMob: true);
      TelemetryService.instance.recordMobCleared();
      // Log MOB end
      ref.read(logProvider.notifier).log(
        type: LogEntryType.system,
        subtype: 'mob_end',
        message: 'MOB CANCELLED — alert ended after ${mins}m ${secs}s',
      );
      ref.read(lanBroadcastProvider)?.call({'type': 'mob_cancel'});
    }
  }

  void receiveMob(MobAlert alert) {
    state = state.copyWith(activeMob: alert);
    // Log receipt of remote MOB
    ref.read(logProvider.notifier).log(
      type: LogEntryType.system,
      subtype: 'mob_start',
      message: 'MOB ALERT — received from remote device',
    );
  }

  /// Called when a remote device cancelled the MOB — clears locally without re-broadcasting.
  void receiveMobCancel() {
    if (state.activeMob != null) {
      state.activeMob!.isActive = false;
      state = state.copyWith(clearMob: true);
      ref.read(logProvider.notifier).log(
        type: LogEntryType.system,
        subtype: 'mob_end',
        message: 'MOB CANCELLED — received cancellation from remote device',
      );
    }
  }

  void setDepthAlarm({required bool enabled, double? threshold}) {
    state = state.copyWith(
      depthAlarmEnabled: enabled,
      depthAlarmThreshold: threshold,
    );
    _save();
    _broadcastAlarmSettings();
  }

  void setSpeedAlarm({required bool enabled, double? threshold}) {
    state = state.copyWith(
      speedAlarmEnabled: enabled,
      speedAlarmThreshold: threshold,
    );
    _save();
    _broadcastAlarmSettings();
  }

  /// Apply alarm settings received from a remote peer (no re-broadcast).
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
