import 'dart:math' as math;
import '../../models/vessel_state.dart';

/// Parses Signal K delta messages and applies them to VesselState.
/// Signal K units: speed in m/s, angles in radians.
class SignalKParser {
  static const _msToKnots = 1.94384;
  static const _radToDeg = 180 / math.pi;

  /// Apply a parsed delta JSON map onto the current state, return new state.
  static VesselState applyDelta(VesselState current, Map<String, dynamic> delta) {
    final updates = delta['updates'] as List<dynamic>?;
    if (updates == null) return current;

    var state = current;
    for (final update in updates) {
      final values = update['values'] as List<dynamic>?;
      if (values == null) continue;
      for (final item in values) {
        final path = item['path'] as String?;
        final value = item['value'];
        if (path == null || value == null) continue;
        state = _applyPath(state, path, value);
      }
    }

    return state.copyWith(lastUpdated: DateTime.now());
  }

  static VesselState _applyPath(VesselState state, String path, dynamic value) {
    try {
      switch (path) {
        case 'navigation.speedOverGround':
          return state.copyWith(speedOverGround: _toDouble(value) * _msToKnots);

        case 'navigation.speedThroughWater':
          // Only use if SOG not available
          if (state.speedOverGround == null) {
            return state.copyWith(speedOverGround: _toDouble(value) * _msToKnots);
          }
          return state;

        case 'navigation.courseOverGroundTrue':
          return state.copyWith(courseOverGround: _toDouble(value) * _radToDeg);

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
                  altitude: value['altitude'] != null ? _toDouble(value['altitude']) : null,
                  timestamp: DateTime.now(),
                ),
              );
            }
          }
          return state;

        case 'environment.wind.speedTrue':
          return state.copyWith(trueWindSpeed: _toDouble(value) * _msToKnots);

        case 'environment.wind.directionTrue':
          return state.copyWith(trueWindDirection: _toDouble(value) * _radToDeg);

        case 'environment.wind.directionGround':
          if (state.trueWindDirection == null) {
            return state.copyWith(trueWindDirection: _toDouble(value) * _radToDeg);
          }
          return state;

        case 'environment.wind.speedApparent':
          return state.copyWith(apparentWindSpeed: _toDouble(value) * _msToKnots);

        case 'environment.wind.angleApparent':
          // Signal K: 0..2π, starboard positive. Convert to -180..+180 deg
          final deg = _toDouble(value) * _radToDeg;
          final normalised = deg > 180 ? deg - 360 : deg;
          return state.copyWith(apparentWindAngle: normalised);

        case 'environment.depth.belowKeel':
          return state.copyWith(depthBelowKeel: _toDouble(value));

        case 'environment.depth.belowSurface':
          return state.copyWith(depthBelowSurface: _toDouble(value));

        case 'environment.depth.belowTransducer':
          if (state.depthBelowKeel == null && state.depthBelowSurface == null) {
            return state.copyWith(depthBelowKeel: _toDouble(value));
          }
          return state;

        default:
          if (path.startsWith('electrical.batteries.')) {
            return _applyBatteryPath(state, path, value);
          }
          return state;
      }
    } catch (_) {
      // Silently skip malformed values
      return state;
    }
  }

  static VesselState _applyBatteryPath(
      VesselState state, String path, dynamic value) {
    final parts = path.split('.');
    if (parts.length < 4) return state;

    final batteryId = parts[2]; // e.g. "house", "engine", "0"
    final field = parts.sublist(3).join('.'); // e.g. "voltage", "capacity.stateOfCharge"

    final batteries = Map<String, BatteryState>.from(state.batteries);
    final existing = batteries[batteryId] ??
        BatteryState(id: batteryId, name: _prettifyId(batteryId));

    BatteryState? updated;
    switch (field) {
      case 'voltage':
        updated = existing.copyWith(voltage: _toDouble(value));
      case 'current':
        updated = existing.copyWith(current: _toDouble(value));
      case 'capacity.stateOfCharge':
        updated = existing.copyWith(stateOfCharge: _toDouble(value));
      case 'temperature':
        updated = existing.copyWith(temperature: _toDouble(value) - 273.15); // K→°C
    }

    if (updated == null) return state;
    batteries[batteryId] = updated;
    return state.copyWith(batteries: batteries);
  }

  static double _toDouble(dynamic value) => (value as num).toDouble();

  static String _prettifyId(String id) {
    if (id.isEmpty) return id;
    return id[0].toUpperCase() + id.substring(1);
  }

  /// Build the Signal K subscription message for paths we care about
  static Map<String, dynamic> buildSubscribeMessage() => {
        'context': 'vessels.self',
        'subscribe': [
          {'path': 'navigation.speedOverGround', 'period': 1000, 'policy': 'ideal'},
          {'path': 'navigation.speedThroughWater', 'period': 1000, 'policy': 'ideal'},
          {'path': 'navigation.courseOverGroundTrue', 'period': 1000, 'policy': 'ideal'},
          {'path': 'navigation.headingTrue', 'period': 500, 'policy': 'ideal'},
          {'path': 'navigation.headingMagnetic', 'period': 500, 'policy': 'ideal'},
          {'path': 'navigation.position', 'period': 1000, 'policy': 'ideal'},
          {'path': 'environment.wind.speedTrue', 'period': 500, 'policy': 'ideal'},
          {'path': 'environment.wind.directionTrue', 'period': 500, 'policy': 'ideal'},
          {'path': 'environment.wind.speedApparent', 'period': 500, 'policy': 'ideal'},
          {'path': 'environment.wind.angleApparent', 'period': 500, 'policy': 'ideal'},
          {'path': 'environment.depth.belowKeel', 'period': 1000, 'policy': 'ideal'},
          {'path': 'environment.depth.belowSurface', 'period': 1000, 'policy': 'ideal'},
          {'path': 'environment.depth.belowTransducer', 'period': 1000, 'policy': 'ideal'},
          {'path': 'electrical.batteries.*.voltage', 'period': 5000, 'policy': 'ideal'},
          {'path': 'electrical.batteries.*.current', 'period': 5000, 'policy': 'ideal'},
          {
            'path': 'electrical.batteries.*.capacity.stateOfCharge',
            'period': 5000,
            'policy': 'ideal'
          },
          {'path': 'electrical.batteries.*.temperature', 'period': 10000, 'policy': 'ideal'},
        ],
      };
}
