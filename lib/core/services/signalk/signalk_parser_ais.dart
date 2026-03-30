import 'dart:math' as math;

import '../../models/vessel_state.dart';
import '../../models/ais_state.dart';

/// Parses Signal K delta messages from the 'vessels.*' context and applies
/// them to [VesselState], updating both [VesselState.aisTargets] (other
/// vessels) and [VesselState.aisOwnShip] (own-vessel AIS identity data).
class SignalKAisParser {
  SignalKAisParser._();

  static const _msToKnots = 1.94384;
  static const _radToDeg = 180 / math.pi;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Applies a batch of Signal K value updates from [context] to [state].
  ///
  /// [context]     – e.g. 'vessels.urn:mrn:imo:mmsi:338234631' or
  ///                       'vessels.self'
  /// [selfContext] – the 'self' field from the SK hello message, used to
  ///                 distinguish own ship from other targets.
  /// [values]      – array of {'path': String, 'value': dynamic} maps.
  static VesselState applyVesselDelta(
    VesselState state,
    String context,
    String? selfContext,
    List<Map<String, dynamic>> values,
  ) {
    if (isSelf(context, selfContext)) {
      return _applyOwnShip(state, values);
    }

    final mmsi = extractMmsi(context);
    final targetId = mmsi ?? context; // fall back to full context string as key
    return _applyTarget(state, targetId, mmsi ?? '', values);
  }

  /// Extracts the MMSI from a context string of the form
  /// 'vessels.urn:mrn:imo:mmsi:<digits>' or 'vessels.mmsi:<digits>'.
  ///
  /// Returns [null] if no MMSI can be parsed.
  static String? extractMmsi(String context) {
    // Common form: 'vessels.urn:mrn:imo:mmsi:338234631'
    final mmsiMarker = 'mmsi:';
    final idx = context.lastIndexOf(mmsiMarker);
    if (idx == -1) return null;
    final candidate = context.substring(idx + mmsiMarker.length);
    // Must be all digits (9 chars typical, but we allow any non-empty run).
    if (candidate.isEmpty || !RegExp(r'^\d+$').hasMatch(candidate)) {
      return null;
    }
    return candidate;
  }

  /// Returns true when [context] represents the own vessel.
  ///
  /// Matches if [context] equals [selfContext], or if [context] is
  /// 'vessels.self', or if both share the same MMSI.
  static bool isSelf(String context, String? selfContext) {
    if (context == 'vessels.self') return true;
    if (selfContext == null) return false;
    if (context == selfContext) return true;
    // Compare by MMSI as a fallback.
    final mmsiCtx = extractMmsi(context);
    final mmsiSelf = extractMmsi(selfContext);
    if (mmsiCtx != null && mmsiCtx == mmsiSelf) return true;
    return false;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static VesselState _applyOwnShip(
      VesselState state, List<Map<String, dynamic>> values) {
    var own = state.aisOwnShip ?? const AisOwnShipState();
    for (final item in values) {
      final path = item['path'] as String?;
      final value = item['value'];
      if (path == null || value == null) continue;
      try {
        own = _applyOwnShipPath(own, path, value);
      } catch (_) {
        // Skip malformed values.
      }
    }
    return state.copyWith(aisOwnShip: own);
  }

  static AisOwnShipState _applyOwnShipPath(
      AisOwnShipState own, String path, dynamic value) {
    switch (path) {
      case 'navigation.position':
        final pos = _parsePosition(value);
        return pos != null ? own.copyWith(position: pos) : own;
      case 'navigation.speedOverGround':
        return own.copyWith(sog: _toDouble(value) * _msToKnots);
      case 'navigation.courseOverGroundTrue':
        return own.copyWith(cog: _toDouble(value) * _radToDeg);
      case 'navigation.headingTrue':
        return own.copyWith(heading: _toDouble(value) * _radToDeg);
      case 'navigation.state':
        return own.copyWith(navStatus: value as String?);
      case 'name':
        return own.copyWith(name: value as String?);
      case 'mmsi':
        return own.copyWith(mmsi: value.toString());
      case 'communication.callsignVhf':
        return own.copyWith(callSign: value as String?);
      case 'design.aisShipType':
        final id = _extractShipTypeId(value);
        return id != null ? own.copyWith(shipType: id) : own;
      case 'design.aisShipType.id':
        return own.copyWith(shipType: (value as num).toInt());
      default:
        return own;
    }
  }

  static VesselState _applyTarget(
    VesselState state,
    String targetId,
    String mmsi,
    List<Map<String, dynamic>> values,
  ) {
    final targets = Map<String, AisTargetState>.from(state.aisTargets);
    var target = targets[targetId] ??
        AisTargetState(
          id: targetId,
          mmsi: mmsi,
          signalSource: AisSignalSource.signalk,
          lastUpdated: DateTime.now(),
          status: AisTargetStatus.active,
        );

    for (final item in values) {
      final path = item['path'] as String?;
      final value = item['value'];
      if (path == null || value == null) continue;
      try {
        target = _applyTargetPath(target, path, value);
      } catch (_) {
        // Skip malformed values.
      }
    }

    // Always stamp the update time and mark active.
    target = target.copyWith(
      lastUpdated: DateTime.now(),
      status: AisTargetStatus.active,
    );

    targets[targetId] = target;
    return state.copyWith(aisTargets: targets);
  }

  static AisTargetState _applyTargetPath(
      AisTargetState target, String path, dynamic value) {
    switch (path) {
      case 'navigation.position':
        final pos = _parsePosition(value);
        return pos != null ? target.copyWith(position: pos) : target;
      case 'navigation.speedOverGround':
        return target.copyWith(sog: _toDouble(value) * _msToKnots);
      case 'navigation.courseOverGroundTrue':
        return target.copyWith(cog: _toDouble(value) * _radToDeg);
      case 'navigation.headingTrue':
        return target.copyWith(heading: _toDouble(value) * _radToDeg);
      case 'navigation.state':
        return target.copyWith(navStatus: value as String?);
      case 'name':
        return target.copyWith(name: value as String?);
      case 'mmsi':
        return target.copyWith(mmsi: value.toString());
      case 'communication.callsignVhf':
        return target.copyWith(callSign: value as String?);
      case 'design.aisShipType':
        final id = _extractShipTypeId(value);
        return id != null ? target.copyWith(shipType: id) : target;
      case 'design.aisShipType.id':
        return target.copyWith(shipType: (value as num).toInt());
      case 'navigation.destination.commonName':
        return target.copyWith(destination: value as String?);
      default:
        return target;
    }
  }

  // ---------------------------------------------------------------------------
  // Value helpers
  // ---------------------------------------------------------------------------

  static double _toDouble(dynamic value) => (value as num).toDouble();

  static GpsPosition? _parsePosition(dynamic value) {
    if (value is! Map<String, dynamic>) return null;
    final lat = value['latitude'];
    final lon = value['longitude'];
    if (lat == null || lon == null) return null;
    return GpsPosition(
      latitude: (lat as num).toDouble(),
      longitude: (lon as num).toDouble(),
      altitude: value['altitude'] != null
          ? (value['altitude'] as num).toDouble()
          : null,
      timestamp: DateTime.now(),
    );
  }

  /// Handles both 'design.aisShipType' (object with 'id' key) and
  /// 'design.aisShipType.id' (plain integer) forms.
  static int? _extractShipTypeId(dynamic value) {
    if (value is num) return value.toInt();
    if (value is Map<String, dynamic>) {
      final id = value['id'];
      if (id is num) return id.toInt();
    }
    return null;
  }
}
