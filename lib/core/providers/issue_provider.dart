import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/issue.dart';
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
// IssueNotifier
// ---------------------------------------------------------------------------

class IssueNotifier extends Notifier<List<IssueTicket>> {
  static const String _storeName = 'issues';

  @override
  List<IssueTicket> build() => const [];

  // ---- Persistence --------------------------------------------------------

  Future<void> load() async {
    final rows = await _JsonStore.load(_storeName);
    state = rows.map(IssueTicket.fromJson).toList();
  }

  Future<void> save() async {
    await _JsonStore.save(
        _storeName, state.map((i) => i.toJson()).toList());
  }

  Future<void> importAll(List<Map<String, dynamic>> rows) async {
    state = rows.map(IssueTicket.fromJson).toList();
    await save();
  }

  // ---- Actions ------------------------------------------------------------

  /// Create and persist a new issue ticket. Returns the created ticket.
  Future<IssueTicket> create({
    required String title,
    required IssueSource source,
    IssueSeverity severity = IssueSeverity.medium,
    String? voyageId,
    String? linkedLogId,
  }) async {
    final ticket = IssueTicket(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      source: source,
      severity: severity,
      status: IssueStatus.open,
      createdAt: DateTime.now(),
      notes: const [],
      linkedLogIds: linkedLogId != null ? [linkedLogId] : const [],
      linkedVoyageId: voyageId,
    );

    state = [...state, ticket];
    await save();
    ref.read(lanBroadcastProvider)?.call(
        {'type': 'issue_upsert', 'data': ticket.toJson()});
    return ticket;
  }

  /// Update the status of an issue. Sets resolvedAt when transitioning to done.
  Future<void> updateStatus(String id, IssueStatus status) async {
    state = state.map((ticket) {
      if (ticket.id != id) return ticket;
      final resolvedAt =
          status == IssueStatus.done ? DateTime.now() : ticket.resolvedAt;
      return ticket.copyWith(status: status, resolvedAt: resolvedAt);
    }).toList();
    await save();
    final updated = state.firstWhere((t) => t.id == id);
    ref.read(lanBroadcastProvider)?.call(
        {'type': 'issue_upsert', 'data': updated.toJson()});
  }

  /// Append a free-text note to an issue.
  Future<void> addNote(String id, String note) async {
    state = state.map((ticket) {
      if (ticket.id != id) return ticket;
      return ticket.copyWith(notes: [...ticket.notes, note]);
    }).toList();
    await save();
    final updated = state.firstWhere((t) => t.id == id);
    ref.read(lanBroadcastProvider)?.call(
        {'type': 'issue_upsert', 'data': updated.toJson()});
  }

  /// Link a log entry ID to an issue.
  Future<void> linkLog(String id, String logId) async {
    state = state.map((ticket) {
      if (ticket.id != id) return ticket;
      if (ticket.linkedLogIds.contains(logId)) return ticket;
      return ticket.copyWith(
          linkedLogIds: [...ticket.linkedLogIds, logId]);
    }).toList();
    await save();
  }

  /// Upsert an [IssueTicket] received from a remote device (LAN sync).
  Future<void> upsertRemote(Map<String, dynamic> data) async {
    try {
      final ticket = IssueTicket.fromJson(data);
      final idx = state.indexWhere((i) => i.id == ticket.id);
      if (idx >= 0) {
        final updated = List<IssueTicket>.from(state);
        updated[idx] = ticket;
        state = updated;
      } else {
        state = [...state, ticket];
      }
      await save();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final issueProvider =
    NotifierProvider<IssueNotifier, List<IssueTicket>>(IssueNotifier.new);

/// All issues that are not yet resolved (status != done).
final openIssuesProvider = Provider<List<IssueTicket>>(
  (ref) => ref.watch(issueProvider).where((i) => i.isOpen).toList(),
);

/// High-severity open issues only.
final criticalIssuesProvider = Provider<List<IssueTicket>>(
  (ref) => ref
      .watch(openIssuesProvider)
      .where((i) => i.severity == IssueSeverity.high)
      .toList(),
);
