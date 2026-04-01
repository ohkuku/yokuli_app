import 'dart:async';
import 'dart:collection' show LinkedHashSet;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
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
import '../../providers/locale_provider.dart' show localeProvider;
import '../../providers/device_provider.dart';
import '../../providers/vessel_provider.dart';
import '../../providers/log_provider.dart';
import '../../providers/alarm_provider.dart';
import '../../providers/alarm_rule_provider.dart';
import '../../providers/alarm_instance_provider.dart';
import '../../providers/alarm_action_provider.dart';
import '../../providers/task_provider.dart';
import '../../providers/issue_provider.dart';
import '../../providers/voyage_provider.dart';
import '../../providers/kanban_provider.dart';
import '../../providers/lan_broadcast.dart';
import '../../../features/mob/providers/mob_provider.dart';
import '../../../features/safety/providers/safety_provider.dart';
import '../../utils/id_gen.dart';
import '../telemetry_service.dart';
import '../../sync/sync_cursor_store.dart';
import '../../sync/sync_engine.dart';
import '../signalk/signalk_auth.dart';
import '../signalk/signalk_client.dart';
import 'lan_sync_platform.dart'; // conditional export → native or web impl
import 'lan_sync_platform_base.dart' show DiscoveredHost;

/// Discovered peers on the LAN — exposed for the settings UI.
final discoveredPeersProvider = StateProvider<List<DiscoveredHost>>((ref) => []);
final networkJoinInProgressProvider = StateProvider<bool>((ref) => false);

/// Sync cursor status — exposed for the settings sync panel.
/// Returns a map of collection → ISO-8601 cursor string.
final syncCursorStatusProvider = FutureProvider<Map<String, String>>((ref) async {
  return SyncCursorStore.getAllCursors();
});

