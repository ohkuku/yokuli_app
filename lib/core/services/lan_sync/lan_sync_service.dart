import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/mob_alert.dart';
import '../../models/vessel_state.dart';
import '../../models/log_entry.dart';
import '../../models/alarm.dart';
import '../../models/task.dart';
import '../../models/issue.dart';
import '../../models/voyage.dart';
import '../../providers/connection_provider.dart'
    show ConnectionNotifier, ConnectionStatus, connectionProvider;
import '../../providers/settings_provider.dart' show settingsProvider;
import '../../providers/device_provider.dart';
import '../../providers/vessel_provider.dart';
import '../../providers/log_provider.dart';
import '../../providers/alarm_provider.dart';
import '../../providers/task_provider.dart';
import '../../providers/issue_provider.dart';
import '../../providers/voyage_provider.dart';
import '../../providers/kanban_provider.dart';
import '../../providers/lan_broadcast.dart';
import '../../sync/sync_cursor_store.dart';
import '../../sync/sync_engine.dart';
import '../signalk/signalk_auth.dart';
import '../signalk/signalk_client.dart';
import 'lan_sync_platform.dart'; // conditional export → native or web impl
import 'lan_sync_platform_base.dart' show DiscoveredHost;

/// Discovered peers on the LAN — exposed for the settings UI.
final discoveredPeersProvider = StateProvider<List<DiscoveredHost>>((ref) => []);

/// Sync cursor status — exposed for the settings sync panel.
/// Returns a map of collection → ISO-8601 cursor string.
final syncCursorStatusProvider = FutureProvider<Map<String, String>>((ref) async {
  return SyncCursorStore.getAllCursors();
});

/// Coordinates LAN sync using the platform-appropriate adapter.
///
/// Native: every device runs a WS server automatically. UDP discovery finds
/// peers. When a new client connects, both sides exchange sync_hello messages
/// to perform cursor-based incremental sync.
///
/// Web: client only — connect manually to a known host IP.
class LanSyncService {
  final Ref _ref;
  final LanSyncPlatformImpl _platform = LanSyncPlatformImpl();
  Timer? _stateTimer;

  /// deviceId → stateVersionMs we last successfully triggered a sync with.
  /// Prevents duplicate connections to the same peer at the same version.
  final Map<String, int> _peerSyncedVersions = {};

  void Function(MobAlert alert)? onMobAlert;
  void Function()? onMobCancelReceived;

  LanSyncService(this._ref) {
    _platform.onStateReceived = (state) {
      // Don't overwrite local SK data with LAN broadcasts — that causes
      // rapid oscillation when multiple devices all have SK connected.
      final skStatus = _ref.read(connectionProvider).signalK;
      if (skStatus != ConnectionStatus.connected) {
        _ref.read(vesselProvider.notifier).update(state);
      }
    };
    _platform.onMobReceived = (alert) => onMobAlert?.call(alert);
    _platform.onMobCancelReceived = () => onMobCancelReceived?.call();
    _platform.onKanbanSync = (data) {
      _ref.read(kanbanProvider.notifier).applySync(data);
    };
    _platform.onSkCredentialsReceived = _onSkCredentialsReceived;
    _platform.onSettingsSyncReceived = _onSettingsSyncReceived;
    _platform.onClientConnectionChanged = (connected) {
      _conn.setLanSyncStatus(
        connected ? ConnectionStatus.connected : ConnectionStatus.connecting,
      );
      if (connected) {
        // As client: send sync_hello to server so it can push missing records to us
        _sendSyncHello(_platform.sendJson);
      }
    };
    _platform.onPeerCountChanged = (count) => _conn.setPeerCount(count);
    _platform.onLogAppend = (data) {
      _ref.read(logProvider.notifier).appendRemote(data);
    };
    _platform.onAlarmSync = (data) {
      _ref.read(alarmProvider.notifier).upsertRemote(data);
    };
    _platform.onTaskUpsert = (data) {
      _ref.read(taskProvider.notifier).upsertInstanceRemote(data);
    };
    _platform.onIssueUpsert = (data) {
      _ref.read(issueProvider.notifier).upsertRemote(data);
    };
    _platform.onVoyageUpsert = (data) {
      _ref.read(voyageProvider.notifier).upsertRemote(data);
    };
    // Server: when a new client connects, send sync_hello to them
    _platform.onNewClientConnected = _sendSyncHello;
    _platform.onPeerDiscovered = _onPeerDiscovered;
    _platform.onSyncMetaReceived = (svMs, peerId) {
      // After receiving a full dump from a server, adopt their stateVersion.
      _ref.read(deviceProvider.notifier).syncTo(
        DateTime.fromMillisecondsSinceEpoch(svMs),
      );
    };
    // Server: received sync_hello from a client → send our missing records to them
    _platform.onSyncHello = _handleSyncHelloFromClient;
    // Client: received sync_hello from the server → send our missing records to it
    _platform.onSyncHelloReceived = _handleSyncHelloFromServer;
    // Both sides: apply incoming batch of records
    _platform.onSyncChanges = (msg) => _applySyncChanges(msg);
  }

