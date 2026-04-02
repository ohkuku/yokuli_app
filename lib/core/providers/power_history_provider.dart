import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/solar_state.dart';
import 'vessel_provider.dart';

/// One timestamped sample of power data.
class PowerSample {
  final DateTime time;
  final double? voltage;   // V
  final double? current;   // A (positive = charging, negative = discharging)
  final double? soc;       // 0.0–1.0
  final double? solarW;    // solar input watts
  const PowerSample({required this.time, this.voltage, this.current, this.soc, this.solarW});
}

/// Holds rolling history of power samples across all batteries + solar.
class PowerHistoryState {
  /// Map of batteryId → ordered list of samples (oldest first, max 360 entries = 1h at 10s)
  final Map<String, List<PowerSample>> batteryHistory;
  /// Summary power samples (net current, main voltage, SOC, solar)
  final List<PowerSample> summaryHistory;

  const PowerHistoryState({
    this.batteryHistory = const {},
    this.summaryHistory = const [],
  });

  static const int maxSamples = 360; // 360 × 10s = 1 hour

  PowerHistoryState addSample({
    required Map<String, PowerSample> bySensor,
    required PowerSample summary,
  }) {
    final newBatteryHistory = Map<String, List<PowerSample>>.from(
      batteryHistory.map((k, v) => MapEntry(k, List<PowerSample>.from(v))),
    );
    for (final entry in bySensor.entries) {
      final list = newBatteryHistory.putIfAbsent(entry.key, () => []);
      list.add(entry.value);
      if (list.length > maxSamples) list.removeAt(0);
    }
    final newSummary = List<PowerSample>.from(summaryHistory)..add(summary);
    if (newSummary.length > maxSamples) newSummary.removeAt(0);
    return PowerHistoryState(
      batteryHistory: newBatteryHistory,
      summaryHistory: newSummary,
    );
  }
}

class PowerHistoryNotifier extends Notifier<PowerHistoryState> {
  Timer? _timer;

  @override
  PowerHistoryState build() {
    ref.onDispose(() { _timer?.cancel(); });
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _sample());
    return const PowerHistoryState();
  }

  void _sample() {
    final vessel = ref.read(vesselProvider);
    final now = DateTime.now();
    final bySensor = <String, PowerSample>{};
    for (final entry in vessel.batteries.entries) {
      bySensor[entry.key] = PowerSample(
        time: now,
        voltage: entry.value.voltage,
        current: entry.value.current,
        soc: entry.value.stateOfCharge,
      );
    }
    final ps = vessel.powerSummary;
    final summary = PowerSample(
      time: now,
      voltage: ps?.batteryVoltageMain,
      current: ps?.batteryCurrentNet,
      soc: ps?.batterySocMain,
      solarW: ps?.solarInputPowerTotal,
    );
    state = state.addSample(bySensor: bySensor, summary: summary);
  }
}

final powerHistoryProvider =
    NotifierProvider<PowerHistoryNotifier, PowerHistoryState>(
  PowerHistoryNotifier.new,
);