/// Pure policy helper for deciding whether we should try connecting to a peer.
bool shouldAttemptPeerConnect({
  required bool isSelf,
  required bool isClientConnected,
  required int nowMs,
  required int lastAttemptMs,
  int cooldownMs = 5000,
}) {
  if (isSelf) return false;
  if (isClientConnected) return false;
  return (nowMs - lastAttemptMs) >= cooldownMs;
}

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
  Timer? _skPushTimer;
  Timer? _joinGuardTimer;
  Timer? _joinMinTimer;
  DateTime? _joinShownAt;
  static const _joinMinDisplay = Duration(seconds: 3);
  String? _localIp;

  /// peerKey(deviceId or ws) → unix-ms of last connect attempt.
  /// Prevents repeated connection storms while discovery beacons are frequent.
  final Map<String, int> _peerSyncedVersions = {};

  /// Bounded set of processed sync_changes eventIds for idempotent dedup.
  /// Keeps the last 2 000 entries; older ones are evicted as new ones arrive.
  final LinkedHashSet<String> _processedEventIds = LinkedHashSet();
  static const int _eventIdCacheSize = 2000;

  void Function(MobAlert alert)? onMobAlert;
  void Function()? onMobCancelReceived;

  /// Called to get the currently active MOB alert (if any) to push to new clients.
  MobAlert? Function()? getActiveMob;

  /// Called to get alarm threshold settings to include in settings_sync.
  Map<String, dynamic>? Function()? getAlarmSettings;

  /// Called when alarm settings arrive from a remote peer.
  void Function(Map<String, dynamic>)? onAlarmSettingsReceived;

  /// Called to get alarm rules payload to push to new clients.
  /// Supports either:
  ///   - {'rules': [ ... ]}
  ///   - [ ... ]  (legacy direct list)
  Object? Function()? getAlarmRules;

  /// Called to get notify channel config to push to new clients.
  Map<String, dynamic>? Function()? getNotifyChannelCfg;

  /// Called when alarm rules arrive from a remote peer.
  /// Receives normalized rule records.
  void Function(List<Map<String, dynamic>>)? onAlarmRulesReceived;

  /// Called when notify channel config arrives from a remote peer.
  void Function(Map<String, dynamic>)? onNotifyChannelReceived;

  /// Called when an alarm rule record arrives from a remote peer.
  void Function(Map<String, dynamic>)? onAlarmRuleSync;

  /// Called when an alarm instance record arrives from a remote peer.
  void Function(Map<String, dynamic>)? onAlarmInstanceSync;

  /// Called when an alarm action record arrives from a remote peer.
  void Function(Map<String, dynamic>)? onAlarmActionSync;

  /// Called when a mob_rule_sync message arrives from a remote peer.
  void Function(Map<String, dynamic>)? onMobRuleSync;

  /// Called to get current MOB trigger rules to push to new clients.
  List<Map<String, dynamic>> Function()? getMobRules;

  LanSyncService(this._ref) {
    _platform.onStateReceived = (state) {
      // Don't overwrite local SK data with LAN broadcasts — that causes
      // rapid oscillation when multiple devices all have SK connected.
      final skStatus = _ref.read(connectionProvider).signalK;
      if (skStatus != ConnectionStatus.connected) {
        _ref.read(vesselProvider.notifier).update(state);
      }
    };
    _platform.onMobReceived = (alert) {
      // Direct provider update FIRST — never blocked by an external callback throw.
      _ref.read(mobProvider.notifier).receiveMob(alert);
      try { onMobAlert?.call(alert); } catch (_) {}
    };
    _platform.onMobCancelReceived = (data) {
      _ref.read(mobProvider.notifier).receiveMobCancel(data);
      try { onMobCancelReceived?.call(); } catch (_) {}
    };
    _platform.onMobHistorySync = (data) {
      _ref.read(mobProvider.notifier).receiveMobHistory(data);
    };
    _platform.onKanbanSync = (data) {
      _ref.read(kanbanProvider.notifier).applySync(data);
    };
    _platform.onSkCredentialsReceived = _onSkCredentialsReceived;
    _platform.onSettingsSyncReceived = _onSettingsSyncReceived;
    _platform.onClientConnectionChanged = (connected) {
      // Use disconnected (not connecting) when the link drops — connecting is
      // only set right before a connection attempt is made.
      _conn.setLanSyncStatus(
        connected ? ConnectionStatus.connected : ConnectionStatus.disconnected,
      );
      if (connected) {
        _setJoinInProgress(false);
        // As client: send sync_hello to server so it can push missing records to us
        _sendSyncHello(_platform.sendJson);
      } else {
        _setJoinInProgress(false);
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
    _platform.onAlarmRuleSync = (data) {
      _ref.read(alarmRuleProvider.notifier).applyRemote([data]);
      try { onAlarmRuleSync?.call(data); } catch (_) {}
    };
    _platform.onAlarmInstanceSync = (data) {
      _ref.read(alarmInstanceProvider.notifier).upsertRemote(data);
      try { onAlarmInstanceSync?.call(data); } catch (_) {}
    };
    _platform.onAlarmActionSync = (data) {
      _ref.read(alarmActionProvider.notifier).applyRemote(data);
      try { onAlarmActionSync?.call(data); } catch (_) {}
    };
    _platform.onMobRuleSync = (data) {
      _ref.read(mobProvider.notifier).applyRuleRemote(data);
      try { onMobRuleSync?.call(data); } catch (_) {}
    };
    _platform.onNotifyChannelSyncReceived = (data) {
      _ref.read(notifyChannelProvider.notifier).applySync(data);
      try { onNotifyChannelReceived?.call(data); } catch (_) {}
    };
    _platform.onVesselStatePush = (state) {
      // A client is sharing their SK vessel state — apply only if we have no SK.
      final skStatus = _ref.read(connectionProvider).signalK;
      if (skStatus != ConnectionStatus.connected) {
        _ref.read(vesselProvider.notifier).update(state);
      }
    };
    _platform.onNetworkJoinSync = () {
      _setJoinInProgress(true);
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
    try {
      debugPrint('[LanSync] _handleSyncHelloFromClient from ${msg['deviceId']}');
      final peerCursors = _parseCursors(msg['cursors']);
      await _sendMissingRecords(peerCursors, reply);
      // Push current settings, SK credentials, and active MOB to the new client
      // so it becomes fully operational without any manual configuration.
      _pushCurrentStateTo(reply);
      debugPrint('[LanSync] _pushCurrentStateTo completed');
      _setJoinInProgress(false);
    } catch (e, st) {
      debugPrint('[LanSync] ERROR in _handleSyncHelloFromClient: $e\n$st');
    }
  }

  /// Push current settings and MOB state to a specific client (e.g. on first connect).
  void _pushCurrentStateTo(void Function(Map<String, dynamic>) sendTo) {
    final s = _ref.read(settingsProvider);
    final lang = _ref.read(localeProvider);
    final safety = _ref.read(safetyProvider);
    final alarmData = getAlarmSettings?.call() ?? {
      'depthAlarmEnabled': safety.depthAlarmEnabled,
      'depthAlarmThreshold': safety.depthAlarmThreshold,
      'speedAlarmEnabled': safety.speedAlarmEnabled,
      'speedAlarmThreshold': safety.speedAlarmThreshold,
    };
    final alarmRules = getAlarmRules?.call() ?? {
      'rules': _ref.read(alarmRuleProvider).map((r) => r.toJson()).toList(),
    };
    final notifyChannelCfg = getNotifyChannelCfg?.call() ??
        _ref.read(notifyChannelProvider).toJson();
    sendTo({
      'type': 'settings_sync',
      'data': {
        'vesselName': s.vesselName,
        'tileOrder': s.tileOrder,
        'keepScreenOn': s.keepScreenOn,
        'autoConnectLan': s.autoConnectLan,
        'language': lang,
        if (s.hostIp.isNotEmpty) 'hostIp': s.hostIp,
        'hostPort': s.hostPort,
        if (s.signalKUrl.isNotEmpty) 'skUrl': s.signalKUrl,
        'autoConnectSignalK': s.autoConnectSignalK,
        if (s.signalKHost.isNotEmpty) ...{
          'skHost': s.signalKHost,
          'skPort': s.signalKPort,
          'skUser': s.signalKUsername,
          'skPass': s.signalKPassword,
        },
        if (s.metServiceApiKey.isNotEmpty) ...{
          'metServiceApiKey': s.metServiceApiKey,
          if (s.metServiceApiKeyUpdatedAt != null)
            'metServiceApiKeyUpdatedAt': s.metServiceApiKeyUpdatedAt!.toIso8601String(),
        },
        ...alarmData,
        'alarmRules': alarmRules,
        'notifyChannel': notifyChannelCfg,
      },
    });
    // Push active MOB alert
    final mob = getActiveMob?.call() ?? _ref.read(mobProvider).activeMob;
    if (mob != null) {
      sendTo({'type': 'mob', 'data': mob.toJson()});
    }
    // Push each MOB trigger rule individually so new client has full rule set.
    final mobRulesList = getMobRules?.call() ??
        _ref.read(mobProvider).rules.map((r) => r.toJson()).toList();
    for (final rule in mobRulesList) {
      sendTo({'type': 'mob_rule_sync', 'data': rule});
    }
    // Push MOB history so new device has the full cleared-alert log.
    for (final entry in _ref.read(mobProvider).history) {
      sendTo({'type': 'mob_history_sync', 'data': entry.toJson()});
    }
  }

  /// Client received sync_hello from the server.
  Future<void> _handleSyncHelloFromServer(Map<String, dynamic> msg) async {
    try {
      debugPrint('[LanSync] _handleSyncHelloFromServer from ${msg['deviceId']}');
      final peerCursors = _parseCursors(msg['cursors']);
      await _sendMissingRecords(peerCursors, _platform.sendJson);
      _setJoinInProgress(false);
    } catch (e, st) {
      debugPrint('[LanSync] ERROR in _handleSyncHelloFromServer: $e\n$st');
    }
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
        'eventId': generateId(),
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
      case SyncCollections.alarmRules:
        return _ref.read(alarmRuleProvider).map((r) => r.toJson()).toList();
      case SyncCollections.alarmInstances:
        return _ref.read(alarmInstanceProvider).map((i) => i.toJson()).toList();
      case SyncCollections.alarmActions:
        return _ref.read(alarmActionProvider).map((a) => a.toJson()).toList();
      default:
        return [];
    }
  }

  /// Apply a batch of incoming records for a collection (LWW merge) and
  /// advance the local cursor.
  Future<void> _applySyncChanges(Map<String, dynamic> msg) async {
    try {
    return _applySyncChangesInner(msg);
    } catch (e, st) {
      debugPrint('[LanSync] ERROR in _applySyncChanges: $e\n$st');
    }
  }

  Future<void> _applySyncChangesInner(Map<String, dynamic> msg) async {
    // Idempotent dedup: skip if this exact batch was already applied.
    final eventId = msg['eventId'] as String?;
    if (eventId != null) {
      if (_processedEventIds.contains(eventId)) {
        TelemetryService.instance.recordSyncDeduplicated();
        return;
      }
      _processedEventIds.add(eventId);
      if (_processedEventIds.length > _eventIdCacheSize) {
        _processedEventIds.remove(_processedEventIds.first);
      }
    }

    final collection = msg['collection'] as String?;
    final recordsRaw = msg['records'] as List<dynamic>?;
    if (collection == null || recordsRaw == null || recordsRaw.isEmpty) return;

    final records = recordsRaw.cast<Map<String, dynamic>>();

    switch (collection) {
      case SyncCollections.logs:
        for (final r in records) {
          await _ref.read(logProvider.notifier).appendRemote(r);
        }
        break;
      case SyncCollections.alarms:
        for (final r in records) {
          await _ref.read(alarmProvider.notifier).upsertRemote(r);
        }
        break;
      case SyncCollections.tasks:
        for (final r in records) {
          await _ref.read(taskProvider.notifier).upsertInstanceRemote(r);
        }
        break;
      case SyncCollections.issues:
        for (final r in records) {
          await _ref.read(issueProvider.notifier).upsertRemote(r);
        }
        break;
      case SyncCollections.voyages:
        for (final r in records) {
          await _ref.read(voyageProvider.notifier).upsertRemote(r);
        }
        break;
      case SyncCollections.kanbanColumns:
        _ref.read(kanbanProvider.notifier).applySyncColumns(records);
        break;
      case SyncCollections.kanbanCards:
        _ref.read(kanbanProvider.notifier).applySyncCards(records);
        break;
      case SyncCollections.alarmRules:
        await _ref.read(alarmRuleProvider.notifier).applyRemote(records);
        break;
      case SyncCollections.alarmInstances:
        for (final r in records) {
          await _ref.read(alarmInstanceProvider.notifier).upsertRemote(r);
        }
        break;
      case SyncCollections.alarmActions:
        for (final r in records) {
          await _ref.read(alarmActionProvider.notifier).applyRemote(r);
        }
        break;
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
    _setJoinInProgress(false);
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
    final ownDeviceId = _ref.read(deviceProvider).deviceId;
    final ownPort = _ref.read(settingsProvider).hostPort;
    final localIp = _localIp;
    final isSelfById =
        peer.deviceId.isNotEmpty && peer.deviceId == ownDeviceId;
    final isSelfByAddress = localIp != null &&
        localIp.isNotEmpty &&
        peer.host == localIp &&
        peer.port == ownPort;
    if (isSelfById || isSelfByAddress) return;

    // Update the discovered peers list for the settings UI.
    final current = List<DiscoveredHost>.from(_ref.read(discoveredPeersProvider));
    final idx = current.indexWhere((p) => p.deviceId == peer.deviceId);
    if (idx >= 0) {
      current[idx] = peer;
    } else {
      current.add(peer);
      _announceJoinSyncToAll();
    }
    _ref.read(discoveredPeersProvider.notifier).state =
        List.unmodifiable(current);

    _checkAndConnect(peer);
  }

  void _announceJoinSyncToAll() {
    broadcastJson({'type': 'network_join_sync'});
    if (_platform.isClientConnected) {
      _platform.sendJson({'type': 'network_join_sync'});
    }
    _setJoinInProgress(true);
  }

  void _setJoinInProgress(bool value) {
    if (value) {
      _joinGuardTimer?.cancel();
      _joinMinTimer?.cancel();
      _joinShownAt = DateTime.now();
      _ref.read(networkJoinInProgressProvider.notifier).state = true;
      // Hard timeout — clears banner even if sync never completes.
      _joinGuardTimer = Timer(const Duration(seconds: 12), () {
        _ref.read(networkJoinInProgressProvider.notifier).state = false;
        _joinShownAt = null;
      });
    } else {
      // Enforce minimum visible time so the crew can read the banner.
      _joinGuardTimer?.cancel();
      final shown = _joinShownAt;
      final elapsed = shown != null ? DateTime.now().difference(shown) : _joinMinDisplay;
      final remaining = _joinMinDisplay - elapsed;
      if (remaining > Duration.zero) {
        _joinMinTimer = Timer(remaining, () {
          _ref.read(networkJoinInProgressProvider.notifier).state = false;
          _joinShownAt = null;
        });
      } else {
        _joinMinTimer?.cancel();
        _ref.read(networkJoinInProgressProvider.notifier).state = false;
        _joinShownAt = null;
      }
    }
  }

  /// Connect to [peer] as a WS client (throttled), independent of peer sv.
  void _checkAndConnect(DiscoveredHost peer) {
    final peerKey = peer.deviceId.isNotEmpty ? peer.deviceId : peer.ws;
    final ownDeviceId = _ref.read(deviceProvider).deviceId;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastAttemptMs = _peerSyncedVersions[peerKey] ?? 0;
    final isSelf = peer.deviceId.isNotEmpty && peer.deviceId == ownDeviceId;
    if (!shouldAttemptPeerConnect(
      isSelf: isSelf,
      isClientConnected: _platform.isClientConnected,
      nowMs: nowMs,
      lastAttemptMs: lastAttemptMs,
    )) {
      return;
    }
    _peerSyncedVersions[peerKey] = nowMs;

    // Mark connecting before the attempt so the UI shows the right state.
    _setJoinInProgress(true);
    _conn.setLanSyncStatus(ConnectionStatus.connecting);

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

    await _ref.read(settingsProvider.notifier).applyRemote(
          _ref.read(settingsProvider).copyWith(
                signalKHost: host,
                signalKPort: port,
                signalKUsername: username,
                signalKPassword: password,
              ),
        );

    final url = 'ws://$host:$port/signalk/v1/stream?subscribe=all';
    String? token;
    if (username.isNotEmpty && password.isNotEmpty) {
      try {
        token = await SignalKAuth.login(url, username, password);
      } catch (_) {}
    }
    await _ref.read(signalKClientProvider).connect(url, token: token);
  }

  Future<void> _onSettingsSyncReceived(Map<String, dynamic> data) async {
    debugPrint('[LanSync] _onSettingsSyncReceived: keys=${data.keys.toList()}');
    final current = _ref.read(settingsProvider);
    final vesselName = data['vesselName'] as String?;
    final normalizedVesselName = vesselName?.trim();
    final shouldApplyVesselName = normalizedVesselName != null &&
        normalizedVesselName.isNotEmpty &&
        // Guard against a newly joined device pushing defaults over
        // an already configured vessel name.
        !(normalizedVesselName == 'My Vessel' &&
            current.vesselName.trim().isNotEmpty &&
            current.vesselName != 'My Vessel');
    final tileOrder = (data['tileOrder'] as List?)?.cast<String>();
    final keepScreenOn = data['keepScreenOn'] as bool?;
    final autoConnectSignalK = data['autoConnectSignalK'] as bool?;
    final autoConnectLan = data['autoConnectLan'] as bool?;
    final hostIp = data['hostIp'] as String?;
    final hostPort = data['hostPort'] as int?;
    final skUrl = data['skUrl'] as String?;
    final skHost = data['skHost'] as String?;
    final skPort = data['skPort'] as int?;
    final skUser = data['skUser'] as String?;
    final skPass = data['skPass'] as String?;
    final incomingMetKey = data['metServiceApiKey'] as String?;
    final incomingMetKeyTsStr = data['metServiceApiKeyUpdatedAt'] as String?;
    final incomingMetKeyTs = incomingMetKeyTsStr != null
        ? DateTime.tryParse(incomingMetKeyTsStr)
        : null;
    // LWW: only apply incoming MetService key if it's newer than local.
    final applyMetKey = incomingMetKey != null &&
        incomingMetKey.isNotEmpty &&
        (current.metServiceApiKeyUpdatedAt == null ||
            (incomingMetKeyTs != null &&
                incomingMetKeyTs.isAfter(current.metServiceApiKeyUpdatedAt!)));

    await _ref.read(settingsProvider.notifier).applyRemote(
          current.copyWith(
            vesselName:
                shouldApplyVesselName ? normalizedVesselName : current.vesselName,
            tileOrder: tileOrder ?? current.tileOrder,
            keepScreenOn: keepScreenOn ?? current.keepScreenOn,
            autoConnectSignalK:
                autoConnectSignalK ?? current.autoConnectSignalK,
            autoConnectLan: autoConnectLan ?? current.autoConnectLan,
            hostIp: hostIp ?? current.hostIp,
            hostPort: hostPort ?? current.hostPort,
            signalKUrl: skUrl ?? current.signalKUrl,
            signalKHost: skHost ?? current.signalKHost,
            signalKPort: skPort ?? current.signalKPort,
            signalKUsername: skUser ?? current.signalKUsername,
            signalKPassword: skPass ?? current.signalKPassword,
            metServiceApiKey: applyMetKey ? incomingMetKey : current.metServiceApiKey,
            metServiceApiKeyUpdatedAt: applyMetKey ? incomingMetKeyTs : current.metServiceApiKeyUpdatedAt,
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
    } else if (skUrl != null && skUrl.isNotEmpty) {
      final skStatus = _ref.read(connectionProvider).signalK;
      if (skStatus != ConnectionStatus.connected) {
        await _ref.read(signalKClientProvider).connect(skUrl);
      }
    }

    // Apply language if present
    final language = data['language'] as String?;
    if (language != null && language.isNotEmpty) {
      _ref.read(localeProvider.notifier).applyRemote(language);
    }

    // Apply alarm threshold settings if present
    final depthEnabled = data['depthAlarmEnabled'] as bool?;
    final depthThreshold = (data['depthAlarmThreshold'] as num?)?.toDouble();
    final speedEnabled = data['speedAlarmEnabled'] as bool?;
    final speedThreshold = (data['speedAlarmThreshold'] as num?)?.toDouble();
    if (depthEnabled != null || depthThreshold != null ||
        speedEnabled != null || speedThreshold != null) {
      final alarmSettingsData = {
        if (depthEnabled != null) 'depthAlarmEnabled': depthEnabled,
        if (depthThreshold != null) 'depthAlarmThreshold': depthThreshold,
        if (speedEnabled != null) 'speedAlarmEnabled': speedEnabled,
        if (speedThreshold != null) 'speedAlarmThreshold': speedThreshold,
      };
      _ref.read(safetyProvider.notifier).applyAlarmSync(alarmSettingsData);
      try { onAlarmSettingsReceived?.call(alarmSettingsData); } catch (_) {}
    }

    // Apply alarm rules if present
    final alarmRulesRaw = data['alarmRules'];
    final normalizedAlarmRules = _parseAlarmRulesPayload(alarmRulesRaw);
    if (normalizedAlarmRules.isNotEmpty) {
      _ref.read(alarmRuleProvider.notifier).applyRemote(normalizedAlarmRules);
      try { onAlarmRulesReceived?.call(normalizedAlarmRules); } catch (_) {}
    }

    // Apply notify channel config if present
    final notifyChannelRaw = data['notifyChannel'] as Map<String, dynamic>?;
    if (notifyChannelRaw != null) {
      _ref.read(notifyChannelProvider.notifier).applySync(notifyChannelRaw);
      try { onNotifyChannelReceived?.call(notifyChannelRaw); } catch (_) {}
    }
  }

  List<Map<String, dynamic>> _parseAlarmRulesPayload(dynamic raw) {
    if (raw is List) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (raw is Map) {
      final rules = raw['rules'];
      if (rules is List) {
        return rules.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    }
    return const [];
  }

  /// Broadcast current settings to all peers (call after any settings change).
  void broadcastSettings() {
    final s = _ref.read(settingsProvider);
    final lang = _ref.read(localeProvider);
    final safety = _ref.read(safetyProvider);
    broadcastJson({
      'type': 'settings_sync',
      'data': {
        'vesselName': s.vesselName,
        'tileOrder': s.tileOrder,
        'keepScreenOn': s.keepScreenOn,
        'autoConnectLan': s.autoConnectLan,
        'language': lang,
        if (s.hostIp.isNotEmpty) 'hostIp': s.hostIp,
        'hostPort': s.hostPort,
        if (s.signalKUrl.isNotEmpty) 'skUrl': s.signalKUrl,
        'autoConnectSignalK': s.autoConnectSignalK,
        if (s.signalKHost.isNotEmpty) ...{
          'skHost': s.signalKHost,
          'skPort': s.signalKPort,
          'skUser': s.signalKUsername,
          'skPass': s.signalKPassword,
        },
        'depthAlarmEnabled': safety.depthAlarmEnabled,
        'depthAlarmThreshold': safety.depthAlarmThreshold,
        'speedAlarmEnabled': safety.speedAlarmEnabled,
        'speedAlarmThreshold': safety.speedAlarmThreshold,
        'alarmRules': {
          'rules': _ref.read(alarmRuleProvider).map((r) => r.toJson()).toList(),
        },
        'notifyChannel': _ref.read(notifyChannelProvider).toJson(),
      },
    });
  }

  // ---------------------------------------------------------------------------
  // Broadcast helpers for new entity types
  // ---------------------------------------------------------------------------

  void broadcastAlarmRule(Map<String, dynamic> data) {
    broadcastJson({'type': 'alarm_rules_sync', 'rules': [data]});
  }

  void broadcastAlarmInstance(Map<String, dynamic> data) {
    broadcastJson({'type': 'alarm_instance_sync', 'data': data});
  }

  void broadcastAlarmAction(Map<String, dynamic> data) {
    broadcastJson({'type': 'alarm_action_sync', 'data': data});
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  ConnectionNotifier get _conn => _ref.read(connectionProvider.notifier);

  bool get canBeHost => _platform.canBeHost;
  bool get supportsAutoDiscovery => _platform.supportsAutoDiscovery;

  Future<void> start() async {
    _setJoinInProgress(false);
    _localIp = await _platform.getLocalIp();
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
        _setJoinInProgress(true);
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
      settings.deviceName,
      deviceId: ownDeviceId,
      getStateVersionMs: () =>
          _ref.read(deviceProvider).stateVersion.millisecondsSinceEpoch,
    );
    // startHost already starts UDP broadcast; also start discovery listener.
    await _platform.startDiscovery();

    _conn.setLanSyncStatus(ConnectionStatus.connected);
    _setJoinInProgress(false);

    // Push VesselState to connected clients at ~2 Hz.
    _stateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_platform.isHostRunning) {
        _platform.updateHostState(_ref.read(vesselProvider));
      }
    });

    // If this device has SK connected AND is also a LAN client (connected upstream),
    // push vessel state to the host at 2 Hz so the host can relay it to all peers.
    _skPushTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_platform.isClientConnected) {
        final skStatus = _ref.read(connectionProvider).signalK;
        if (skStatus == ConnectionStatus.connected) {
          _platform.sendJson({
            'type': 'vessel_state_push',
            'data': _ref.read(vesselProvider).toJson(),
          });
        }
      }
    });
  }

  Future<void> stop() async {
    _stateTimer?.cancel();
    _stateTimer = null;
    _skPushTimer?.cancel();
    _skPushTimer = null;
    _joinGuardTimer?.cancel();
    _joinGuardTimer = null;
    _joinMinTimer?.cancel();
    _joinMinTimer = null;
    _joinShownAt = null;
    _ref.read(lanBroadcastProvider.notifier).state = null;
    _peerSyncedVersions.clear();
    _platform.stopDiscovery();
    await _platform.stopHost();
    await _platform.disconnectClient();
    _conn.setLanSyncStatus(ConnectionStatus.disconnected);
    _ref.read(discoveredPeersProvider.notifier).state = [];
    _setJoinInProgress(false);
    _localIp = null;
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  void triggerMob(MobAlert alert) {
    // Broadcast to our WS clients; also send upstream if connected to a peer.
    // Embed stateVersion and deviceId metadata so peers stay in sv-sync.
    final device = _ref.read(deviceProvider);
    final withMeta = <String, dynamic>{
      'type': 'mob',
      'data': alert.toJson(),
      '_sv': device.stateVersion.millisecondsSinceEpoch,
      '_id': device.deviceId,
    };
    _platform.broadcastJson(withMeta);
    if (_platform.isClientConnected) _platform.sendJson(withMeta);
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
