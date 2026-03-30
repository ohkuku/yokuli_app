import '../../models/vessel_state.dart';
import '../../models/solar_state.dart';
import 'signalk_path_aliases.dart';

/// Parses Signal K delta values for electrical paths (batteries and solar
/// charge controllers) and applies them to [VesselState].
///
/// Keeping power parsing in its own file makes it easy to unit-test in
/// isolation and keeps [SignalKParser] focused on navigation/environment data.
class SignalKPowerParser {
  SignalKPowerParser._();

  // Voltage thresholds for BatteryStatus classification (12 V lead-acid).
  static const _batteryWarnVoltage = 12.0;
  static const _batteryCriticalVoltage = 11.5;

  // Threshold for "solar is charging" determination.
  static const _solarChargingCurrentThreshold = 0.1;

  // ---------------------------------------------------------------------------
  // Battery parsing
  // ---------------------------------------------------------------------------

  /// Applies a single Signal K delta value for a battery path.
  ///
  /// Expected path format: 'electrical.batteries.<id>.<field>'
  /// Returns the updated [VesselState], or the same state if the path is not
  /// recognized.
  static VesselState applyBatteryPath(
      VesselState state, String path, dynamic value) {
    try {
      final extracted = SignalKPathAliases.extractBattery(path);
      if (extracted == null) return state;

      final parts = path.split('.');
      if (parts.length < 4) return state;

      final batteryId = parts[2];
      final field = parts.sublist(3).join('.');

      final batteries = Map<String, BatteryState>.from(state.batteries);
      final existing = batteries[batteryId] ??
          BatteryState(
            id: batteryId,
            name: _prettifyId(batteryId),
            lastUpdated: DateTime.now(),
            status: BatteryStatus.noData,
          );

      BatteryState updated;
      switch (field) {
        case 'voltage':
          final v = _toDouble(value);
          updated = existing.copyWith(
            voltage: v,
            lastUpdated: DateTime.now(),
            status: _batteryStatusFromVoltage(v),
          );
        case 'current':
          updated = existing.copyWith(
            current: _toDouble(value),
            lastUpdated: DateTime.now(),
          );
        case 'capacity.stateOfCharge':
          updated = existing.copyWith(
            stateOfCharge: _toDouble(value),
            lastUpdated: DateTime.now(),
          );
        case 'temperature':
          updated = existing.copyWith(
            temperature: _toDouble(value) - 273.15, // Kelvin -> Celsius
            lastUpdated: DateTime.now(),
          );
        default:
          return state;
      }

      batteries[batteryId] = updated;
      return state.copyWith(batteries: batteries);
    } catch (_) {
      return state;
    }
  }

  // ---------------------------------------------------------------------------
  // Solar parsing
  // ---------------------------------------------------------------------------

  /// Applies a single Signal K delta value for a solar charge controller path.
  ///
  /// Handles both canonical paths and known aliases (via [SignalKPathAliases]).
  /// Expected path format: 'electrical.solar.<id>.<field>'
  /// Returns the updated [VesselState], or the same state if not recognized.
  static VesselState applySolarPath(
      VesselState state, String path, dynamic value) {
    try {
      final extracted = SignalKPathAliases.extractSolar(path);
      if (extracted == null) return state;

      final controllerId = extracted.id;
      // Use the canonical path to determine the field.
      final canonicalPath = extracted.canonical;
      final prefix = 'electrical.solar.$controllerId.';
      if (!canonicalPath.startsWith(prefix)) return state;
      final canonicalField = canonicalPath.substring(prefix.length);

      final solar =
          Map<String, SolarChargeControllerState>.from(state.solar);
      final existing = solar[controllerId] ??
          SolarChargeControllerState(
            id: controllerId,
            chargerState: SolarChargerState.unknown,
            lastUpdated: DateTime.now(),
            status: SolarStatus.noData,
          );

      SolarChargeControllerState updated;
      switch (canonicalField) {
        case 'inputVoltage':
          updated = existing.copyWith(
            inputVoltage: _toDouble(value),
            lastUpdated: DateTime.now(),
          );
        case 'inputCurrent':
          updated = existing.copyWith(
            inputCurrent: _toDouble(value),
            lastUpdated: DateTime.now(),
          );
        case 'inputPower':
          updated = existing.copyWith(
            inputPower: _toDouble(value),
            lastUpdated: DateTime.now(),
          );
        case 'outputVoltage':
          updated = existing.copyWith(
            outputVoltage: _toDouble(value),
            lastUpdated: DateTime.now(),
          );
        case 'outputCurrent':
          final oc = _toDouble(value);
          updated = existing.copyWith(
            outputCurrent: oc,
            lastUpdated: DateTime.now(),
            status: _solarStatusFromCurrent(oc),
          );
        case 'outputPower':
          updated = existing.copyWith(
            outputPower: _toDouble(value),
            lastUpdated: DateTime.now(),
          );
        case 'controllerTemperature':
          updated = existing.copyWith(
            controllerTemperature: _toDouble(value) - 273.15, // K -> °C
            lastUpdated: DateTime.now(),
          );
        case 'chargerState':
          updated = existing.copyWith(
            chargerState: _parseChargerState(value),
            lastUpdated: DateTime.now(),
          );
        case 'yieldTodayWh':
          // Some servers send yieldToday as an object {value: <Wh>}; others
          // send it as a plain numeric.
          final wh = _extractYieldWh(value);
          if (wh == null) return state;
          updated = existing.copyWith(
            yieldTodayWh: wh,
            lastUpdated: DateTime.now(),
          );
        case 'yieldTodayAh':
          updated = existing.copyWith(
            yieldTodayAh: _toDouble(value),
            lastUpdated: DateTime.now(),
          );
        case 'yieldTotalWh':
          updated = existing.copyWith(
            yieldTotalWh: _toDouble(value),
            lastUpdated: DateTime.now(),
          );
        default:
          return state;
      }

      solar[controllerId] = updated;
      return state.copyWith(solar: solar);
    } catch (_) {
      return state;
    }
  }

