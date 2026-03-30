import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/vessel_state.dart';

/// Central vessel state — updated by SignalK client or LAN sync client
class VesselStateNotifier extends Notifier<VesselState> {
  @override
  VesselState build() => VesselState.empty();

  void update(VesselState newState) {
    state = newState;
  }

  void applyPartial(VesselState partial) {
    state = VesselState(
      speedOverGround: partial.speedOverGround ?? state.speedOverGround,
      courseOverGround: partial.courseOverGround ?? state.courseOverGround,
      heading: partial.heading ?? state.heading,
      position: partial.position ?? state.position,
      trueWindSpeed: partial.trueWindSpeed ?? state.trueWindSpeed,
      trueWindDirection: partial.trueWindDirection ?? state.trueWindDirection,
      apparentWindSpeed: partial.apparentWindSpeed ?? state.apparentWindSpeed,
      apparentWindAngle: partial.apparentWindAngle ?? state.apparentWindAngle,
      depthBelowKeel: partial.depthBelowKeel ?? state.depthBelowKeel,
      depthBelowSurface: partial.depthBelowSurface ?? state.depthBelowSurface,
      batteries: partial.batteries.isNotEmpty ? partial.batteries : state.batteries,
      lastUpdated: partial.lastUpdated,
      sourceDeviceId: partial.sourceDeviceId ?? state.sourceDeviceId,
    );
  }

  void reset() => state = VesselState.empty();
}

final vesselProvider = NotifierProvider<VesselStateNotifier, VesselState>(
  VesselStateNotifier.new,
);

// Convenience selectors (avoid rebuilding entire tree)
final sogProvider = Provider<double?>((ref) => ref.watch(vesselProvider).speedOverGround);
final cogProvider = Provider<double?>((ref) => ref.watch(vesselProvider).courseOverGround);
final headingProvider = Provider<double?>((ref) => ref.watch(vesselProvider).heading);
final positionProvider = Provider<GpsPosition?>((ref) => ref.watch(vesselProvider).position);
final depthProvider = Provider<double?>((ref) => ref.watch(vesselProvider).depthBelowKeel);
final trueWindSpeedProvider = Provider<double?>((ref) => ref.watch(vesselProvider).trueWindSpeed);
final trueWindDirProvider =
    Provider<double?>((ref) => ref.watch(vesselProvider).trueWindDirection);
final apparentWindSpeedProvider =
    Provider<double?>((ref) => ref.watch(vesselProvider).apparentWindSpeed);
final apparentWindAngleProvider =
    Provider<double?>((ref) => ref.watch(vesselProvider).apparentWindAngle);
final batteriesProvider =
    Provider<Map<String, BatteryState>>((ref) => ref.watch(vesselProvider).batteries);
