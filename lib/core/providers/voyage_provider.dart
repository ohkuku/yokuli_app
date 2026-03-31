import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/log_entry.dart';
import '../models/vessel_state.dart';
import '../models/voyage.dart';
import '../sync/sync_engine.dart';
import '../utils/id_gen.dart';
import 'device_provider.dart';
import 'log_provider.dart';
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
// VoyageState
// ---------------------------------------------------------------------------

class VoyageState {
  /// The currently active voyage, or null if no voyage is in progress.
  final VoyageSession? active;

  /// Completed voyages, sorted most-recent first.
  final List<VoyageSession> history;

  const VoyageState({
    this.active,
    this.history = const [],
  });
}

// ---------------------------------------------------------------------------
// VoyageNotifier
// ---------------------------------------------------------------------------

class VoyageNotifier extends Notifier<VoyageState> {
  static const String _storeName = 'voyages';

  @override
  VoyageState build() => const VoyageState();

  // ---- Persistence --------------------------------------------------------

  Future<void> load() async {
    final rows = await _JsonStore.load(_storeName);
    final all = rows.map(VoyageSession.fromJson).toList();

    VoyageSession? active;
    final List<VoyageSession> history = [];

    for (final s in all) {
      if (s.isActive && !s.deleted) {
        // In the unlikely case of multiple active sessions (e.g. crash),
        // keep only the most recent one and close the others.
        if (active == null ||
            s.startTime.isAfter(active.startTime)) {
          if (active != null) history.add(active);
          active = s;
        } else {
          history.add(s);
        }
      } else {
        history.add(s);
      }
    }

    // Sort history most-recent first
    history.sort((a, b) => b.startTime.compareTo(a.startTime));

    state = VoyageState(active: active, history: history);
  }

  Future<void> save() async {
    final all = <VoyageSession>[
      if (state.active != null) state.active!,
      ...state.history,
    ];
    await _JsonStore.save(
        _storeName, all.map((s) => s.toJson()).toList());
  }

  Future<void> importAll(List<Map<String, dynamic>> rows) async {
    final all = rows.map(VoyageSession.fromJson).toList();
    VoyageSession? active;
    final history = <VoyageSession>[];
    for (final s in all) {
      if (s.isActive && active == null) { active = s; }
      else { history.add(s); }
    }
    state = VoyageState(active: active, history: history);
    await save();
  }

  // ---- Actions ------------------------------------------------------------

  /// Start a new voyage. Ends any currently active voyage first.
  Future<void> startVoyage(
    VoyageSource source, {
    GpsPosition? position,
  }) async {
    final now = DateTime.now();

    // End any existing active voyage
    if (state.active != null) {
      await endVoyage(position: position);
    }

    final deviceId = ref.read(deviceProvider).deviceId;
    final session = VoyageSession(
      id: generateId(),
      startTime: now,
      startPosition: position,
      status: VoyageStatus.active,
      source: source,
      updatedAt: now,
      sourceDeviceId: deviceId,
    );

    state = VoyageState(
      active: session,
      history: state.history,
    );
    await save();
    ref.read(lanBroadcastProvider)?.call(
        {'type': 'voyage_upsert', 'data': session.toJson()});
    await ref.read(logProvider.notifier).log(
          type: LogEntryType.navigation,
          subtype: 'voyage_start',
          message: '航行开始',
          voyageId: session.id,
        );
  }

  /// End the currently active voyage.
  Future<void> endVoyage({GpsPosition? position}) async {
    final current = state.active;
    if (current == null) return;

    final now = DateTime.now();
    final ended = current.copyWith(
      endTime: now,
      endPosition: position,
      status: VoyageStatus.ended,
      updatedAt: now,
    );

    final newHistory = [ended, ...state.history];

    state = VoyageState(active: null, history: newHistory);
    await save();
    ref.read(lanBroadcastProvider)?.call(
        {'type': 'voyage_upsert', 'data': ended.toJson()});
    await ref.read(logProvider.notifier).log(
          type: LogEntryType.navigation,
          subtype: 'voyage_end',
          message: '航行结束',
          voyageId: ended.id,
        );
  }

  // ---- Delete -------------------------------------------------------------

  /// Soft-delete a voyage by ID: marks deleted=true and propagates tombstone.
  Future<void> delete(String id) async {
    final now = DateTime.now();
    VoyageSession? tombstone;
    if (state.active?.id == id) {
      tombstone = state.active!.copyWith(deleted: true, updatedAt: now);
      state = VoyageState(active: null, history: [...state.history, tombstone]);
    } else {
      final idx = state.history.indexWhere((v) => v.id == id);
      if (idx < 0) return;
      final updated = List<VoyageSession>.from(state.history);
      tombstone = updated[idx].copyWith(deleted: true, updatedAt: now);
      updated[idx] = tombstone;
      state = VoyageState(active: state.active, history: updated);
    }
    await save();
    ref.read(lanBroadcastProvider)?.call(
        {'type': 'voyage_upsert', 'data': tombstone.toJson()});
  }

  // ---- Edit metadata ------------------------------------------------------

