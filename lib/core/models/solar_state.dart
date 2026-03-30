enum SolarChargerState { bulk, absorption, float, idle, fault, unknown }

enum SolarStatus { charging, idle, fault, stale, noData }

enum ChargeState { charging, discharging, neutral, unknown }

enum EnergyFlowDirection {
  solarToBattery,
  batteryToLoad,
  solarPlusBatteryToLoad,
  unknown,
}

class SolarChargeControllerState {
  final String id;
  final double? inputVoltage;
  final double? inputCurrent;
  final double? inputPower;
  final double? outputVoltage;
  final double? outputCurrent;
  final double? outputPower;
  final double? controllerTemperature;
  final SolarChargerState chargerState;
  final double? yieldTodayWh;
  final double? yieldTodayAh;
  final double? yieldTotalWh;
  final DateTime lastUpdated;
  final SolarStatus status;

  const SolarChargeControllerState({
    required this.id,
    this.inputVoltage,
    this.inputCurrent,
    this.inputPower,
    this.outputVoltage,
    this.outputCurrent,
    this.outputPower,
    this.controllerTemperature,
    required this.chargerState,
    this.yieldTodayWh,
    this.yieldTodayAh,
    this.yieldTotalWh,
    required this.lastUpdated,
    required this.status,
  });

  double? get effectiveInputPower =>
      inputPower ??
      (inputVoltage != null && inputCurrent != null
          ? inputVoltage! * inputCurrent!
          : null);

  double? get effectiveOutputPower =>
      outputPower ??
      (outputVoltage != null && outputCurrent != null
          ? outputVoltage! * outputCurrent!
          : null);

  SolarChargeControllerState copyWith({
    String? id,
    Object? inputVoltage = _sentinel,
    Object? inputCurrent = _sentinel,
    Object? inputPower = _sentinel,
    Object? outputVoltage = _sentinel,
    Object? outputCurrent = _sentinel,
    Object? outputPower = _sentinel,
    Object? controllerTemperature = _sentinel,
    SolarChargerState? chargerState,
    Object? yieldTodayWh = _sentinel,
    Object? yieldTodayAh = _sentinel,
    Object? yieldTotalWh = _sentinel,
    DateTime? lastUpdated,
    SolarStatus? status,
  }) {
    return SolarChargeControllerState(
      id: id ?? this.id,
      inputVoltage: inputVoltage == _sentinel
          ? this.inputVoltage
          : inputVoltage as double?,
      inputCurrent: inputCurrent == _sentinel
          ? this.inputCurrent
          : inputCurrent as double?,
      inputPower:
          inputPower == _sentinel ? this.inputPower : inputPower as double?,
      outputVoltage: outputVoltage == _sentinel
          ? this.outputVoltage
          : outputVoltage as double?,
      outputCurrent: outputCurrent == _sentinel
          ? this.outputCurrent
          : outputCurrent as double?,
      outputPower: outputPower == _sentinel
          ? this.outputPower
          : outputPower as double?,
      controllerTemperature: controllerTemperature == _sentinel
          ? this.controllerTemperature
          : controllerTemperature as double?,
      chargerState: chargerState ?? this.chargerState,
      yieldTodayWh: yieldTodayWh == _sentinel
          ? this.yieldTodayWh
          : yieldTodayWh as double?,
      yieldTodayAh: yieldTodayAh == _sentinel
          ? this.yieldTodayAh
          : yieldTodayAh as double?,
      yieldTotalWh: yieldTotalWh == _sentinel
          ? this.yieldTotalWh
          : yieldTotalWh as double?,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (inputVoltage != null) 'iv': inputVoltage,
        if (inputCurrent != null) 'ic': inputCurrent,
        if (inputPower != null) 'ip': inputPower,
        if (outputVoltage != null) 'ov': outputVoltage,
        if (outputCurrent != null) 'oc': outputCurrent,
        if (outputPower != null) 'op': outputPower,
        if (controllerTemperature != null) 'ct': controllerTemperature,
        'cs': chargerState.index,
        if (yieldTodayWh != null) 'ywh': yieldTodayWh,
        if (yieldTodayAh != null) 'yah': yieldTodayAh,
        if (yieldTotalWh != null) 'twh': yieldTotalWh,
        'lu': lastUpdated.toIso8601String(),
        's': status.index,
      };

  factory SolarChargeControllerState.fromJson(Map<String, dynamic> json) {
    return SolarChargeControllerState(
      id: json['id'] as String,
      inputVoltage:
          json['iv'] != null ? (json['iv'] as num).toDouble() : null,
      inputCurrent:
          json['ic'] != null ? (json['ic'] as num).toDouble() : null,
      inputPower:
          json['ip'] != null ? (json['ip'] as num).toDouble() : null,
      outputVoltage:
          json['ov'] != null ? (json['ov'] as num).toDouble() : null,
      outputCurrent:
          json['oc'] != null ? (json['oc'] as num).toDouble() : null,
      outputPower:
          json['op'] != null ? (json['op'] as num).toDouble() : null,
      controllerTemperature:
          json['ct'] != null ? (json['ct'] as num).toDouble() : null,
      chargerState: SolarChargerState.values[json['cs'] as int],
      yieldTodayWh:
          json['ywh'] != null ? (json['ywh'] as num).toDouble() : null,
      yieldTodayAh:
          json['yah'] != null ? (json['yah'] as num).toDouble() : null,
      yieldTotalWh:
          json['twh'] != null ? (json['twh'] as num).toDouble() : null,
      lastUpdated: DateTime.parse(json['lu'] as String),
      status: SolarStatus.values[json['s'] as int],
    );
  }
}

// Sentinel object used for nullable copyWith pattern
const Object _sentinel = Object();

class PowerSummaryState {
  final double? batteryVoltageMain;
  final double? batteryCurrentNet;
  final double? batterySocMain;
  final double? solarInputPowerTotal;
  final double? solarChargeCurrentTotal;
  final ChargeState estimatedChargeState;
  final EnergyFlowDirection energyFlowDirection;
  final DateTime lastUpdated;

