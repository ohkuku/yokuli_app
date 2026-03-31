import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Structured telemetry service — singleton.
///
/// Tracks connection health, alarm lifecycle latencies, MOB handling times,
/// and sync dedup counts.  All events are also emitted as JSON-lines to a
/// rolling log file (`yokuli_telemetry.jsonl`) for support-bundle export.
class TelemetryService {
  TelemetryService._();
  static final TelemetryService instance = TelemetryService._();

  // ---- Connection metrics ---------------------------------------------------
  int _connectionAttempts = 0;
  int _connectionSuccesses = 0;
  int _connectionFailures = 0;
  int _reconnectCount = 0;
  int _disconnectCount = 0;
  final List<int> _reconnectDurationsMs = [];

  // ---- Alarm metrics --------------------------------------------------------
  int _alarmTriggeredCount = 0;
  final Map<String, DateTime> _alarmTriggerTimes = {};
  final List<int> _ackLatenciesMs = [];

  // ---- MOB metrics ----------------------------------------------------------
  int _mobActivationCount = 0;
  DateTime? _mobActivatedAt;
  final List<int> _mobClearDurationsMs = [];

  // ---- Sync dedup metrics --------------------------------------------------
  int _syncDeduplicated = 0;

  // ---- Log file ------------------------------------------------------------
  IOSink? _logSink;
  bool _initialized = false;

  // ---- Initialization -------------------------------------------------------

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/yokuli_telemetry.jsonl');
      _logSink = file.openWrite(mode: FileMode.append);
      log('info', 'telemetry_init');
    } catch (_) {
      // Telemetry is non-critical — continue without file logging.
    }
  }

  // ---- Structured logging ---------------------------------------------------

  void log(String level, String event, [Map<String, dynamic>? fields]) {
    final entry = <String, dynamic>{
      'ts': DateTime.now().toIso8601String(),
      'level': level,
      'event': event,
      if (fields != null) ...fields,
    };
    try {
      _logSink?.writeln(jsonEncode(entry));
    } catch (_) {}
  }

  // ---- Connection event recording ------------------------------------------

  void recordConnectionAttempt() {
    _connectionAttempts++;
    log('info', 'connection_attempt',
        {'total': _connectionAttempts});
  }

  void recordConnectionSuccess(int durationMs) {
    _connectionSuccesses++;
    _reconnectDurationsMs.add(durationMs);
    if (_reconnectDurationsMs.length > 100) _reconnectDurationsMs.removeAt(0);
    log('info', 'connection_success', {'durationMs': durationMs});
  }

  void recordConnectionFailure() {
    _connectionFailures++;
    log('warn', 'connection_failure',
        {'failures': _connectionFailures});
  }

  void recordDisconnect() {
    _disconnectCount++;
    log('warn', 'disconnected', {'count': _disconnectCount});
  }

  void recordReconnectScheduled(int attempt) {
    _reconnectCount++;
    log('info', 'reconnect_scheduled',
        {'attempt': attempt, 'total': _reconnectCount});
  }

  // ---- Alarm event recording -----------------------------------------------

  void recordAlarmTriggered(String instanceId) {
    _alarmTriggeredCount++;
    _alarmTriggerTimes[instanceId] = DateTime.now();
    log('info', 'alarm_triggered',
        {'instanceId': instanceId, 'total': _alarmTriggeredCount});
  }

  void recordAlarmAcknowledged(String instanceId) {
    final triggeredAt = _alarmTriggerTimes.remove(instanceId);
    if (triggeredAt != null) {
      final latencyMs = DateTime.now().difference(triggeredAt).inMilliseconds;
      _ackLatenciesMs.add(latencyMs);
      if (_ackLatenciesMs.length > 200) _ackLatenciesMs.removeAt(0);
      log('info', 'alarm_acknowledged',
          {'instanceId': instanceId, 'latencyMs': latencyMs});
    } else {
      log('info', 'alarm_acknowledged', {'instanceId': instanceId});
    }
  }

  void recordAlarmCleared(String instanceId, {bool auto = false}) {
    _alarmTriggerTimes.remove(instanceId);
    log('info', auto ? 'alarm_auto_cleared' : 'alarm_cleared',
        {'instanceId': instanceId});
  }

  // ---- MOB event recording -------------------------------------------------

  void recordMobActivated() {
    _mobActivationCount++;
    _mobActivatedAt = DateTime.now();
    log('warn', 'mob_activated', {'count': _mobActivationCount});
  }

  void recordMobCleared() {
    final activatedAt = _mobActivatedAt;
    if (activatedAt != null) {
      final durationMs =
          DateTime.now().difference(activatedAt).inMilliseconds;
      _mobClearDurationsMs.add(durationMs);
      if (_mobClearDurationsMs.length > 50) _mobClearDurationsMs.removeAt(0);
      log('info', 'mob_cleared', {'durationMs': durationMs});
    } else {
      log('info', 'mob_cleared');
    }
    _mobActivatedAt = null;
  }

  // ---- Sync dedup recording ------------------------------------------------

  void recordSyncDeduplicated() {
    _syncDeduplicated++;
    log('debug', 'sync_deduplicated', {'total': _syncDeduplicated});
  }

  // ---- Snapshot & export ---------------------------------------------------

  Map<String, dynamic> snapshot() {
    int _avgMs(List<int> list) =>
        list.isEmpty ? 0 : list.reduce((a, b) => a + b) ~/ list.length;

    return {
      'generatedAt': DateTime.now().toIso8601String(),
      'connections': {
        'attempts': _connectionAttempts,
        'successes': _connectionSuccesses,
        'failures': _connectionFailures,
        'disconnects': _disconnectCount,
        'reconnects': _reconnectCount,
        'avgConnectMs': _avgMs(_reconnectDurationsMs),
      },
      'alarms': {
        'triggered': _alarmTriggeredCount,
        'acknowledged': _ackLatenciesMs.length,
        'avgAckLatencyMs': _avgMs(_ackLatenciesMs),
        'p95AckLatencyMs': _p95(_ackLatenciesMs),
      },
      'mob': {
        'activations': _mobActivationCount,
        'avgClearDurationMs': _avgMs(_mobClearDurationsMs),
      },
      'sync': {
        'deduplicated': _syncDeduplicated,
      },
    };
  }

  /// Writes a support bundle JSON string (metrics + log path).
  Future<String> exportSupportBundle() async {
    final bundle = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'metrics': snapshot(),
    };
    try {
      final dir = await getApplicationDocumentsDirectory();
      final out = File('${dir.path}/yokuli_support_bundle.json');
      await out.writeAsString(jsonEncode(bundle));
      log('info', 'support_bundle_exported', {'path': out.path});
      return out.path;
    } catch (e) {
      return jsonEncode(bundle);
    }
  }

  Future<void> dispose() async {
    await _logSink?.flush();
    await _logSink?.close();
    _logSink = null;
  }

  // ---- Helpers -------------------------------------------------------------

  static int _p95(List<int> list) {
    if (list.isEmpty) return 0;
    final sorted = List<int>.from(list)..sort();
    final idx = ((sorted.length - 1) * 0.95).round();
    return sorted[idx];
  }
}
