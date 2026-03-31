import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/kanban.dart';
import '../sync/sync_engine.dart';
import '../utils/id_gen.dart';
import 'device_provider.dart';
import 'lan_broadcast.dart';

class _Store {
  static Future<File> _file(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/yokuli_$name.json');
  }

  static Future<Map<String, dynamic>> load(String name) async {
    try {
      final f = await _file(name);
      if (!await f.exists()) return {};
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(String name, Map<String, dynamic> data) async {
    try {
      (await _file(name)).writeAsString(jsonEncode(data));
    } catch (_) {}
  }
}

class KanbanNotifier extends Notifier<KanbanState> {
  static const _storeName = 'kanban';

  @override
  KanbanState build() {
    load();
    return KanbanState(columns: List.from(kKanbanDefaultColumns));
  }

  Future<void> load() async {
    final data = await _Store.load(_storeName);
    if (data.isEmpty) {
      state = KanbanState(columns: List.from(kKanbanDefaultColumns));
      return;
    }

    final cols = (data['columns'] as List<dynamic>? ?? [])
        .map((c) => KanbanColumn.fromJson(c as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    final cards = (data['cards'] as List<dynamic>? ?? [])
        .map((c) => KanbanCard.fromJson(c as Map<String, dynamic>))
        .toList();

    state = KanbanState(
      columns: cols.isEmpty ? List.from(kKanbanDefaultColumns) : cols,
      cards: cards,
    );
  }

  Future<void> _save() async {
    await _Store.save(_storeName, {
      'columns': state.columns.map((c) => c.toJson()).toList(),
      'cards': state.cards.map((c) => c.toJson()).toList(),
    });
  }

  void _broadcast() {
    ref.read(lanBroadcastProvider)?.call({
      'type': 'kanban_sync',
      'columns': state.columns.map((c) => c.toJson()).toList(),
      'cards': state.cards.map((c) => c.toJson()).toList(),
    });
  }

  /// Bump stateVersion after any local mutation so peers detect we have newer data.
  void _bump() {
    ref.read(deviceProvider.notifier).bump();
  }

  Future<void> addCard(KanbanCard card) async {
    final deviceId = ref.read(deviceProvider).deviceId;
    final cardWithSrc = card.copyWith(sourceDeviceId: card.sourceDeviceId ?? deviceId);
    state = KanbanState(columns: state.columns, cards: [...state.cards, cardWithSrc]);
    await _save();
    _broadcast();
    _bump();
  }

  Future<void> updateCard(KanbanCard card) async {
    final updated = state.cards.map((c) => c.id == card.id ? card : c).toList();
    state = KanbanState(columns: state.columns, cards: updated);
    await _save();
    _broadcast();
    _bump();
  }

  Future<void> deleteCard(String id) async {
    final now = DateTime.now();
    final updated = state.cards.map((c) {
      if (c.id != id) return c;
      return c.copyWith(deleted: true, updatedAt: now);
    }).toList();
    state = KanbanState(columns: state.columns, cards: updated);
    await _save();
    _broadcast();
    _bump();
  }

  Future<void> archiveCard(String id) async {
    final updated = state.cards.map((c) {
      if (c.id != id) return c;
      return c.copyWith(archived: true, updatedAt: DateTime.now());
    }).toList();
    state = KanbanState(columns: state.columns, cards: updated);
    await _save();
    _broadcast();
    _bump();
  }

  Future<void> unarchiveCard(String id) async {
    final updated = state.cards.map((c) {
      if (c.id != id) return c;
      return c.copyWith(archived: false, updatedAt: DateTime.now());
    }).toList();
    state = KanbanState(columns: state.columns, cards: updated);
    await _save();
    _broadcast();
    _bump();
  }

  Future<void> moveCard(String cardId, String toColumnId) async {
    final updated = state.cards.map((c) {
      if (c.id != cardId) return c;
      return c.copyWith(columnId: toColumnId, updatedAt: DateTime.now());
    }).toList();
    state = KanbanState(columns: state.columns, cards: updated);
    await _save();
    _broadcast();
    _bump();
  }

  Future<void> addColumn(String title) async {
    final now = DateTime.now();
    final newOrder = state.columns.isEmpty
        ? 0
        : state.columns.map((c) => c.order).reduce((a, b) => a > b ? a : b) + 1;
    final deviceId = ref.read(deviceProvider).deviceId;
    final col = KanbanColumn(
      id: generateId(),
      title: title,
      order: newOrder,
      updatedAt: now,
      sourceDeviceId: deviceId,
    );
    state = KanbanState(columns: [...state.columns, col], cards: state.cards);
    await _save();
    _broadcast();
    _bump();
  }

  Future<void> deleteColumn(String columnId) async {
    final now = DateTime.now();
    // Move orphaned cards to backlog and bump their updatedAt.
    final updatedCards = state.cards.map((c) {
      if (c.columnId != columnId || c.deleted) return c;
      return c.copyWith(columnId: 'backlog', updatedAt: now);
    }).toList();
    // Soft-delete the column.
    final updatedColumns = state.columns.map((c) {
      if (c.id != columnId) return c;
      return c.copyWith(deleted: true, updatedAt: now);
    }).toList();
    state = KanbanState(columns: updatedColumns, cards: updatedCards);
    await _save();
    _broadcast();
    _bump();
  }

  Future<void> importAll(Map<String, dynamic> data) async {
    final cols = (data['columns'] as List? ?? [])
        .map((c) => KanbanColumn.fromJson(c as Map<String, dynamic>)).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final cards = (data['cards'] as List? ?? [])
        .map((c) => KanbanCard.fromJson(c as Map<String, dynamic>)).toList();
    state = KanbanState(
      columns: cols.isEmpty ? List.from(kKanbanDefaultColumns) : cols,
      cards: cards,
    );
    await _save();
  }

  /// Merge incoming kanban state using per-record LWW (updatedAt comparison).
  /// Used by legacy kanban_sync message type.
  void applySync(Map<String, dynamic> data) {
    try {
      final incomingCols = (data['columns'] as List<dynamic>? ?? [])
          .map((c) => KanbanColumn.fromJson(c as Map<String, dynamic>))
          .toList();
      final incomingCards = (data['cards'] as List<dynamic>? ?? [])
          .map((c) => KanbanCard.fromJson(c as Map<String, dynamic>))
          .toList();

      _mergeColumns(incomingCols);
      _mergeCards(incomingCards);
      _save();
    } catch (_) {}
  }

  /// Merge a list of incoming column records (LWW per ID).
  /// Used by the cursor-based sync_changes protocol.
  void applySyncColumns(List<Map<String, dynamic>> records) {
    try {
      final incomingCols = records
          .map((c) => KanbanColumn.fromJson(c))
          .toList();
      _mergeColumns(incomingCols);
      _save();
    } catch (_) {}
  }

  /// Merge a list of incoming card records (LWW per ID).
  /// Used by the cursor-based sync_changes protocol.
  void applySyncCards(List<Map<String, dynamic>> records) {
    try {
      final incomingCards = records
          .map((c) => KanbanCard.fromJson(c))
          .toList();
      _mergeCards(incomingCards);
      _save();
    } catch (_) {}
  }

  void _mergeColumns(List<KanbanColumn> incomingCols) {
    final colsById = <String, KanbanColumn>{
      for (final c in state.columns) c.id: c,
    };
    for (final inc in incomingCols) {
      final existing = colsById[inc.id];
      if (existing == null) {
        colsById[inc.id] = inc;
      } else {
        final existingJson = existing.toJson();
        final winnerJson = SyncEngine.merge(existingJson, inc.toJson());
        if (!identical(winnerJson, existingJson)) {
          colsById[inc.id] = KanbanColumn.fromJson(winnerJson);
        }
      }
    }
    final mergedCols = colsById.values
        .where((c) => !c.deleted)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    state = KanbanState(
      columns: mergedCols.isEmpty ? state.columns : mergedCols,
      cards: state.cards,
    );
  }

  void _mergeCards(List<KanbanCard> incomingCards) {
    final cardsById = <String, KanbanCard>{
      for (final c in state.cards) c.id: c,
    };
    for (final inc in incomingCards) {
      final existing = cardsById[inc.id];
      if (existing == null) {
        cardsById[inc.id] = inc;
      } else {
        final existingJson = existing.toJson();
        final winnerJson = SyncEngine.merge(existingJson, inc.toJson());
        if (!identical(winnerJson, existingJson)) {
          cardsById[inc.id] = KanbanCard.fromJson(winnerJson);
        }
      }
    }
    state = KanbanState(
      columns: state.columns,
      cards: cardsById.values.toList(),
    );
  }
}

final kanbanProvider =
    NotifierProvider<KanbanNotifier, KanbanState>(KanbanNotifier.new);
