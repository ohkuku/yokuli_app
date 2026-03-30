import 'dart:math' as math;
import '../../models/vessel_state.dart';
import 'signalk_parser_power.dart';
import 'signalk_parser_ais.dart';

/// Parses Signal K delta messages and applies them to [VesselState].
///
/// Signal K units: speed in m/s, angles in radians.
///
/// Battery and solar parsing is delegated to [SignalKPowerParser].
/// AIS vessel updates (context 'vessels.*') are delegated to [SignalKAisParser].
class SignalKParser {
  static const _msToKnots = 1.94384;
  static const _radToDeg = 180 / math.pi;

  // ---------------------------------------------------------------------------
  // Main entry point
  // ---------------------------------------------------------------------------

  /// Apply a parsed Signal K delta JSON map onto the current [VesselState].
  ///
  /// [selfContext] is the 'self' field received in the hello message, used to
  /// distinguish own-ship AIS data from other vessel targets.
  static VesselState applyDelta(
    VesselState current,
    Map<String, dynamic> delta, {
    String? selfContext,
  }) {
    final updates = delta['updates'] as List<dynamic>?;
    if (updates == null) return current;

    var state = current;

    for (final update in updates) {
      // Some SK servers include a 'context' field inside each update object
      // (in addition to the top-level delta context).
      final updateContext =
          (update['context'] as String?) ?? (delta['context'] as String?);

      final values = update['values'] as List<dynamic>?;
      if (values == null) continue;

      // Cast values to a typed list for AIS parser.
      final typedValues = values
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);

      // If this update belongs to another vessel's context (not own-ship),
      // delegate entirely to the AIS parser.
      final isSelf = updateContext == null ||
                     updateContext == 'vessels.self' ||
                     (selfContext != null && updateContext == selfContext);
      if (!isSelf && updateContext!.startsWith('vessels.')) {
        state = SignalKAisParser.applyVesselDelta(
          state,
          updateContext,
          selfContext,
          typedValues,
        );
        continue;
      }

      // Otherwise, apply each path individually to the own-vessel state.
      for (final item in typedValues) {
        final path = item['path'] as String?;
        final value = item['value'];
        if (path == null || value == null) continue;
        state = _applyPath(state, path, value);
      }
    }

    // Rebuild the power summary after every delta so that the UI always has
    // an up-to-date aggregate view.
    final summary = SignalKPowerParser.buildSummary(state.batteries, state.solar);
    state = state.copyWith(
      powerSummary: summary,
      lastUpdated: DateTime.now(),
    );

