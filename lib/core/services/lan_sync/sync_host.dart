import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../models/vessel_state.dart';
import '../../models/mob_alert.dart';

/// Runs a WebSocket server on the LAN.
/// Host broadcasts VesselState updates to all connected clients.
/// Also handles MOB alerts from clients.
class SyncHost {
  static const int defaultPort = 8765;
  static const int discoveryPort = 43215;
  static const String serviceType = 'yokuli';

  HttpServer? _server;
  Timer? _broadcastTimer;
  Timer? _discoveryTimer;
  RawDatagramSocket? _udpSocket;
  final Set<WebSocketChannel> _clients = {};
  VesselState _lastState = VesselState.empty();

  // Callbacks
  void Function(int clientCount)? onClientCountChanged;
  void Function(MobAlert alert)? onMobReceived;

  Future<void> start({
    required int port,
    required String vesselName,
    VesselState Function()? getState,
  }) async {
    final handler = webSocketHandler(
      (WebSocketChannel channel, String? protocol) {
        _clients.add(channel);
        onClientCountChanged?.call(_clients.length);

        // Send current state immediately on connect
        _sendToChannel(channel, _buildStateMessage(_lastState));

        channel.stream.listen(
          (message) => _handleClientMessage(message as String),
          onDone: () {
            _clients.remove(channel);
            onClientCountChanged?.call(_clients.length);
          },
          onError: (_) {
            _clients.remove(channel);
            onClientCountChanged?.call(_clients.length);
          },
          cancelOnError: true,
        );
      },
    );

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);

    // Broadcast VesselState to all clients at ~2Hz
    _broadcastTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_clients.isNotEmpty) {
        final msg = _buildStateMessage(_lastState);
        for (final client in List.of(_clients)) {
          _sendToChannel(client, msg);
        }
      }
    });

    // UDP discovery broadcast every 5 seconds
    await _startUdpDiscovery(port, vesselName);
  }

  Future<void> _startUdpDiscovery(int port, String vesselName) async {
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpSocket!.broadcastEnabled = true;

      final localIp = await _getLocalIp();
      final announcement = jsonEncode({
        'type': serviceType,
        'name': vesselName,
        'host': localIp,
        'port': port,
        'ws': 'ws://$localIp:$port',
      });
      final data = utf8.encode(announcement);

      _discoveryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _udpSocket?.send(
          data,
          InternetAddress('255.255.255.255'),
          discoveryPort,
        );
      });
    } catch (_) {
      // Discovery optional — continue without it
    }
  }

  void updateState(VesselState state) {
    _lastState = state;
  }

  void broadcastMob(MobAlert alert) {
    final msg = jsonEncode({'type': 'mob', 'data': alert.toJson()});
    for (final client in List.of(_clients)) {
      _sendToChannel(client, msg);
    }
  }

  void _handleClientMessage(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['type'] == 'mob') {
        final alert = MobAlert.fromJson(json['data'] as Map<String, dynamic>);
        onMobReceived?.call(alert);
        // Re-broadcast to all other clients
        broadcastMob(alert);
      }
    } catch (_) {}
  }

  void _sendToChannel(WebSocketChannel channel, String message) {
    try {
      channel.sink.add(message);
    } catch (_) {
      _clients.remove(channel);
    }
  }

  String _buildStateMessage(VesselState state) =>
      jsonEncode({'type': 'vessel_state', 'data': state.toJson()});

  Future<void> stop() async {
    _broadcastTimer?.cancel();
    _discoveryTimer?.cancel();
    _udpSocket?.close();
    for (final client in List.of(_clients)) {
      await client.sink.close();
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
  }

  bool get isRunning => _server != null;
  int get clientCount => _clients.length;

  static Future<String> _getLocalIp() async {
    for (final iface in await NetworkInterface.list()) {
      for (final addr in iface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          return addr.address;
        }
      }
    }
    return '127.0.0.1';
  }

  static Future<String> getLocalIp() => _getLocalIp();
}
