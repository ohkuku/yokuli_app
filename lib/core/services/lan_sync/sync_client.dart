import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../../models/vessel_state.dart';
import '../../models/mob_alert.dart';
import 'sync_host.dart' show SyncHost;

typedef DiscoveredHost = ({String name, String host, int port, String ws});

/// Connects to a SyncHost on the LAN and receives VesselState updates.
class SyncClient {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _intentionalDisconnect = false;
  Timer? _reconnectTimer;
  String? _currentWsUrl;

  // Callbacks
  void Function(VesselState state)? onStateReceived;
  void Function(MobAlert alert)? onMobReceived;
  void Function()? onMobCancelReceived;
  void Function(bool connected)? onConnectionChanged;
  void Function(Map<String, dynamic> data)? onLogAppend;
  void Function(Map<String, dynamic> data)? onAlarmSync;
  void Function(Map<String, dynamic> data)? onTaskUpsert;
  void Function(Map<String, dynamic> data)? onIssueUpsert;
  void Function(Map<String, dynamic> data)? onVoyageUpsert;

  Future<void> connect(String wsUrl) async {
    await disconnect();
    _intentionalDisconnect = false;
    _currentWsUrl = wsUrl;
    _doConnect(wsUrl);
  }

  Future<void> _doConnect(String wsUrl) async {
    onConnectionChanged?.call(false);
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      // Wait for the WebSocket handshake to complete before reporting connected
      await _channel!.ready;
      _sub = _channel!.stream.listen(
        _onMessage,
        onError: (_) {
          onConnectionChanged?.call(false);
          if (!_intentionalDisconnect) _scheduleReconnect();
        },
        onDone: () {
          onConnectionChanged?.call(false);
          if (!_intentionalDisconnect) _scheduleReconnect();
        },
        cancelOnError: true,
      );
      onConnectionChanged?.call(true);
    } catch (_) {
      _channel = null;
      onConnectionChanged?.call(false);
      if (!_intentionalDisconnect) _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
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
      }
    } catch (_) {}
  }

  void sendJson(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
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
    await _sub?.cancel();
    await _channel?.sink.close(ws_status.goingAway);
    _channel = null;
    _sub = null;
    onConnectionChanged?.call(false);
  }

  bool get isConnected => _channel != null;
}

/// Listens on UDP for host announcements broadcast by SyncHost.
class HostDiscovery {
  RawDatagramSocket? _socket;
  final Set<String> _seen = {};
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
          if (_seen.contains(ws)) return;
          _seen.add(ws);
          _controller?.add((
            name: json['name'] as String? ?? 'Unknown',
            host: json['host'] as String,
            port: json['port'] as int,
            ws: ws,
          ));
        } catch (_) {}
      });
    } catch (_) {}
  }

  void stop() {
    _socket?.close();
    _socket = null;
    _seen.clear();
  }

  /// Probe a subnet for running hosts (fallback when UDP not available)
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
          ));
        } catch (_) {}
      }());
    }

    await Future.wait(futures);
    return results;
  }
}
