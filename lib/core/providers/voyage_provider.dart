import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/vessel_state.dart';
import '../models/voyage.dart';
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
      if (s.isActive) {
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

    final session = VoyageSession(
      id: now.millisecondsSinceEpoch.toString(),
      startTime: now,
      startPosition: position,
      status: VoyageStatus.active,
      source: source,
    );

    state = VoyageState(
      active: session,
      history: state.history,
    );
    await save();
    ref.read(lanBroadcastProvider)?.call(
        {'type': 'voyage_upsert', 'data': session.toJson()});
  }

  /// End the currently active voyage.
  Future<void> endVoyage({GpsPosition? position}) async {
    final current = state.active;
    if (current == null) return;

    final ended = current.copyWith(
      endTime: DateTime.now(),
      endPosition: position,
      status: VoyageStatus.ended,
    );

    final newHistory = [ended, ...state.history];

    state = VoyageState(active: null, history: newHistory);
    await save();
    ref.read(lanBroadcastProvider)?.call(
        {'type': 'voyage_upsert', 'data': ended.toJson()});
  }

  // ---- Remote sync --------------------------------------------------------

  /// Upsert a [VoyageSession] received from a remote device (LAN sync).
  Future<void> upsertRemote(Map<String, dynamic> data) async {
    try {
      final session = VoyageSession.fromJson(data);
      if (session.isActive) {
        // Remote device started/updated active voyage
        state = VoyageState(active: session, history: state.history);
      } else {
        // Completed voyage — upsert in history
        final idx = state.history.indexWhere((s) => s.id == session.id);
        final List<VoyageSession> updated;
        if (idx >= 0) {
          updated = List<VoyageSession>.from(state.history);
          updated[idx] = session;
        } else {
          updated = [session, ...state.history];
        }
        final active = state.active?.id == session.id ? null : state.active;
        state = VoyageState(active: active, history: updated);
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

/// Auto-voyage detection: listens to SOG and calls [handleSog].
/// Wire this up in your app's root widget or service layer:
///   ref.listen(voyageAutoDetectProvider, (_, __) {});
final voyageAutoDetectProvider = Provider<void>((ref) {
  final sog = ref.watch(sogProvider);
  final position = ref.watch(positionProvider);
  ref.read(voyageProvider.notifier).handleSog(sog, position: position);
});
