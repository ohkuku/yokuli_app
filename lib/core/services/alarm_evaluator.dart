import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/alarm_action.dart';
import '../models/alarm_instance.dart';
import '../models/alarm_rule.dart';
import '../models/vessel_state.dart';
import '../providers/alarm_action_provider.dart';
import '../providers/alarm_instance_provider.dart';
import '../providers/alarm_rule_provider.dart';
import '../providers/device_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/vessel_provider.dart';
import '../utils/id_gen.dart';

// ---------------------------------------------------------------------------
// AlarmEvaluator
// ---------------------------------------------------------------------------

/// Watches live vessel state and evaluates all enabled [AlarmRule]s, creating
/// [AlarmInstance] entries whenever a condition is met and the relevant
/// cool-down / sustain / deduplication constraints allow.
class AlarmEvaluator {
  final Ref _ref;

  /// Tracks when a rule's condition first became continuously true.
  /// Used to implement the [AlarmCondition.sustainMs] feature.
  final Map<String, DateTime> _conditionFirstTrueAt = {};

  /// Tracks when a rule's condition first became continuously false after
  /// previously being true. Used to implement hysteresis-based auto-clear.
  final Map<String, DateTime> _conditionFirstFalseAt = {};

  ProviderSubscription<VesselState>? _vesselSub;
  Timer? _snoozeCheckTimer;

  AlarmEvaluator(this._ref);

  // ---- Lifecycle ------------------------------------------------------------