  // ---------------------------------------------------------------------------
  // Sync hello protocol
  // ---------------------------------------------------------------------------

  /// Build and send a sync_hello message to [sendTo].
  ///
  /// The hello includes our own deviceId and per-collection cursors so the
  /// recipient knows which records to send us.
  Future<void> _sendSyncHello(void Function(Map<String, dynamic>) sendTo) async {
    final deviceId = _ref.read(deviceProvider).deviceId;
    final cursors = await SyncCursorStore.getAllCursors();
    sendTo({
      'type': 'sync_hello',
      'deviceId': deviceId,
      'cursors': cursors,
    });
  }

  /// Server received sync_hello from a client.
  ///
  /// [reply] sends a message directly to that specific client only.
  Future<void> _handleSyncHelloFromClient(
    Map<String, dynamic> msg,
    void Function(Map<String, dynamic>) reply,
  ) async {
    final peerCursors = _parseCursors(msg['cursors']);
    await _sendMissingRecords(peerCursors, reply);
  }

  /// Client received sync_hello from the server.
  Future<void> _handleSyncHelloFromServer(Map<String, dynamic> msg) async {
    final peerCursors = _parseCursors(msg['cursors']);
    await _sendMissingRecords(peerCursors, _platform.sendJson);
  }

  /// Parse cursors map from sync_hello — gracefully handles nulls.
  Map<String, DateTime?> _parseCursors(dynamic raw) {
    final result = <String, DateTime?>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final key = entry.key as String;
        final val = entry.value as String?;
        result[key] = val != null ? DateTime.tryParse(val) : null;
      }
    }
    return result;
  }

  /// Send all records newer than the peer's cursor for each collection.
  Future<void> _sendMissingRecords(
    Map<String, DateTime?> peerCursors,
    void Function(Map<String, dynamic>) sendTo,
  ) async {
    for (final collection in SyncCollections.all) {
      // null cursor = peer has never synced this collection → send all
      final peerCursor = peerCursors[collection];
      final records = _getRecordsForCollection(collection);
      final missing = SyncEngine.missingFor(records, peerCursor);
      if (missing.isEmpty) continue;
      sendTo({
        'type': 'sync_changes',
        'collection': collection,
        'records': missing,
      });
    }
  }

  /// Get all records for [collection] as raw JSON maps.
  List<Map<String, dynamic>> _getRecordsForCollection(String collection) {
    switch (collection) {
      case SyncCollections.logs:
        return _ref.read(logProvider).map((e) => e.toJson()).toList();
      case SyncCollections.alarms:
        return _ref.read(alarmProvider).map((a) => a.toJson()).toList();
      case SyncCollections.tasks:
        return _ref.read(taskProvider).instances.map((i) => i.toJson()).toList();
      case SyncCollections.issues:
        return _ref.read(issueProvider).map((i) => i.toJson()).toList();
      case SyncCollections.voyages:
        final vs = _ref.read(voyageProvider);
        return [
          if (vs.active != null) vs.active!.toJson(),
          ...vs.history.map((s) => s.toJson()),
        ];
      case SyncCollections.kanbanColumns:
        return _ref.read(kanbanProvider).columns.map((c) => c.toJson()).toList();
      case SyncCollections.kanbanCards:
        return _ref.read(kanbanProvider).cards.map((c) => c.toJson()).toList();
      default:
        return [];
    }
  }

  /// Apply a batch of incoming records for a collection (LWW merge) and
  /// advance the local cursor.
  Future<void> _applySyncChanges(Map<String, dynamic> msg) async {
    final collection = msg['collection'] as String?;
    final recordsRaw = msg['records'] as List<dynamic>?;
    if (collection == null || recordsRaw == null || recordsRaw.isEmpty) return;

    final records = recordsRaw.cast<Map<String, dynamic>>();

    switch (collection) {
      case SyncCollections.logs:
        for (final r in records) {
          await _ref.read(logProvider.notifier).appendRemote(r);
        }
      case SyncCollections.alarms:
        for (final r in records) {
          await _ref.read(alarmProvider.notifier).upsertRemote(r);
        }
      case SyncCollections.tasks:
        for (final r in records) {
          await _ref.read(taskProvider.notifier).upsertInstanceRemote(r);
        }
      case SyncCollections.issues:
        for (final r in records) {
          await _ref.read(issueProvider.notifier).upsertRemote(r);
        }
      case SyncCollections.voyages:
        for (final r in records) {
          await _ref.read(voyageProvider.notifier).upsertRemote(r);
        }
      case SyncCollections.kanbanColumns:
        _ref.read(kanbanProvider.notifier).applySyncColumns(records);
      case SyncCollections.kanbanCards:
        _ref.read(kanbanProvider.notifier).applySyncCards(records);
    }

    // Advance local cursor to max ua across received records
    final maxUa = records.fold<DateTime>(
      DateTime.fromMillisecondsSinceEpoch(0),
      (best, r) {
        final ua = r['ua'] as String?;
        if (ua == null) return best;
        final dt = DateTime.tryParse(ua);
        return (dt != null && dt.isAfter(best)) ? dt : best;
      },
    );
    if (maxUa.millisecondsSinceEpoch > 0) {
      await SyncCursorStore.advance(collection, maxUa);
    }
  }

  // ---------------------------------------------------------------------------
  // Force full resync
  // ---------------------------------------------------------------------------

  /// Reset all cursors and reconnect — triggers a full resync on next connect.
  Future<void> forceFullResync() async {
    await SyncCursorStore.resetAll();
    await restart();
  }

  // ---------------------------------------------------------------------------
  // P2P discovery & auto-connect
  // ---------------------------------------------------------------------------

  void _onPeerDiscovered(DiscoveredHost peer) {
    // Update the discovered peers list for the settings UI.
    final current = List<DiscoveredHost>.from(_ref.read(discoveredPeersProvider));
    final idx = current.indexWhere((p) => p.deviceId == peer.deviceId);
    if (idx >= 0) {
      current[idx] = peer;
    } else {
      current.add(peer);
    }
    _ref.read(discoveredPeersProvider.notifier).state =
        List.unmodifiable(current);

    _checkAndConnect(peer);
  }

  /// Connect to [peer] as a WS client if they have newer data than us.
  void _checkAndConnect(DiscoveredHost peer) {
    final device = _ref.read(deviceProvider);

    // Never connect to ourselves.
    if (peer.deviceId.isNotEmpty && peer.deviceId == device.deviceId) return;

    final ownSvMs = device.stateVersion.millisecondsSinceEpoch;

    // Only connect if peer has strictly newer data.
    if (peer.stateVersionMs <= ownSvMs) return;

    // Don't re-trigger if we already initiated a sync at this exact version.
    final lastSynced = _peerSyncedVersions[peer.deviceId] ?? 0;
    if (peer.stateVersionMs <= lastSynced) return;

    // Record before connecting to prevent races / duplicate calls.
    _peerSyncedVersions[peer.deviceId] = peer.stateVersionMs;

    // Connect — sync_hello exchange will happen automatically on connection
    _platform.connectAsClient(peer.ws);
  }

  // ---------------------------------------------------------------------------
  // SK credentials
  // ---------------------------------------------------------------------------

  /// Broadcasts the host's Signal K credentials to all clients.
  void broadcastSkCredentials() {
    final s = _ref.read(settingsProvider);
    if (s.signalKHost.isEmpty) return;
    broadcastJson({
      'type': 'sk_credentials',
      'data': {
        'host': s.signalKHost,
        'port': s.signalKPort,
        'username': s.signalKUsername,
        'password': s.signalKPassword,
      },
    });
  }

  Future<void> _onSkCredentialsReceived(Map<String, dynamic> data) async {
    final host = data['host'] as String? ?? '';
    final port = data['port'] as int? ?? 3000;
    final username = data['username'] as String? ?? '';
    final password = data['password'] as String? ?? '';
    if (host.isEmpty) return;

    await _ref.read(settingsProvider.notifier).update(
          _ref.read(settingsProvider).copyWith(
                signalKHost: host,
                signalKPort: port,
                signalKUsername: username,
                signalKPassword: password,
              ),
        );

    final url = 'ws://$host:$port/signalk/v1/stream';
    String? token;
    if (username.isNotEmpty && password.isNotEmpty) {
      try {
        token = await SignalKAuth.login(url, username, password);
      } catch (_) {}
    }
    await _ref.read(signalKClientProvider).connect(url, token: token);
  }

  Future<void> _onSettingsSyncReceived(Map<String, dynamic> data) async {
    final current = _ref.read(settingsProvider);
    final vesselName = data['vesselName'] as String?;
    final tileOrder = (data['tileOrder'] as List?)?.cast<String>();
    final keepScreenOn = data['keepScreenOn'] as bool?;
    final skHost = data['skHost'] as String?;
    final skPort = data['skPort'] as int?;
    final skUser = data['skUser'] as String?;
    final skPass = data['skPass'] as String?;

    await _ref.read(settingsProvider.notifier).update(
          current.copyWith(
            vesselName: vesselName ?? current.vesselName,
            tileOrder: tileOrder ?? current.tileOrder,
            keepScreenOn: keepScreenOn ?? current.keepScreenOn,
            signalKHost: skHost ?? current.signalKHost,
            signalKPort: skPort ?? current.signalKPort,
            signalKUsername: skUser ?? current.signalKUsername,
            signalKPassword: skPass ?? current.signalKPassword,
          ),
        );

    // Auto-connect SK if credentials arrived and we're not already connected
    if (skHost != null && skHost.isNotEmpty) {
      final skStatus = _ref.read(connectionProvider).signalK;
      if (skStatus != ConnectionStatus.connected) {
        await _onSkCredentialsReceived({
          'host': skHost,
          'port': skPort ?? 3000,
          'username': skUser ?? '',
          'password': skPass ?? '',
        });
      }
    }
  }

  /// Broadcast current settings to all peers (call after any settings change).
  void broadcastSettings() {
    final s = _ref.read(settingsProvider);
    broadcastJson({
      'type': 'settings_sync',
      'data': {
        'vesselName': s.vesselName,
        'tileOrder': s.tileOrder,
        'keepScreenOn': s.keepScreenOn,
        if (s.signalKHost.isNotEmpty) ...{
          'skHost': s.signalKHost,
          'skPort': s.signalKPort,
          'skUser': s.signalKUsername,
          'skPass': s.signalKPassword,
        },
      },
    });
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  ConnectionNotifier get _conn => _ref.read(connectionProvider.notifier);

  bool get canBeHost => _platform.canBeHost;
  bool get supportsAutoDiscovery => _platform.supportsAutoDiscovery;

  Future<void> start() async {
    if (kIsWeb) {
      // Web: client-only — connect to manually configured host IP.
      final settings = _ref.read(settingsProvider);
      _ref.read(lanBroadcastProvider.notifier).state = (msg) {
        final device = _ref.read(deviceProvider);
        final withMeta = Map<String, dynamic>.from(msg)
          ..['_sv'] = device.stateVersion.millisecondsSinceEpoch
          ..['_id'] = device.deviceId;
        _platform.sendJson(withMeta);
      };

      if (settings.hostIp.isNotEmpty) {
        _conn.setLanSyncStatus(ConnectionStatus.connecting);
        await _platform.connectAsClient(
          'ws://${settings.hostIp}:${settings.hostPort}',
        );
      }
      return;
    }

    // Native: always start as WS server + UDP discovery.
    final settings = _ref.read(settingsProvider);
    final ownDeviceId = _ref.read(deviceProvider).deviceId;

    // Broadcast function: push to our WS clients AND upstream if we're also
    // connected as a client to a peer (so they relay it further).
    // Always embed _sv + _id so all recipients stay in sv-sync automatically.
    _ref.read(lanBroadcastProvider.notifier).state = (msg) {
      final device = _ref.read(deviceProvider);
      final withMeta = Map<String, dynamic>.from(msg)
        ..['_sv'] = device.stateVersion.millisecondsSinceEpoch
        ..['_id'] = device.deviceId;
      _platform.broadcastJson(withMeta);
      if (_platform.isClientConnected) _platform.sendJson(withMeta);
    };

    _conn.setLanSyncStatus(ConnectionStatus.connecting);
    await _platform.startHost(
      settings.hostPort,
      settings.vesselName,
      deviceId: ownDeviceId,
      getStateVersionMs: () =>
          _ref.read(deviceProvider).stateVersion.millisecondsSinceEpoch,
    );
    // startHost already starts UDP broadcast; also start discovery listener.
    await _platform.startDiscovery();

    _conn.setLanSyncStatus(ConnectionStatus.connected);

    // Push VesselState to connected clients at ~2 Hz.
    _stateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_platform.isHostRunning) {
        _platform.updateHostState(_ref.read(vesselProvider));
      }
    });
  }

  Future<void> stop() async {
    _stateTimer?.cancel();
    _stateTimer = null;
    _ref.read(lanBroadcastProvider.notifier).state = null;
    _peerSyncedVersions.clear();
    _platform.stopDiscovery();
    await _platform.stopHost();
    await _platform.disconnectClient();
    _conn.setLanSyncStatus(ConnectionStatus.disconnected);
    _ref.read(discoveredPeersProvider.notifier).state = [];
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  void triggerMob(MobAlert alert) {
    // Broadcast to our WS clients; also send upstream if connected to a peer.
    _platform.broadcastMob(alert);
    if (_platform.isClientConnected) _platform.sendMob(alert);
    onMobAlert?.call(alert);
  }

  /// Send a JSON message upstream to the host we're connected to (client mode).
  void sendJson(Map<String, dynamic> message) => _platform.sendJson(message);

  /// Broadcast a JSON message to all connected WS clients (server mode).
  void broadcastJson(Map<String, dynamic> message) =>
      _platform.broadcastJson(message);

  /// Returns this device's local IP (empty string on web).
  Future<String> getLocalIp() => _platform.getLocalIp();

  /// Scan LAN subnet for Yokuli hosts (TCP fallback; no sv/deviceId). Returns [] on web.
  Future<List<DiscoveredHost>> scanForHosts(String subnet) =>
      _platform.scanForHosts(subnet);
}

final lanSyncServiceProvider = Provider<LanSyncService>((ref) {
  final service = LanSyncService(ref);
  ref.onDispose(service.stop);
  return service;
});