  // ---------------------------------------------------------------------------
  // Power summary
  // ---------------------------------------------------------------------------

  /// Builds a [PowerSummaryState] by aggregating all battery and solar data.
  ///
  /// Selects the "main" battery by preferring an entry whose id contains
  /// 'house' (case-insensitive); if none found, selects the one with the
  /// highest voltage.
  static PowerSummaryState buildSummary(
    Map<String, BatteryState> batteries,
    Map<String, SolarChargeControllerState> solar,
  ) {
    // --- Find the main battery ---
    BatteryState? main;
    for (final b in batteries.values) {
      if (b.id.toLowerCase().contains('house')) {
        main = b;
        break;
      }
    }
    if (main == null && batteries.isNotEmpty) {
      // Fall back to the battery with the highest known voltage.
      for (final b in batteries.values) {
        if (main == null) {
          main = b;
        } else if ((b.voltage ?? 0) > (main.voltage ?? 0)) {
          main = b;
        }
      }
    }

    // --- Aggregate battery current ---
    double? batteryCurrentNet;
    for (final b in batteries.values) {
      if (b.current != null) {
        batteryCurrentNet = (batteryCurrentNet ?? 0) + b.current!;
      }
    }

    // --- Aggregate solar ---
    double? solarInputPowerTotal;
    double? solarChargeCurrentTotal;
    for (final s in solar.values) {
      final p = s.effectiveInputPower;
      if (p != null) {
        solarInputPowerTotal = (solarInputPowerTotal ?? 0) + p;
      }
      if (s.outputCurrent != null) {
        solarChargeCurrentTotal =
            (solarChargeCurrentTotal ?? 0) + s.outputCurrent!;
      }
    }

    // --- Determine charge state ---
    ChargeState chargeState;
    if ((solarChargeCurrentTotal ?? 0) > 0.5) {
      chargeState = ChargeState.charging;
    } else if ((batteryCurrentNet ?? 0) < -0.5) {
      chargeState = ChargeState.discharging;
    } else {
      chargeState = ChargeState.neutral;
    }

    // --- Determine energy flow direction ---
    final solarActive = (solarChargeCurrentTotal ?? 0) > 0.5;
    final batteryDischarging = (batteryCurrentNet ?? 0) < -0.5;
    EnergyFlowDirection flowDir;
    if (solarActive && batteryDischarging) {
      flowDir = EnergyFlowDirection.solarPlusBatteryToLoad;
    } else if (solarActive) {
      flowDir = EnergyFlowDirection.solarToBattery;
    } else if (batteryDischarging) {
      flowDir = EnergyFlowDirection.batteryToLoad;
    } else {
      flowDir = EnergyFlowDirection.unknown;
    }

    return PowerSummaryState(
      batteryVoltageMain: main?.voltage,
      batteryCurrentNet: batteryCurrentNet,
      batterySocMain: main?.stateOfCharge,
      solarInputPowerTotal: solarInputPowerTotal,
      solarChargeCurrentTotal: solarChargeCurrentTotal,
      estimatedChargeState: chargeState,
      energyFlowDirection: flowDir,
      lastUpdated: DateTime.now(),
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static double _toDouble(dynamic value) => (value as num).toDouble();

  static String _prettifyId(String id) {
    if (id.isEmpty) return id;
    return id[0].toUpperCase() + id.substring(1);
  }

  static BatteryStatus _batteryStatusFromVoltage(double voltage) {
    if (voltage < _batteryCriticalVoltage) return BatteryStatus.critical;
    if (voltage < _batteryWarnVoltage) return BatteryStatus.warning;
    return BatteryStatus.normal;
  }

  static SolarStatus _solarStatusFromCurrent(double outputCurrent) {
    return outputCurrent > _solarChargingCurrentThreshold
        ? SolarStatus.charging
        : SolarStatus.idle;
  }

  static SolarChargerState _parseChargerState(dynamic value) {
    if (value is! String) return SolarChargerState.unknown;
    switch (value) {
      case 'Bulk':
      case 'bulk':
        return SolarChargerState.bulk;
      case 'Absorption':
      case 'absorption':
        return SolarChargerState.absorption;
      case 'Float':
      case 'float':
        return SolarChargerState.float;
      case 'Off':
      case 'off':
      case 'Idle':
      case 'idle':
        return SolarChargerState.idle;
      case 'Fault':
      case 'fault':
        return SolarChargerState.fault;
      default:
        return SolarChargerState.unknown;
    }
  }

  /// Extracts a Wh double from a value that may be either a plain [num] or a
  /// Map with a 'value' key (as produced by some SK plugin implementations).
  static double? _extractYieldWh(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is Map<String, dynamic>) {
      final inner = value['value'];
      if (inner is num) return inner.toDouble();
    }
    return null;
  }
}