  /// Begin evaluation. Safe to call multiple times (subsequent calls are
  /// no-ops if the evaluator is already running).
  void start() {
    if (_vesselSub != null) return;

    _vesselSub = _ref.listen<VesselState>(
      vesselProvider,
      (_, state) => _evaluate(state),
      fireImmediately: false,
    );

    // Periodically expire snoozed instances so they can re-trigger if the
    // underlying condition is still met.
    _snoozeCheckTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _ref.read(alarmInstanceProvider.notifier).checkSnoozedExpired(),
    );
  }

  /// Stop evaluation and release all resources.
  void stop() {
    _vesselSub?.close();
    _vesselSub = null;
    _snoozeCheckTimer?.cancel();
    _snoozeCheckTimer = null;
    _conditionFirstTrueAt.clear();
    _conditionFirstFalseAt.clear();
  }

  // ---- Core evaluation loop ------------------------------------------------

  void _evaluate(VesselState state) {
    final rules = _ref
        .read(alarmRuleProvider)
        .where((r) => r.enabled && !r.deleted)
        .toList();

    for (final rule in rules) {
      final value = _extractMetric(
        state,
        rule.condition.metric,
        rule.condition.source,
      );

      if (value == null) {
        // No data for this metric — reset any sustain tracking and move on.
        _conditionFirstTrueAt.remove(rule.id);
        continue;
      }

      final conditionMet =
          rule.condition.operator.evaluate(value, rule.condition.threshold);

      if (conditionMet) {
        _conditionFirstFalseAt.remove(rule.id);
        _handleConditionTrue(rule, value);
      } else {
        // Condition not met — clear sustain tracking so the timer resets if
        // the condition becomes true again later.
        _conditionFirstTrueAt.remove(rule.id);
        _handleConditionFalse(rule, value);
      }
    }
  }

  // ---- Condition-true path -------------------------------------------------

  void _handleConditionTrue(AlarmRule rule, double value) {
    // 1. Deduplication: skip if an active or snoozed instance already exists.
    final instances = _ref.read(alarmInstanceProvider);
    final hasActiveOrSnoozed = instances.any((i) =>
        i.ruleId == rule.id &&
        !i.deleted &&
        (i.status == AlarmInstanceStatus.active ||
            i.status == AlarmInstanceStatus.snoozed));

    if (hasActiveOrSnoozed) return;

    // 2. Cool-down: skip if the most-recent cleared/acknowledged instance was
    //    within the cool-down window.
    final cooldownMs = rule.condition.cooldownMs;
    if (cooldownMs > 0) {
      final recent = _mostRecentSettledInstance(instances, rule.id);
      if (recent != null) {
        final elapsed =
            DateTime.now().difference(recent.updatedAt).inMilliseconds;
        if (elapsed < cooldownMs) return;
      }
    }

    // 3. Sustain: the condition must have been continuously true for at least
    //    [sustainMs] before a new instance is created.
    final sustainMs = rule.condition.sustainMs;
    if (sustainMs != null && sustainMs > 0) {
      final firstTrue =
          _conditionFirstTrueAt.putIfAbsent(rule.id, () => DateTime.now());
      final elapsed =
          DateTime.now().difference(firstTrue).inMilliseconds;
      if (elapsed < sustainMs) return;
    }

    // All guards passed — trigger.
    final device = _ref.read(deviceProvider);
    _triggerAlarm(rule, value, device.deviceId);
  }

  // ---- Condition-false / recovery path -------------------------------------

  void _handleConditionFalse(AlarmRule rule, double value) {
    // Check hysteresis: the value must have moved far enough past the threshold
    // before we consider the condition "recovered" and auto-clear.
    final hysteresis = rule.condition.hysteresis ?? 0.0;
    final recovered = rule.condition.operator.isRecovered(
      value,
      rule.condition.threshold,
      hysteresis,
    );
    if (!recovered) {
      // Value is in the hysteresis band — don't auto-clear yet.
      _conditionFirstFalseAt.remove(rule.id);
      return;
    }

    // Track when recovery first started. With sustainMs we could delay
    // auto-clear; for now we auto-clear immediately once hysteresis passes.
    _conditionFirstFalseAt.putIfAbsent(rule.id, () => DateTime.now());

    // Find active or acknowledged instances to auto-clear.
    final instances = _ref.read(alarmInstanceProvider);
    final toAutoClear = instances.where((i) =>
        i.ruleId == rule.id &&
        !i.deleted &&
        (i.status == AlarmInstanceStatus.active ||
            i.status == AlarmInstanceStatus.acknowledged));

    if (toAutoClear.isEmpty) {
      _conditionFirstFalseAt.remove(rule.id);
      return;
    }

    final deviceId = _ref.read(deviceProvider).deviceId;
    final deviceName = _ref.read(settingsProvider).deviceName;
    for (final instance in toAutoClear) {
      _autoClearInstance(instance, deviceId, deviceName);
    }
    _conditionFirstFalseAt.remove(rule.id);
  }

  Future<void> _autoClearInstance(
    AlarmInstance instance,
    String deviceId,
    String deviceName,
  ) async {
    final now = DateTime.now();
    // Delegate the state change to the notifier.
    await _ref.read(alarmInstanceProvider.notifier).autoClear(
      instance.id,
      deviceId: deviceId,
    );

    // Record the auto-clear action for audit.
    final action = AlarmAction(
      id: generateId(),
      instanceId: instance.id,
      action: AlarmActionType.autoClear,
      deviceId: deviceId,
      deviceName: deviceName,
      at: now,
      note: '条件自动恢复',
      updatedAt: now,
      deleted: false,
      scope: 'global',
      sourceDeviceId: deviceId,
      schemaVersion: 1,
    );
    await _ref.read(alarmActionProvider.notifier).append(action);
  }

  // ---- Trigger -------------------------------------------------------------

  Future<void> _triggerAlarm(AlarmRule rule, double value, String deviceId) async {
    final unit = _unitForMetric(rule.condition.metric);
    final message = '${rule.name}: ${value.toStringAsFixed(1)} $unit';

    // Delegate instance creation (and broadcast) to the notifier.
    final instance = await _ref.read(alarmInstanceProvider.notifier).trigger(
      ruleId: rule.id,
      ruleName: rule.name,
      level: rule.level,
      message: message,
      triggeredValue: value,
      deviceId: deviceId,
      cooldownMs: rule.condition.cooldownMs,
    );

    // Notifier returns null if deduplication/cooldown blocked the trigger.
    if (instance == null) return;

    // Clear sustain tracking now that the alarm has fired, so the sustain
    // window resets should the condition persist after this instance clears.
    _conditionFirstTrueAt.remove(rule.id);
  }

  // ---- Metric extraction ---------------------------------------------------

  /// Reads the current value for [metric] from [state].
  ///
  /// Returns `null` if the value is unavailable or the source is not yet
  /// supported.
  double? _extractMetric(
    VesselState state,
    String metric,
    AlarmConditionSource source,
  ) {
    switch (source) {
      case AlarmConditionSource.vesselMetric:
        return _extractVesselMetric(state, metric);

      case AlarmConditionSource.signalK:
        // TODO(signalK): Implement direct SignalK path evaluation.
        return null;
    }
  }

  double? _extractVesselMetric(VesselState state, String metric) {
    switch (metric) {
      case 'sog':
        return state.speedOverGround;
      case 'depth_keel':
        return state.depthBelowKeel;
      case 'depth_surface':
        return state.depthBelowSurface;
      case 'wind_true_speed':
        return state.trueWindSpeed;
      case 'wind_apparent_speed':
        return state.apparentWindSpeed;
      case 'battery_voltage_main':
        // Use the first battery that has a voltage reading as the "main"
        // battery proxy.  Callers can create more-specific rules against
        // named batteries once per-battery metric keys are added.
        return state.batteries.values
            .where((b) => b.voltage != null)
            .firstOrNull
            ?.voltage;
      case 'solar_power_total':
        return state.powerSummary?.solarInputPowerTotal;
      default:
        return null;
    }
  }

  // ---- Helpers -------------------------------------------------------------

  /// Returns the most-recently-settled (cleared or acknowledged) instance for
  /// [ruleId], sorted by [updatedAt] descending.
  AlarmInstance? _mostRecentSettledInstance(
    List<AlarmInstance> instances,
    String ruleId,
  ) {
    final settled = instances
        .where((i) =>
            i.ruleId == ruleId &&
            !i.deleted &&
            (i.status == AlarmInstanceStatus.cleared ||
                i.status == AlarmInstanceStatus.acknowledged))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return settled.firstOrNull;
  }

  /// Returns the display unit string for a vessel metric key.
  String _unitForMetric(String metric) {
    const units = {
      'sog': 'kn',
      'depth_keel': 'm',
      'depth_surface': 'm',
      'battery_voltage_main': 'V',
      'wind_true_speed': 'kn',
      'wind_apparent_speed': 'kn',
      'solar_power_total': 'W',
    };
    return units[metric] ?? '';
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final alarmEvaluatorProvider = Provider<AlarmEvaluator>((ref) {
  final evaluator = AlarmEvaluator(ref);
  ref.onDispose(evaluator.stop);
  return evaluator;
});
