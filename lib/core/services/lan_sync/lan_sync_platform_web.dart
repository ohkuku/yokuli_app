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
  Future<void> startHost(int port, String vesselName) async {}

  @override
  Future<void> stopHost() async {}

  @override
  void updateHostState(VesselState state) {}

  @override
  void broadcastMob(MobAlert alert) {}

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
      switch (json['type'] as String?) {
        case 'vessel_state':
          final state = VesselState.fromJson(json['data'] as Map<String, dynamic>);
          onStateReceived?.call(state);
        case 'mob':
          final alert = MobAlert.fromJson(json['data'] as Map<String, dynamic>);
          onMobReceived?.call(alert);
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
  bool get isClientConnected => _connected;

  // --- Discovery (not available on web) ---

  @override
  Future<String> getLocalIp() async => 'web';

  @override
  Future<List<DiscoveredHost>> scanForHosts(String subnet) async => [];
}
