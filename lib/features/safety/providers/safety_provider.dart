import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/mob_alert.dart';
import '../../../core/models/vessel_state.dart';
import '../../../core/providers/vessel_provider.dart';
import '../../../core/providers/lan_broadcast.dart';
import '../../../core/services/lan_sync/lan_sync_service.dart';

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
  @override
  SafetyState build() {
    // Watch vessel state for alarm checks
    ref.listen(vesselProvider, (prev, vessel) => _checkAlarms(vessel));
    return const SafetyState();
  }

  void triggerMob() {
    final vessel = ref.read(vesselProvider);
    final alert = MobAlert(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      triggeredAt: DateTime.now(),
      position: vessel.position,
      triggeredByDevice: 'this device',
    );
    state = state.copyWith(activeMob: alert);
    // Broadcast to LAN peers
    ref.read(lanSyncServiceProvider).triggerMob(alert);
  }

  void cancelMob() {
    if (state.activeMob != null) {
      state.activeMob!.isActive = false;
      state = state.copyWith(clearMob: true);
      ref.read(lanBroadcastProvider)?.call({'type': 'mob_cancel'});
    }
  }

  void receiveMob(MobAlert alert) {
    state = state.copyWith(activeMob: alert);
  }

  /// Called when a remote device cancelled the MOB — clears locally without re-broadcasting.
  void receiveMobCancel() {
    if (state.activeMob != null) {
      state.activeMob!.isActive = false;
      state = state.copyWith(clearMob: true);
    }
  }

  void setDepthAlarm({required bool enabled, double? threshold}) {
    state = state.copyWith(
      depthAlarmEnabled: enabled,
      depthAlarmThreshold: threshold,
    );
  }

  void setSpeedAlarm({required bool enabled, double? threshold}) {
    state = state.copyWith(
      speedAlarmEnabled: enabled,
      speedAlarmThreshold: threshold,
    );
  }

  void _checkAlarms(VesselState vessel) {
    bool changed = false;
    SafetyState next = state;

    if (state.depthAlarmEnabled && vessel.depthBelowKeel != null) {
      final triggered = vessel.depthBelowKeel! < state.depthAlarmThreshold;
      if (triggered != state.depthAlarmTriggered) {
        next = next.copyWith(depthAlarmTriggered: triggered);
        changed = true;
      }
    }

    if (state.speedAlarmEnabled && vessel.speedOverGround != null) {
      final triggered = vessel.speedOverGround! > state.speedAlarmThreshold;
      if (triggered != state.speedAlarmTriggered) {
        next = next.copyWith(speedAlarmTriggered: triggered);
        changed = true;
      }
    }

    if (changed) state = next;
  }
}

final safetyProvider = NotifierProvider<SafetyNotifier, SafetyState>(
  SafetyNotifier.new,
);
