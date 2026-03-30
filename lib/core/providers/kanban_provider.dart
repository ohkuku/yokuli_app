import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/kanban.dart';

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

  Future<void> addCard(KanbanCard card) async {
    state = KanbanState(columns: state.columns, cards: [...state.cards, card]);
    await _save();
  }

  Future<void> updateCard(KanbanCard card) async {
    final updated = state.cards.map((c) => c.id == card.id ? card : c).toList();
    state = KanbanState(columns: state.columns, cards: updated);
    await _save();
  }

  Future<void> deleteCard(String id) async {
    state = KanbanState(
        columns: state.columns,
        cards: state.cards.where((c) => c.id != id).toList());
    await _save();
  }

  Future<void> moveCard(String cardId, String toColumnId) async {
    final updated = state.cards.map((c) {
      if (c.id != cardId) return c;
      return c.copyWith(columnId: toColumnId, updatedAt: DateTime.now());
    }).toList();
    state = KanbanState(columns: state.columns, cards: updated);
    await _save();
  }

  Future<void> addColumn(String title) async {
    final newOrder = state.columns.isEmpty
        ? 0
        : state.columns.map((c) => c.order).reduce((a, b) => a > b ? a : b) + 1;
    final col = KanbanColumn(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      order: newOrder,
    );
    state = KanbanState(columns: [...state.columns, col], cards: state.cards);
    await _save();
  }

  Future<void> deleteColumn(String columnId) async {
    // Move orphaned cards to backlog
    final updatedCards = state.cards.map((c) {
      if (c.columnId != columnId) return c;
      return c.copyWith(columnId: 'backlog');
    }).toList();
    state = KanbanState(
      columns: state.columns.where((c) => c.id != columnId).toList(),
      cards: updatedCards,
    );
    await _save();
  }
}

final kanbanProvider =
    NotifierProvider<KanbanNotifier, KanbanState>(KanbanNotifier.new);
