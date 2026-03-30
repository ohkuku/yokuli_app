import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ais_state.dart';
import '../models/vessel_state.dart';
import 'vessel_provider.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const double _defaultCpaThresholdNm = 1.0;
const double _defaultTcpaThresholdMin = 30.0;

/// Age thresholds for AIS target staleness
const int _staleAgeSeconds = 60;
const int _lostAgeSeconds = 300;

// ---------------------------------------------------------------------------
// AisState
// ---------------------------------------------------------------------------

class AisState {
  /// Active + stale targets, sorted by relativeDistanceNm ascending.
  /// Lost targets are excluded.
  final List<AisTargetState> targets;

  /// All targets including lost ones.
  final List<AisTargetState> allTargets;

  /// Own-ship AIS data (may be null if not available).
  final AisOwnShipState? ownShip;

  /// Targets where CPA < [cpaThresholdNm] AND 0 < TCPA < [tcpaThresholdMin].
  final List<AisTargetState> riskTargets;

  final double cpaThresholdNm;
  final double tcpaThresholdMin;

  const AisState({
    required this.targets,
    required this.allTargets,
    required this.ownShip,
    required this.riskTargets,
    this.cpaThresholdNm = _defaultCpaThresholdNm,
    this.tcpaThresholdMin = _defaultTcpaThresholdMin,
  });
}

// ---------------------------------------------------------------------------
// CPA / TCPA calculation
// ---------------------------------------------------------------------------

/// Result of a CPA/TCPA computation.
class _CpaTcpa {
  final double cpaNm;
  final double tcpaMinutes; // negative means already past CPA
  const _CpaTcpa(this.cpaNm, this.tcpaMinutes);
}

/// Compute CPA and TCPA given own-ship and target navigation data.
///
/// All positions in decimal degrees. SOG in knots, COG in degrees true.
/// Returns CPA in nautical miles and TCPA in minutes.
_CpaTcpa _computeCpaTcpa({
  required double ownLat,
  required double ownLon,
  required double ownSog,
  required double ownCog,
  required double tgtLat,
  required double tgtLon,
  required double tgtSog,
  required double tgtCog,
}) {
  // Convert positions to local Cartesian (NM)
  final lat0 = ownLat * math.pi / 180.0;
  final dx = (tgtLon - ownLon) * math.cos(lat0) * 60.0; // NM
  final dy = (tgtLat - ownLat) * 60.0; // NM

  // Current range
  final currentRange = math.sqrt(dx * dx + dy * dy);

  // Velocity vectors (knots, i.e. NM/hr)
  final ovx = ownSog * math.sin(ownCog * math.pi / 180.0);
  final ovy = ownSog * math.cos(ownCog * math.pi / 180.0);
  final tvx = tgtSog * math.sin(tgtCog * math.pi / 180.0);
  final tvy = tgtSog * math.cos(tgtCog * math.pi / 180.0);

  // Relative velocity (target relative to own)
  final rvx = tvx - ovx;
  final rvy = tvy - ovy;

  final rvSq = rvx * rvx + rvy * rvy;

  if (rvSq < 0.001) {
    // Vessels are on the same course/speed — CPA equals current range,
    // TCPA is effectively infinity (use a large positive sentinel).
    return _CpaTcpa(currentRange, double.infinity);
  }

  // TCPA in hours
  final tcpaHours = -(dx * rvx + dy * rvy) / rvSq;

  // CPA in NM
  final cpaX = dx + rvx * tcpaHours;
  final cpaY = dy + rvy * tcpaHours;
  final cpaNm = math.sqrt(cpaX * cpaX + cpaY * cpaY);

  // Convert TCPA to minutes
  final tcpaMinutes = tcpaHours * 60.0;

  return _CpaTcpa(cpaNm, tcpaMinutes);
}

// ---------------------------------------------------------------------------
// Staleness helper
// ---------------------------------------------------------------------------

AisTargetStatus _ageToStatus(int ageSec) {
  if (ageSec >= _lostAgeSeconds) return AisTargetStatus.lost;
  if (ageSec >= _staleAgeSeconds) return AisTargetStatus.stale;
  return AisTargetStatus.active;
}

// ---------------------------------------------------------------------------
// aisProvider
// ---------------------------------------------------------------------------

