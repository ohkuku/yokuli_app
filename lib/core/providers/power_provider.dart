import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/solar_state.dart';
import '../models/vessel_state.dart';
import 'vessel_provider.dart';

// ---------------------------------------------------------------------------
// PowerState
// ---------------------------------------------------------------------------

class PowerState {
  final Map<String, BatteryState> batteries;
  final Map<String, SolarChargeControllerState> solar;
  final PowerSummaryState summary;

  const PowerState({
    required this.batteries,
    required this.solar,
    required this.summary,
  });
}

// ---------------------------------------------------------------------------
// Helper: derive PowerSummaryState from live batteries + solar maps
// ---------------------------------------------------------------------------

PowerSummaryState _computeSummary(
  Map<String, BatteryState> batteries,
  Map<String, SolarChargeControllerState> solar,
) {
  // --- Main battery voltage: prefer 'house', otherwise highest voltage ---
  BatteryState? mainBattery;
  if (batteries.containsKey('house')) {
    mainBattery = batteries['house'];
  } else {
    for (final b in batteries.values) {
      if (b.voltage != null) {
        if (mainBattery == null ||
            (b.voltage ?? 0) > (mainBattery.voltage ?? 0)) {
          mainBattery = b;
        }
      }
    }
  }

  final double? batteryVoltageMain = mainBattery?.voltage;
  final double? batterySocMain = mainBattery?.stateOfCharge;

  // --- Net battery current: sum of all battery currents ---
  double? batteryCurrentNet;
  for (final b in batteries.values) {
    if (b.current != null) {
      batteryCurrentNet = (batteryCurrentNet ?? 0.0) + b.current!;
    }
  }

  // --- Solar totals ---
  double? solarInputPowerTotal;
  double? solarChargeCurrentTotal;
  for (final s in solar.values) {
    final ip = s.effectiveInputPower;
    if (ip != null) {
      solarInputPowerTotal = (solarInputPowerTotal ?? 0.0) + ip;
    }
    if (s.outputCurrent != null) {
      solarChargeCurrentTotal =
          (solarChargeCurrentTotal ?? 0.0) + s.outputCurrent!;
    }
  }

  // --- Estimated charge state ---
  final ChargeState estimatedChargeState;
  if ((solarChargeCurrentTotal ?? 0.0) > 0.5) {
    estimatedChargeState = ChargeState.charging;
  } else if ((batteryCurrentNet ?? 0.0) < -0.5) {
    estimatedChargeState = ChargeState.discharging;
  } else {
    estimatedChargeState = ChargeState.neutral;
  }

  // --- Energy flow direction ---
  final EnergyFlowDirection energyFlowDirection;
  final bool hasSolar = (solarInputPowerTotal ?? 0.0) > 0;
  if (hasSolar && estimatedChargeState == ChargeState.charging) {
    energyFlowDirection = EnergyFlowDirection.solarToBattery;
  } else if (!hasSolar && estimatedChargeState == ChargeState.discharging) {
    energyFlowDirection = EnergyFlowDirection.batteryToLoad;
  } else if (hasSolar && estimatedChargeState == ChargeState.discharging) {
    energyFlowDirection = EnergyFlowDirection.solarPlusBatteryToLoad;
  } else {
    energyFlowDirection = EnergyFlowDirection.unknown;
  }

  return PowerSummaryState(
    batteryVoltageMain: batteryVoltageMain,
    batteryCurrentNet: batteryCurrentNet,
    batterySocMain: batterySocMain,
    solarInputPowerTotal: solarInputPowerTotal,
    solarChargeCurrentTotal: solarChargeCurrentTotal,
    estimatedChargeState: estimatedChargeState,
    energyFlowDirection: energyFlowDirection,
    lastUpdated: DateTime.now(),
  );
}

// ---------------------------------------------------------------------------
// powerProvider
// ---------------------------------------------------------------------------

/// Derives the full power picture from vesselProvider. No storage needed.
final powerProvider = Provider<PowerState>((ref) {
  final vessel = ref.watch(vesselProvider);

  // The full VesselState spec includes solar and powerSummary fields.
  // Read them via dynamic access when the model exposes them; fall back to
  // empty maps so the provider compiles against the current model shape.
  final batteries = vessel.batteries;

  // ignore: avoid_dynamic_calls
  final Map<String, SolarChargeControllerState> solar = () {
    try {
      // When VesselState gains a `solar` field this cast will succeed.
      final dynamic v = vessel;
      final dynamic raw = (v as dynamic).solar;
      if (raw is Map<String, SolarChargeControllerState>) return raw;
      if (raw is Map) {
        return raw.cast<String, SolarChargeControllerState>();
      }
    } catch (_) {}
    return <String, SolarChargeControllerState>{};
  }();

  final summary = _computeSummary(batteries, solar);

  return PowerState(
    batteries: batteries,
    solar: solar,
    summary: summary,
  );
});

// ---------------------------------------------------------------------------
// staleBatteriesProvider — batteries not updated in the last 15 seconds
// ---------------------------------------------------------------------------

final staleBatteriesProvider = Provider<Set<String>>((ref) {
  final batteries = ref.watch(vesselProvider).batteries;
  final now = DateTime.now();
  return batteries.entries
      .where((e) {
        // BatteryState in the current model does not carry lastUpdated;
        // when the model is updated (per spec) we use e.value.lastUpdated.
        // Until then we guard with a try/catch and mark nothing as stale.
        try {
          final dynamic b = e.value;
          final dynamic lu = (b as dynamic).lastUpdated;
          if (lu is DateTime) {
            return now.difference(lu).inSeconds > 15;
          }
        } catch (_) {}
        return false;
      })
      .map((e) => e.key)
      .toSet();
});