  const PowerSummaryState({
    this.batteryVoltageMain,
    this.batteryCurrentNet,
    this.batterySocMain,
    this.solarInputPowerTotal,
    this.solarChargeCurrentTotal,
    required this.estimatedChargeState,
    required this.energyFlowDirection,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
        if (batteryVoltageMain != null) 'bv': batteryVoltageMain,
        if (batteryCurrentNet != null) 'bc': batteryCurrentNet,
        if (batterySocMain != null) 'bsoc': batterySocMain,
        if (solarInputPowerTotal != null) 'sip': solarInputPowerTotal,
        if (solarChargeCurrentTotal != null) 'scc': solarChargeCurrentTotal,
        'cs': estimatedChargeState.index,
        'ef': energyFlowDirection.index,
        'lu': lastUpdated.toIso8601String(),
      };

  factory PowerSummaryState.fromJson(Map<String, dynamic> json) {
    return PowerSummaryState(
      batteryVoltageMain:
          json['bv'] != null ? (json['bv'] as num).toDouble() : null,
      batteryCurrentNet:
          json['bc'] != null ? (json['bc'] as num).toDouble() : null,
      batterySocMain:
          json['bsoc'] != null ? (json['bsoc'] as num).toDouble() : null,
      solarInputPowerTotal:
          json['sip'] != null ? (json['sip'] as num).toDouble() : null,
      solarChargeCurrentTotal:
          json['scc'] != null ? (json['scc'] as num).toDouble() : null,
      estimatedChargeState: ChargeState.values[json['cs'] as int],
      energyFlowDirection: EnergyFlowDirection.values[json['ef'] as int],
      lastUpdated: DateTime.parse(json['lu'] as String),
    );
  }
}
