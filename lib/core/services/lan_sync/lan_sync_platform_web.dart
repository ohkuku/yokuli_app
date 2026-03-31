import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../../models/mob_alert.dart';
import '../../models/vessel_state.dart';
import 'lan_sync_platform_base.dart';

/// Web browser implementation.
/// Can ONLY act as a WebSocket client — browsers cannot run servers.
/// UDP discovery is not available; host IP must be entered manually.
class LanSyncPlatformImpl extends LanSyncPlatform {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _intentionalDisconnect = false;
  Timer? _reconnectTimer;
  String? _currentWsUrl;
  bool _connected = false;

  @override
  bool get canBeHost => false;

  @override
  bool get supportsAutoDiscovery => false;

  // --- Host stubs (no-ops on web) ---

  @override
  Future<void> startHost(
    int port,
    String vesselName, {
    String deviceId = '',
    int Function()? getStateVersionMs,
  }) async {}

  @override
  Future<void> stopHost() async {}

  @override
  void updateHostState(VesselState state) {}

  @override
  void broadcastMob(MobAlert alert) {}

  @override
  void broadcastJson(Map<String, dynamic> message) {}

  @override
  bool get isHostRunning => false;

  // --- Client ---

  @override
  Future<void> connectAsClient(String wsUrl) async {
    await disconnectClient();
    _intentionalDisconnect = false;
    _currentWsUrl = wsUrl;
    _doConnect(wsUrl);
  }

  void _doConnect(String wsUrl) {
    onClientConnectionChanged?.call(false);
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _sub = _channel!.stream.listen(
        _onMessage,
        onError: (_) {
          _connected = false;
          onClientConnectionChanged?.call(false);
          if (!_intentionalDisconnect) _scheduleReconnect();
        },
        onDone: () {
          _connected = false;
          onClientConnectionChanged?.call(false);
          if (!_intentionalDisconnect) _scheduleReconnect();
        },
        cancelOnError: true,
      );
      _connected = true;
      onClientConnectionChanged?.call(true);
    } catch (_) {
      _connected = false;
      onClientConnectionChanged?.call(false);
      if (!_intentionalDisconnect) _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;

      // Propagate stateVersion from any message that carries _sv.
      final embeddedSv = json['_sv'] as int?;
      if (embeddedSv != null) {
        onSyncMetaReceived?.call(embeddedSv, json['_id'] as String? ?? '');
      }

      final data = json['data'] as Map<String, dynamic>?;
      switch (json['type'] as String?) {
        case 'vessel_state':
          if (data != null) onStateReceived?.call(VesselState.fromJson(data));
        case 'mob':
          if (data != null) onMobReceived?.call(MobAlert.fromJson(data));
        case 'mob_cancel':
          onMobCancelReceived?.call();
        case 'log_append':
          if (data != null) onLogAppend?.call(data);
        case 'alarm':
          if (data != null) onAlarmSync?.call(data);
        case 'task_upsert':
          if (data != null) onTaskUpsert?.call(data);
        case 'issue_upsert':
          if (data != null) onIssueUpsert?.call(data);
        case 'voyage_upsert':
          if (data != null) onVoyageUpsert?.call(data);
        case 'kanban_sync':
          onKanbanSync?.call(json);
        case 'sk_credentials':
          if (data != null) onSkCredentialsReceived?.call(data);
        case 'settings_sync':
          if (data != null) onSettingsSyncReceived?.call(data);
        case 'sync_meta':
          final svMs = json['sv'] as int?;
          final peerId = json['id'] as String? ?? '';
          if (svMs != null) onSyncMetaReceived?.call(svMs, peerId);
        case 'sync_hello':
          onSyncHelloReceived?.call(json);
        case 'sync_changes':
          onSyncChanges?.call(json);
      }
    } catch (_) {}
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_intentionalDisconnect && _currentWsUrl != null) {
        _doConnect(_currentWsUrl!);
      }
    });
  }

  @override
  Future<void> disconnectClient() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close(ws_status.goingAway);
    _channel = null;
    _sub = null;
    _connected = false;
    onClientConnectionChanged?.call(false);
  }

  @override
  void sendMob(MobAlert alert) {
    _channel?.sink.add(jsonEncode({'type': 'mob', 'data': alert.toJson()}));
  }

  @override
  void sendJson(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  @override
  bool get isClientConnected => _connected;

  // --- Discovery (not available on web) ---

  @override
  Future<void> startDiscovery() async {}

  @override
  void stopDiscovery() {}

  @override
  Future<String> getLocalIp() async => 'web';

  @override
  Future<List<DiscoveredHost>> scanForHosts(String subnet) async => [];
}