final aisProvider = Provider<AisState>((ref) {
  final vessel = ref.watch(vesselProvider);

  // Pull AIS data from the vessel state.
  // The full spec adds aisTargets and aisOwnShip to VesselState; we access
  // them defensively so the provider compiles against the current model.
  final Map<String, AisTargetState> rawTargets = () {
    try {
      final dynamic v = vessel;
      final dynamic raw = (v as dynamic).aisTargets;
      if (raw is Map<String, AisTargetState>) return raw;
      if (raw is Map) return raw.cast<String, AisTargetState>();
    } catch (_) {}
    return <String, AisTargetState>{};
  }();

  final AisOwnShipState? ownShip = () {
    try {
      final dynamic v = vessel;
      return (v as dynamic).aisOwnShip as AisOwnShipState?;
    } catch (_) {}
    return null;
  }();

  final now = DateTime.now();

  // Own-ship position/motion used for CPA calculations (prefer aisOwnShip,
  // fall back to main vessel GPS/SOG/COG).
  final double? ownLat =
      ownShip?.position?.latitude ?? vessel.position?.latitude;
  final double? ownLon =
      ownShip?.position?.longitude ?? vessel.position?.longitude;
  final double ownSog = ownShip?.sog ?? vessel.speedOverGround ?? 0.0;
  final double ownCog = ownShip?.cog ?? vessel.courseOverGround ?? 0.0;

  // Filter own ship MMSI from targets (vessel may hear its own transponder).
  final ownMmsi = ownShip?.mmsi;

  // Process each raw target: update status and compute CPA/TCPA/bearing.
  final List<AisTargetState> processed = rawTargets.values
      .where((t) => ownMmsi == null || t.mmsi != ownMmsi)
      .map((t) {
    final ageSec = now.difference(t.lastUpdated).inSeconds;
    final status = _ageToStatus(ageSec);

    // CPA/TCPA — only meaningful when we have own and target position/motion.
    double? cpaNm = t.closestPointNm;
    double? tcpaMin = t.tcpaMinutes;
    double? relBearingDeg = t.relativeBearingDeg;
    double? relDistNm = t.relativeDistanceNm;

    if (ownLat != null &&
        ownLon != null &&
        t.position != null &&
        t.sog != null &&
        t.cog != null) {
      final result = _computeCpaTcpa(
        ownLat: ownLat,
        ownLon: ownLon,
        ownSog: ownSog,
        ownCog: ownCog,
        tgtLat: t.position!.latitude,
        tgtLon: t.position!.longitude,
        tgtSog: t.sog!,
        tgtCog: t.cog!,
      );

      cpaNm = result.cpaNm;
      tcpaMin =
          result.tcpaMinutes.isInfinite ? null : result.tcpaMinutes;

      // Relative distance and bearing from own to target
      final dLat = (t.position!.latitude - ownLat) * 60.0; // NM
      final dLon = (t.position!.longitude - ownLon) *
          math.cos(ownLat * math.pi / 180.0) *
          60.0;
      relDistNm = math.sqrt(dLat * dLat + dLon * dLon);

      // Bearing own -> target (degrees true)
      final bearingRad = math.atan2(dLon, dLat);
      relBearingDeg = (bearingRad * 180.0 / math.pi + 360.0) % 360.0;
    }

    return t.copyWith(
      status: status,
      closestPointNm: cpaNm,
      tcpaMinutes: tcpaMin,
      relativeBearingDeg: relBearingDeg,
      relativeDistanceNm: relDistNm,
    );
  }).toList();

  // allTargets: every processed target (preserves lost)
  final allTargets = List<AisTargetState>.unmodifiable(processed);

  // targets: exclude lost, sort by relativeDistanceNm ascending
  final visibleTargets = processed
      .where((t) => t.status != AisTargetStatus.lost)
      .toList()
    ..sort((a, b) {
      final da = a.relativeDistanceNm ?? double.infinity;
      final db = b.relativeDistanceNm ?? double.infinity;
      return da.compareTo(db);
    });

  // riskTargets: CPA < threshold AND TCPA in (0, threshold]
  final riskTargets = visibleTargets.where((t) {
    final cpa = t.closestPointNm;
    final tcpa = t.tcpaMinutes;
    if (cpa == null || tcpa == null) return false;
    return cpa < _defaultCpaThresholdNm &&
        tcpa > 0 &&
        tcpa < _defaultTcpaThresholdMin;
  }).toList();

  return AisState(
    targets: visibleTargets,
    allTargets: allTargets,
    ownShip: ownShip,
    riskTargets: riskTargets,
    cpaThresholdNm: _defaultCpaThresholdNm,
    tcpaThresholdMin: _defaultTcpaThresholdMin,
  );
});
