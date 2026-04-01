import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show min, Random;

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../../models/vessel_state.dart';
import '../../models/mob_alert.dart';
import '../../services/telemetry_service.dart';
import 'sync_host.dart' show SyncHost;

typedef DiscoveredHost = ({
  String name,
  String host,
  int port,
  String ws,
  String deviceId,
  int stateVersionMs,
});

/// Connects to a SyncHost on the LAN and receives VesselState updates.
class SyncClient {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _intentionalDisconnect = false;
  Timer? _reconnectTimer;
  String? _currentWsUrl;

  // Exponential back-off state
  int _reconnectAttempts = 0;
  static const int _maxBackoffMs = 30000;
  static const int _baseBackoffMs = 1000;

  // Heartbeat & watchdog
  Timer? _pingTimer;
  Timer? _watchdogTimer;
  DateTime? _lastMessageAt;
  DateTime? _lastPingSentAt;
  static const Duration _pingInterval = Duration(seconds: 15);
  static const Duration _watchdogThreshold = Duration(seconds: 35);

  // Reconnect duration tracking
  DateTime? _connectAttemptAt;

  // Callbacks
  void Function(VesselState state)? onStateReceived;
  void Function(MobAlert alert)? onMobReceived;
  void Function(Map<String, dynamic>? data)? onMobCancelReceived;
  void Function(Map<String, dynamic> data)? onMobHistorySync;
  void Function(bool connected)? onConnectionChanged;
  void Function(Map<String, dynamic> data)? onLogAppend;
  void Function(Map<String, dynamic> data)? onAlarmSync;
  void Function(Map<String, dynamic> data)? onTaskUpsert;
  void Function(Map<String, dynamic> data)? onIssueUpsert;
  void Function(Map<String, dynamic> data)? onVoyageUpsert;
  void Function(Map<String, dynamic>)? onKanbanSync;
  void Function(Map<String, dynamic> data)? onAlarmRuleSync;
  void Function(Map<String, dynamic> data)? onAlarmInstanceSync;
  void Function(Map<String, dynamic> data)? onAlarmActionSync;
  void Function(Map<String, dynamic> data)? onSkCredentialsReceived;
  void Function(Map<String, dynamic> data)? onSettingsSyncReceived;
  void Function(Map<String, dynamic> data)? onMobRuleSync;
  void Function(Map<String, dynamic> data)? onNotifyChannelSyncReceived;
  void Function()? onNetworkJoinSync;
  /// Called when server sends sync_meta (stateVersionMs + deviceId of the server).
  void Function(int svMs, String peerId)? onSyncMetaReceived;
  /// Called when client receives sync_hello from the server.
  void Function(Map<String, dynamic> msg)? onSyncHelloReceived;
  /// Called when client receives sync_changes from the server.
  void Function(Map<String, dynamic> msg)? onSyncChanges;

  Future<void> connect(String wsUrl) async {
    await disconnect();
    _intentionalDisconnect = false;
    _currentWsUrl = wsUrl;
    _doConnect(wsUrl);
  }