  /// Set a custom name/alias for a voyage.
  Future<void> rename(String id, String name) async {
    final trimmed = name.trim();
    final now = DateTime.now();
    if (state.active?.id == id) {
      state = VoyageState(
        active: state.active!.copyWith(name: trimmed.isEmpty ? null : trimmed, updatedAt: now),
        history: state.history,
      );
    } else {
      final idx = state.history.indexWhere((s) => s.id == id);
      if (idx < 0) return;
      final updated = List<VoyageSession>.from(state.history);
      updated[idx] = updated[idx].copyWith(name: trimmed.isEmpty ? null : trimmed, updatedAt: now);
      state = VoyageState(active: state.active, history: updated);
    }
    await save();
    final session = state.active?.id == id
        ? state.active!
        : state.history.firstWhere((s) => s.id == id);
    ref.read(lanBroadcastProvider)?.call(
        {'type': 'voyage_upsert', 'data': session.toJson()});
  }

  /// Update notes for a voyage.
  Future<void> updateNotes(String id, String notes) async {
    final trimmed = notes.trim();
    final now = DateTime.now();
    if (state.active?.id == id) {
      state = VoyageState(
        active: state.active!.copyWith(notes: trimmed.isEmpty ? null : trimmed, updatedAt: now),
        history: state.history,
      );
    } else {
      final idx = state.history.indexWhere((s) => s.id == id);
      if (idx < 0) return;
      final updated = List<VoyageSession>.from(state.history);
      updated[idx] = updated[idx].copyWith(notes: trimmed.isEmpty ? null : trimmed, updatedAt: now);
      state = VoyageState(active: state.active, history: updated);
    }
    await save();
  }

  // ---- Remote sync --------------------------------------------------------

  /// Upsert a [VoyageSession] received from a remote device (LAN sync).
  /// Uses SyncEngine LWW with full tie-break (tombstone, then sdid lexicographic).
  Future<void> upsertRemote(Map<String, dynamic> data) async {
    try {
      final id = data['id'] as String?;
      if (id == null) return;

      // Check against any existing record with this ID.
      final existingActive = state.active?.id == id ? state.active : null;
      final existingHistoryIdx = state.history.indexWhere((s) => s.id == id);
      final existing = existingActive ??
          (existingHistoryIdx >= 0 ? state.history[existingHistoryIdx] : null);

      if (existing != null) {
        final existingJson = existing.toJson();
        final winnerJson = SyncEngine.merge(existingJson, data, srcKey: 'sdid');
        if (identical(winnerJson, existingJson)) return;
        data = winnerJson;
      }

      final session = VoyageSession.fromJson(data);

      if (session.deleted) {
        // Tombstone: remove from active/history but keep tombstone in history.
        final history = List<VoyageSession>.from(state.history);
        if (existingHistoryIdx >= 0) {
          history[existingHistoryIdx] = session;
        } else {
          history.add(session);
        }
        final active = state.active?.id == session.id ? null : state.active;
        state = VoyageState(active: active, history: history);
      } else if (session.isActive) {
        state = VoyageState(active: session, history: state.history);
      } else {
        final history = List<VoyageSession>.from(state.history);
        if (existingHistoryIdx >= 0) {
          history[existingHistoryIdx] = session;
        } else {
          history.insert(0, session);
        }
        final active = state.active?.id == session.id ? null : state.active;
        state = VoyageState(active: active, history: history);
      }
      await save();
    } catch (_) {}
  }

  // ---- Auto-detection -----------------------------------------------------

  /// Call this with the current vessel SOG to auto-start / auto-end voyages.
  ///
  /// Convention:
  ///   SOG > 1.5 kn for first data → start voyage (auto)
  ///   SOG < 0.5 kn                → end active voyage (auto)
  void handleSog(double? sog, {GpsPosition? position}) {
    if (sog == null) return;

    if (state.active == null && sog > 1.5) {
      startVoyage(VoyageSource.auto, position: position);
    } else if (state.active != null && sog < 0.5) {
      endVoyage(position: position);
    }
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final voyageProvider =
    NotifierProvider<VoyageNotifier, VoyageState>(VoyageNotifier.new);

/// Convenience: the ID of the currently active voyage (or null).
final activeVoyageIdProvider = Provider<String?>(
  (ref) => ref.watch(voyageProvider).active?.id,
);

/// Voyage history with soft-deleted tombstones filtered out.
final voyageHistoryProvider = Provider<List<VoyageSession>>(
  (ref) => ref.watch(voyageProvider).history.where((v) => !v.deleted).toList(),
);

/// Map of voyage ID → display title for quick lookup in log screen.
final voyageNameMapProvider = Provider<Map<String, String>>((ref) {
  final state = ref.watch(voyageProvider);
  final map = <String, String>{};
  if (state.active != null) {
    map[state.active!.id] = state.active!.displayTitle;
  }
  for (final v in state.history.where((v) => !v.deleted)) {
    map[v.id] = v.displayTitle;
  }
  return map;
});

/// Auto-voyage detection: listens to SOG and calls [handleSog].
/// Wire this up in your app's root widget or service layer:
///   ref.listen(voyageAutoDetectProvider, (_, __) {});
final voyageAutoDetectProvider = Provider<void>((ref) {
  final sog = ref.watch(sogProvider);
  final position = ref.watch(positionProvider);
  ref.read(voyageProvider.notifier).handleSog(sog, position: position);
});
