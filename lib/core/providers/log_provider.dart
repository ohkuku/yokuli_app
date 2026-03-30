import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/log_entry.dart';
import '../models/vessel_state.dart';
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

    // Pull the first battery's voltage as a summary value (if available).
    double? batteryVoltage;
    for (final b in vessel.batteries.values) {
      if (b.voltage != null) {
        batteryVoltage = b.voltage;
        break;
      }
    }

    // Attempt to read solar total power from the extended VesselState spec.
    double? solarPower;
    try {
      final dynamic v = vessel;
      final dynamic raw = (v as dynamic).powerSummary;
      if (raw != null) {
        final dynamic sp = (raw as dynamic).solarInputPowerTotal;
        if (sp is double) solarPower = sp;
      }
    } catch (_) {}

    final context = LogContext(
      position: vessel.position,
      sog: vessel.speedOverGround,
      cog: vessel.courseOverGround,
      heading: vessel.heading,
      depth: vessel.depthBelowKeel,
      batteryVoltage: batteryVoltage,
      solarPower: solarPower,
      activeAlarmIds: activeAlarmIds,
      aisTargetId: aisTargetId,
    );

    final entry = LogEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
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

  /// The 100 most recent log entries (state is already newest-first).
  List<LogEntry> get recent => state.take(100).toList();

  /// Filter entries by voyage ID.
  List<LogEntry> byVoyage(String voyageId) =>
      state.where((e) => e.voyageId == voyageId).toList();

  /// Filter entries by type.
  List<LogEntry> byType(LogEntryType type) =>
      state.where((e) => e.type == type).toList();

  /// Upsert a [LogEntry] received from a remote device (LAN sync).
  /// If an entry with the same ID already exists it is ignored (idempotent).
  Future<void> appendRemote(Map<String, dynamic> data) async {
    try {
      final entry = LogEntry.fromJson(data);
      if (state.any((e) => e.id == entry.id)) return;
      state = [entry, ...state];
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