  Future<void> _doConnect(String wsUrl) async {
    _connectAttemptAt = DateTime.now();
    TelemetryService.instance.recordConnectionAttempt();
    onConnectionChanged?.call(false);
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      await _channel!.ready;
      _sub = _channel!.stream.listen(
        _onMessage,
        onError: (_) {
          _onDisconnected();
        },
        onDone: () {
          _onDisconnected();
        },
        cancelOnError: true,
      );
      _reconnectAttempts = 0;
      _lastMessageAt = DateTime.now();
      if (_connectAttemptAt != null) {
        final durationMs =
            DateTime.now().difference(_connectAttemptAt!).inMilliseconds;
        TelemetryService.instance.recordConnectionSuccess(durationMs);
      }
      onConnectionChanged?.call(true);
      _startHeartbeat();
    } catch (e) {
      _channel = null;
      TelemetryService.instance.recordConnectionFailure();
      onConnectionChanged?.call(false);
      if (!_intentionalDisconnect) _scheduleReconnect();
    }
  }

  void _onDisconnected() {
    _stopHeartbeat();
    onConnectionChanged?.call(false);
    if (!_intentionalDisconnect) {
      TelemetryService.instance.recordDisconnect();
      _scheduleReconnect();
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (_channel == null) return;
      _lastPingSentAt = DateTime.now();
      _channel?.sink.add(jsonEncode({
        'type': 'ping',
        'at': _lastPingSentAt!.toIso8601String(),
      }));
    });
    _watchdogTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_intentionalDisconnect || _channel == null) return;
      final last = _lastMessageAt;
      if (last != null && DateTime.now().difference(last) > _watchdogThreshold) {
        TelemetryService.instance.log('warn', 'watchdog_reconnect',
            {'silentMs': DateTime.now().difference(last).inMilliseconds});
        _onDisconnected();
        _doConnect(_currentWsUrl!);
      }
    });
  }

  void _stopHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  void _onMessage(dynamic raw) {
    _lastMessageAt = DateTime.now();
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;

      // Every message from the server may carry _sv (stateVersion) and _id
      // (deviceId). Fire onSyncMetaReceived so the recipient stays in sync
      // without needing a full-dump cycle.
      final embeddedSv = json['_sv'] as int?;
      if (embeddedSv != null) {
        onSyncMetaReceived?.call(embeddedSv, json['_id'] as String? ?? '');
      }

      final data = json['data'] as Map<String, dynamic>?;
      switch (json['type'] as String?) {
        case 'vessel_state':
          if (data != null) onStateReceived?.call(VesselState.fromJson(data));
          break;
        case 'mob':
          if (data != null) onMobReceived?.call(MobAlert.fromJson(data));
          break;
        case 'mob_cancel':
          onMobCancelReceived?.call(data);
          break;
        case 'mob_history_sync':
          if (data != null) onMobHistorySync?.call(data);
          break;
        case 'log_append':
          if (data != null) onLogAppend?.call(data);
          break;
        case 'alarm':
          if (data != null) onAlarmSync?.call(data);
          break;
        case 'task_upsert':
          if (data != null) onTaskUpsert?.call(data);
          break;
        case 'issue_upsert':
          if (data != null) onIssueUpsert?.call(data);
          break;
        case 'voyage_upsert':
          if (data != null) onVoyageUpsert?.call(data);
          break;
        case 'kanban_sync':
          onKanbanSync?.call(json);
          break;
        case 'alarm_rules_sync':
          final rules = json['rules'] as List<dynamic>?;
          if (rules != null) {
            for (final r in rules) {
              onAlarmRuleSync?.call(r as Map<String, dynamic>);
            }
          }
          break;
        case 'alarm_instance_sync':
          if (data != null) onAlarmInstanceSync?.call(data);
          break;
        case 'alarm_action_sync':
          if (data != null) onAlarmActionSync?.call(data);
          break;
        case 'sk_credentials':
          if (data != null) onSkCredentialsReceived?.call(data);
          break;
        case 'settings_sync':
          if (data != null) onSettingsSyncReceived?.call(data);
          break;
        case 'sync_meta':
          final svMs = json['sv'] as int?;
          final peerId = json['id'] as String? ?? '';
          if (svMs != null) onSyncMetaReceived?.call(svMs, peerId);
          break;
        case 'mob_rule_sync':
          if (data != null) onMobRuleSync?.call(data);
          break;
        case 'notify_channel_sync':
          if (data != null) onNotifyChannelSyncReceived?.call(data);
          break;
        case 'network_join_sync':
          onNetworkJoinSync?.call();
          break;
        case 'sync_hello':
          onSyncHelloReceived?.call(json);
          break;
        case 'sync_changes':
          onSyncChanges?.call(json);
          break;
        case 'pong':
          // Pong received — connection is alive; watchdog reset happens via _lastMessageAt
          break;
        default:
          break;
      }
    } catch (_) {}
  }

  void sendJson(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    TelemetryService.instance.recordReconnectScheduled(_reconnectAttempts);

    // Exponential backoff with jitter: base * 2^n + rand(0..base), capped at 30s
    final expMs = _baseBackoffMs * (1 << min(_reconnectAttempts - 1, 5));
    final jitterMs = Random().nextInt(_baseBackoffMs);
    final delayMs = min(expMs + jitterMs, _maxBackoffMs);

    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!_intentionalDisconnect && _currentWsUrl != null) {
        _doConnect(_currentWsUrl!);
      }
    });
  }

  /// Send MOB alert to host (host re-broadcasts to all)
  void sendMob(MobAlert alert) {
    _channel?.sink.add(jsonEncode({'type': 'mob', 'data': alert.toJson()}));
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _stopHeartbeat();
    await _sub?.cancel();
    await _channel?.sink.close(ws_status.goingAway);
    _channel = null;
    _sub = null;
    onConnectionChanged?.call(false);
  }

  bool get isConnected => _channel != null;
}

/// Listens on UDP for host announcements broadcast by SyncHost.
/// Re-emits a peer whenever its stateVersionMs increases.
class HostDiscovery {
  RawDatagramSocket? _socket;
  /// deviceId → latest stateVersionMs we've seen from this peer.
  final Map<String, int> _seenVersions = {};
  StreamController<DiscoveredHost>? _controller;

  Stream<DiscoveredHost> get stream {
    _controller ??= StreamController<DiscoveredHost>.broadcast();
    return _controller!.stream;
  }

  Future<void> start() async {
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        SyncHost.discoveryPort,
      );
      _socket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = _socket!.receive();
        if (dg == null) return;
        try {
          final json = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
          if (json['type'] != SyncHost.serviceType) return;

          final ws = json['ws'] as String;
          // Use deviceId for deduplication; fall back to ws if absent (old firmware)
          final deviceId = (json['deviceId'] as String?)?.isNotEmpty == true
              ? json['deviceId'] as String
              : ws;
          final sv = json['sv'] as int? ?? 0;

          // Emit (or re-emit) only when stateVersionMs increases
          final lastSv = _seenVersions[deviceId] ?? -1;
          if (sv > lastSv) {
            _seenVersions[deviceId] = sv;
            _controller?.add((
              name: json['name'] as String? ?? 'Unknown',
              host: json['host'] as String,
              port: json['port'] as int,
              ws: ws,
              deviceId: deviceId,
              stateVersionMs: sv,
            ));
          }
        } catch (_) {}
      });
    } catch (_) {}
  }

  void stop() {
    _socket?.close();
    _socket = null;
    _seenVersions.clear();
  }

  /// Probe a subnet for running hosts (fallback when UDP not available).
  /// TCP scan can't retrieve deviceId or sv, so they default to empty/0.
  static Future<List<DiscoveredHost>> scanSubnet({
    required String subnet, // e.g. "192.168.1"
    int port = SyncHost.defaultPort,
    Duration timeout = const Duration(milliseconds: 300),
  }) async {
    final results = <DiscoveredHost>[];
    final futures = <Future<void>>[];

    for (int i = 1; i <= 254; i++) {
      final ip = '$subnet.$i';
      futures.add(() async {
        try {
          final socket = await Socket.connect(ip, port, timeout: timeout);
          socket.destroy();
          results.add((
            name: 'Yokuli @ $ip',
            host: ip,
            port: port,
            ws: 'ws://$ip:$port',
            deviceId: '',
            stateVersionMs: 0,
          ));
        } catch (_) {}
      }());
    }

    await Future.wait(futures);
    return results;
  }
}