    return state;
  }

  // ---------------------------------------------------------------------------
  // Path dispatcher
  // ---------------------------------------------------------------------------

  static VesselState _applyPath(
      VesselState state, String path, dynamic value) {
    try {
      switch (path) {
        // ---- Navigation ----
        case 'navigation.speedOverGround':
          return state.copyWith(
              speedOverGround: _toDouble(value) * _msToKnots);

        case 'navigation.speedThroughWater':
          // Only use if SOG is not yet available.
          if (state.speedOverGround == null) {
            return state.copyWith(
                speedOverGround: _toDouble(value) * _msToKnots);
          }
          return state;

        case 'navigation.courseOverGroundTrue':
          return state.copyWith(
              courseOverGround: _toDouble(value) * _radToDeg);

        case 'navigation.headingTrue':
          return state.copyWith(heading: _toDouble(value) * _radToDeg);

        case 'navigation.headingMagnetic':
          if (state.heading == null) {
            return state.copyWith(heading: _toDouble(value) * _radToDeg);
          }
          return state;

        case 'navigation.position':
          if (value is Map<String, dynamic>) {
            final lat = value['latitude'];
            final lon = value['longitude'];
            if (lat != null && lon != null) {
              return state.copyWith(
                position: GpsPosition(
                  latitude: _toDouble(lat),
                  longitude: _toDouble(lon),
                  altitude: value['altitude'] != null
                      ? _toDouble(value['altitude'])
                      : null,
                  timestamp: DateTime.now(),
                ),
              );
            }
          }
          return state;

        // ---- Wind ----
        case 'environment.wind.speedTrue':
          return state.copyWith(
              trueWindSpeed: _toDouble(value) * _msToKnots);

        case 'environment.wind.directionTrue':
          return state.copyWith(
              trueWindDirection: _toDouble(value) * _radToDeg);

        case 'environment.wind.directionGround':
          if (state.trueWindDirection == null) {
            return state.copyWith(
                trueWindDirection: _toDouble(value) * _radToDeg);
          }
          return state;

        case 'environment.wind.speedApparent':
          return state.copyWith(
              apparentWindSpeed: _toDouble(value) * _msToKnots);

        case 'environment.wind.angleApparent':
          // Signal K: 0..2π, starboard positive. Convert to -180..+180 deg.
          final deg = _toDouble(value) * _radToDeg;
          final normalised = deg > 180 ? deg - 360 : deg;
          return state.copyWith(apparentWindAngle: normalised);

        // ---- Depth ----
        case 'environment.depth.belowKeel':
          return state.copyWith(depthBelowKeel: _toDouble(value));

        case 'environment.depth.belowSurface':
          return state.copyWith(depthBelowSurface: _toDouble(value));

        case 'environment.depth.belowTransducer':
          if (state.depthBelowKeel == null &&
              state.depthBelowSurface == null) {
            return state.copyWith(depthBelowKeel: _toDouble(value));
          }
          return state;

        // ---- Electrical ----
        default:
          if (path.startsWith('electrical.batteries.')) {
            return SignalKPowerParser.applyBatteryPath(state, path, value);
          }
          if (path.startsWith('electrical.solar.')) {
            return SignalKPowerParser.applySolarPath(state, path, value);
          }
          return state;
      }
    } catch (_) {
      // Silently skip malformed values.
      return state;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static double _toDouble(dynamic value) => (value as num).toDouble();

  // ---------------------------------------------------------------------------
  // Subscription messages
  // ---------------------------------------------------------------------------

  /// Signal K subscribe message for own-vessel paths (navigation, wind, depth,
  /// electrical).
  static Map<String, dynamic> buildSubscribeMessage() => {
        'context': 'vessels.self',
        'subscribe': [
          // Navigation
          {'path': 'navigation.speedOverGround', 'period': 1000, 'policy': 'ideal'},
          {'path': 'navigation.speedThroughWater', 'period': 1000, 'policy': 'ideal'},
          {'path': 'navigation.courseOverGroundTrue', 'period': 1000, 'policy': 'ideal'},
          {'path': 'navigation.headingTrue', 'period': 500, 'policy': 'ideal'},
          {'path': 'navigation.headingMagnetic', 'period': 500, 'policy': 'ideal'},
          {'path': 'navigation.position', 'period': 1000, 'policy': 'ideal'},
          // Wind
          {'path': 'environment.wind.speedTrue', 'period': 500, 'policy': 'ideal'},
          {'path': 'environment.wind.directionTrue', 'period': 500, 'policy': 'ideal'},
          {'path': 'environment.wind.speedApparent', 'period': 500, 'policy': 'ideal'},
          {'path': 'environment.wind.angleApparent', 'period': 500, 'policy': 'ideal'},
          // Depth
          {'path': 'environment.depth.belowKeel', 'period': 1000, 'policy': 'ideal'},
          {'path': 'environment.depth.belowSurface', 'period': 1000, 'policy': 'ideal'},
          {'path': 'environment.depth.belowTransducer', 'period': 1000, 'policy': 'ideal'},
          // Batteries
          {'path': 'electrical.batteries.*.voltage', 'period': 5000, 'policy': 'ideal'},
          {'path': 'electrical.batteries.*.current', 'period': 5000, 'policy': 'ideal'},
          {
            'path': 'electrical.batteries.*.capacity.stateOfCharge',
            'period': 5000,
            'policy': 'ideal'
          },
          {'path': 'electrical.batteries.*.temperature', 'period': 10000, 'policy': 'ideal'},
          // Solar – canonical paths
          {'path': 'electrical.solar.*.inputVoltage', 'period': 5000},
          {'path': 'electrical.solar.*.inputCurrent', 'period': 5000},
          {'path': 'electrical.solar.*.inputPower', 'period': 5000},
          {'path': 'electrical.solar.*.outputVoltage', 'period': 5000},
          {'path': 'electrical.solar.*.outputCurrent', 'period': 5000},
          {'path': 'electrical.solar.*.outputPower', 'period': 5000},
          {'path': 'electrical.solar.*.controllerTemperature', 'period': 10000},
          {'path': 'electrical.solar.*.chargerState', 'period': 5000},
          {'path': 'electrical.solar.*.yieldTodayWh', 'period': 60000},
          // Solar – aliases used by some SK server plugins (e.g. Victron)
          {'path': 'electrical.solar.*.panelVoltage', 'period': 5000},
          {'path': 'electrical.solar.*.panelCurrent', 'period': 5000},
          {'path': 'electrical.solar.*.chargeCurrent', 'period': 5000},
          {'path': 'electrical.solar.*.chargePower', 'period': 5000},
          {'path': 'electrical.solar.*.state', 'period': 5000},
          {'path': 'electrical.solar.*.yieldToday', 'period': 60000},
        ],
      };

  /// Signal K subscribe message for AIS data from all vessels.
  ///
  /// This must be sent as a separate message because it uses the
  /// 'vessels.*' context rather than 'vessels.self'.
  static Map<String, dynamic> buildAisSubscribeMessage() => {
        'context': 'vessels.*',
        'subscribe': [
          {'path': 'navigation.position', 'period': 5000},
          {'path': 'navigation.speedOverGround', 'period': 5000},
          {'path': 'navigation.courseOverGroundTrue', 'period': 5000},
          {'path': 'navigation.headingTrue', 'period': 5000},
          {'path': 'navigation.state', 'period': 10000},
          {'path': 'name', 'period': 60000},
          {'path': 'mmsi', 'period': 60000},
          {'path': 'communication.callsignVhf', 'period': 60000},
          {'path': 'design.aisShipType', 'period': 60000},
          {'path': 'navigation.destination.commonName', 'period': 60000},
        ],
      };
}
