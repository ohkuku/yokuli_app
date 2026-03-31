import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/notification_receipt.dart';
import '../models/notification_record.dart';
import '../sync/sync_engine.dart';
import 'device_provider.dart';
import 'lan_broadcast.dart';

// ---------------------------------------------------------------------------
// _JsonStore — private file-based JSON persistence helper
// ---------------------------------------------------------------------------

class _JsonStore {
  static Future<File> _file(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name.json');
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
// NotificationNotifier — manages NotificationRecord (global)
// ---------------------------------------------------------------------------

class NotificationNotifier extends Notifier<List<NotificationRecord>> {
  static const _storeName = 'yokuli_notifications';

  @override
  List<NotificationRecord> build() => const [];

  // ---- Persistence ----------------------------------------------------------

  Future<void> load() async {
    final rows = await _JsonStore.load(_storeName);
    state = rows.map(NotificationRecord.fromJson).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _save() async {
    await _JsonStore.save(
        _storeName, state.map((r) => r.toJson()).toList());
  }

  // ---- Mutations ------------------------------------------------------------

  /// Append a new notification record. Saves and broadcasts.
  Future<void> append(NotificationRecord record) async {
    // Deduplicate by id.
    if (state.any((r) => r.id == record.id)) return;
    state = [record, ...state];
    await _save();
    ref.read(lanBroadcastProvider)?.call({
      'type': 'notification_sync',
      'data': record.toJson(),
    });
  }

  /// Apply a record received from a remote peer (LWW merge, no rebroadcast).
  Future<void> applyRemote(Map<String, dynamic> json) async {
    try {
      final incoming = NotificationRecord.fromJson(json);
      final idx = state.indexWhere((r) => r.id == incoming.id);
      if (idx >= 0) {
        final existingJson = state[idx].toJson();
        final merged = SyncEngine.merge(existingJson, json);
        final mergedRecord = NotificationRecord.fromJson(merged);
        final list = List<NotificationRecord>.from(state);
        list[idx] = mergedRecord;
        state = list;
      } else {
        state = [incoming, ...state];
      }
      await _save();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// NotificationReceiptNotifier — manages NotificationReceipt (per-device)
// ---------------------------------------------------------------------------

class NotificationReceiptNotifier extends Notifier<List<NotificationReceipt>> {
  static const _storeName = 'yokuli_notification_receipts';

  @override
  List<NotificationReceipt> build() => const [];

  // ---- Persistence ----------------------------------------------------------

  Future<void> load() async {
    final rows = await _JsonStore.load(_storeName);
    state = rows.map(NotificationReceipt.fromJson).toList();
  }

  Future<void> _save() async {
    await _JsonStore.save(
        _storeName, state.map((r) => r.toJson()).toList());
  }

  // ---- Mutations ------------------------------------------------------------

  /// Dismiss a notification for the given device. Creates a receipt, saves,
  /// and broadcasts.
  Future<void> dismiss(
    String notificationId, {
    required String deviceId,
  }) async {
    final existingId = 'receipt_${notificationId}_$deviceId';
    // Idempotent: if already dismissed, no-op.
    if (state.any((r) => r.id == existingId && !r.deleted)) return;

    final receipt = NotificationReceipt.create(
      notifId: notificationId,
      deviceId: deviceId,
    );

    final idx = state.indexWhere((r) => r.id == existingId);
    if (idx >= 0) {
      final list = List<NotificationReceipt>.from(state);
      list[idx] = receipt;
      state = list;
    } else {
      state = [...state, receipt];
    }
    await _save();
    ref.read(lanBroadcastProvider)?.call({
      'type': 'notification_receipt_sync',
      'data': receipt.toJson(),
    });
  }

  /// Apply a receipt received from a remote peer (LWW merge, no rebroadcast).
  Future<void> applyRemote(Map<String, dynamic> json) async {
    try {
      final incoming = NotificationReceipt.fromJson(json);
      final idx = state.indexWhere((r) => r.id == incoming.id);
      if (idx >= 0) {
        final existingJson = state[idx].toJson();
        final merged = SyncEngine.merge(existingJson, json);
        final mergedReceipt = NotificationReceipt.fromJson(merged);
        final list = List<NotificationReceipt>.from(state);
        list[idx] = mergedReceipt;
        state = list;
      } else {
        state = [...state, incoming];
      }
      await _save();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final notificationProvider =
    NotifierProvider<NotificationNotifier, List<NotificationRecord>>(
        NotificationNotifier.new);

final notificationReceiptProvider =
    NotifierProvider<NotificationReceiptNotifier, List<NotificationReceipt>>(
        NotificationReceiptNotifier.new);

/// Notifications not yet dismissed by the current device, sorted newest-first.
final unreadNotificationsProvider = Provider<List<NotificationRecord>>((ref) {
  final deviceId = ref.watch(deviceProvider).deviceId;
  final records = ref.watch(notificationProvider);
  final receipts = ref.watch(notificationReceiptProvider);
  final dismissedIds = receipts
      .where((r) => r.deviceId == deviceId && !r.deleted)
      .map((r) => r.notificationId)
      .toSet();
  return records
      .where((r) => !r.deleted && !dismissedIds.contains(r.id))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
});

/// Count of unread notifications for the current device.
final unreadNotificationCountProvider = Provider<int>(
    (ref) => ref.watch(unreadNotificationsProvider).length);
