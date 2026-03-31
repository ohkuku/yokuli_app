import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/log_entry.dart';
import '../models/vessel_state.dart';
import '../sync/sync_engine.dart';
import '../utils/id_gen.dart';
import 'vessel_provider.dart';
import 'lan_broadcast.dart';

// ---------------------------------------------------------------------------
// _JsonStore — private file-based JSON persistence helper
// ---------------------------------------------------------------------------

class _JsonStore {
  static Future<File> _file(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/yokuli_$name.json');
  }

  static Future<List<Map<String, dynamic>>> load(String name) async {
    try {
      final f = await _file(name);
      if (!await f.exists()) return [];
      final data = jsonDecode(await f.readAsString());
      return List<Map<String, dynamic>>.from(data as List);
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(
      String name, List<Map<String, dynamic>> data) async {
    try {
      (await _file(name)).writeAsString(jsonEncode(data));
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// LogNotifier
// ---------------------------------------------------------------------------

/// Append-only log provider. Entries are stored newest-first in state so that
/// [recent] is cheap (just take(100)).
class LogNotifier extends Notifier<List<LogEntry>> {
  static const String _storeName = 'log';

  @override
  List<LogEntry> build() => const [];

  // ---- Persistence --------------------------------------------------------

  Future<void> load() async {
    final rows = await _JsonStore.load(_storeName);
    // Rows are stored newest-first; restore in the same order.
    state = rows.map(LogEntry.fromJson).toList();
  }

  Future<void> save() async {
    await _JsonStore.save(
        _storeName, state.map((e) => e.toJson()).toList());
  }

  // ---- Core append --------------------------------------------------------

  Future<void> importAll(List<Map<String, dynamic>> rows) async {
    state = rows.map(LogEntry.fromJson).toList();
    await save();
  }

  /// Append a [LogEntry] and immediately persist it.
  Future<void> append(LogEntry entry) async {
    // Prepend so that state[0] is always the newest entry.
    state = [entry, ...state];
    await save();
    ref.read(lanBroadcastProvider)?.call(
        {'type': 'log_append', 'data': entry.toJson()});
  }

  // ---- Convenience log method ---------------------------------------------

  /// Build and append a [LogEntry] from the current vessel state context.
  ///
  /// The [LogContext] is automatically populated from [vesselProvider], so
  /// callers only need to supply the semantic fields.
  Future<LogEntry> log({
    required LogEntryType type,
    String? subtype,
    required String message,
    String? voyageId,
    String? sourceDeviceId,
    List<String> activeAlarmIds = const [],
    String? aisTargetId,
  }) async {
    final vessel = ref.read(vesselProvider);

    // Collect all battery voltages (keyed by battery id).
    final allBatteryVoltages = <String, double>{};
    double? firstBatteryVoltage;
    for (final entry in vessel.batteries.entries) {
      final v = entry.value.voltage;
      if (v != null) {
        allBatteryVoltages[entry.key] = v;
        firstBatteryVoltage ??= v;
      }
    }

    // Solar total input power from PowerSummaryState (if available).
    final solarPower = vessel.powerSummary?.solarInputPowerTotal;

    final context = LogContext(
      position: vessel.position,
      sog: vessel.speedOverGround,
      cog: vessel.courseOverGround,
      heading: vessel.heading,
      depth: vessel.depthBelowKeel,
      depthBelowSurface: vessel.depthBelowSurface,
      batteryVoltage: firstBatteryVoltage,
      allBatteryVoltages: allBatteryVoltages,
      solarPower: solarPower,
      trueWindSpeed: vessel.trueWindSpeed,
      trueWindDirection: vessel.trueWindDirection,
      apparentWindSpeed: vessel.apparentWindSpeed,
      apparentWindAngle: vessel.apparentWindAngle,
      activeAlarmIds: activeAlarmIds,
      aisTargetId: aisTargetId,
    );

    final entry = LogEntry(
      id: generateId(),
      type: type,
      subtype: subtype,
      timestamp: DateTime.now(),
      voyageId: voyageId,
      message: message,
      context: context,
      sourceDeviceId: sourceDeviceId,
    );

    await append(entry);
    return entry;
  }

  // ---- Accessors ----------------------------------------------------------

  /// The 100 most recent log entries (state is already newest-first), excluding deleted.
  List<LogEntry> get recent =>
      state.where((e) => !e.deleted).take(100).toList();

  /// Filter entries by voyage ID, excluding deleted.
  List<LogEntry> byVoyage(String voyageId) =>
      state.where((e) => e.voyageId == voyageId && !e.deleted).toList();

  /// Filter entries by type, excluding deleted.
  List<LogEntry> byType(LogEntryType type) =>
      state.where((e) => e.type == type && !e.deleted).toList();

  /// Soft-delete a log entry by ID: marks deleted=true and propagates.
  Future<void> delete(String id) async {
    final now = DateTime.now();
    state = state.map((e) {
      if (e.id != id) return e;
      return e.copyWith(deleted: true, updatedAt: now);
    }).toList();
    await save();
    final tombstone = state.firstWhere((e) => e.id == id, orElse: () => state.first);
    ref.read(lanBroadcastProvider)?.call(
        {'type': 'log_append', 'data': tombstone.toJson()});
  }

  /// Upsert a [LogEntry] received from a remote device (LAN sync).
  /// Uses SyncEngine LWW with full tie-break (tombstone, then src lexicographic).
  Future<void> appendRemote(Map<String, dynamic> data) async {
    try {
      final idx = state.indexWhere((e) => e.id == (data['id'] as String?));
      if (idx >= 0) {
        final existingJson = state[idx].toJson();
        final winnerJson = SyncEngine.merge(existingJson, data);
        if (identical(winnerJson, existingJson)) return;
        final updated = List<LogEntry>.from(state);
        updated[idx] = LogEntry.fromJson(winnerJson);
        state = updated;
      } else {
        state = [LogEntry.fromJson(data), ...state];
      }
      await save();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final logProvider =
    NotifierProvider<LogNotifier, List<LogEntry>>(LogNotifier.new);

/// The 100 most recent log entries.
final recentLogProvider = Provider<List<LogEntry>>(
  (ref) => ref.watch(logProvider.notifier).recent,
);
