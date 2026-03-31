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
/// Also handles MOB alerts and sync messages from clients.
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
  void Function()? onMobCancelReceived;
  // Event callbacks (host receives from clients, applies + re-broadcasts)
  void Function(Map<String, dynamic> data)? onLogAppend;
  void Function(Map<String, dynamic> data)? onAlarmSync;
  void Function(Map<String, dynamic> data)? onTaskUpsert;
  void Function(Map<String, dynamic> data)? onIssueUpsert;
  void Function(Map<String, dynamic> data)? onVoyageUpsert;
  void Function(Map<String, dynamic>)? onKanbanSync;
  void Function(Map<String, dynamic> data)? onAlarmRuleSync;
  void Function(Map<String, dynamic> data)? onAlarmInstanceSync;
  void Function(Map<String, dynamic> data)? onAlarmActionSync;
  void Function(Map<String, dynamic> data)? onMobRuleSync;
  void Function(Map<String, dynamic> data)? onNotifyChannelSync;
  void Function(Map<String, dynamic> data)? onSettingsSyncReceived;
  void Function(Map<String, dynamic> data)? onSkCredentialsReceived;
  void Function()? onNetworkJoinSync;
  void Function(VesselState state)? onVesselStatePush;
  /// Called when a new client connects; receives a function that sends a
  /// JSON message directly to that specific client only.
  void Function(void Function(Map<String, dynamic>))? onNewClientConnected;
  /// Called when host receives sync_hello from a client.
  /// [reply] sends a message to that specific client only.
  void Function(Map<String, dynamic> msg, void Function(Map<String, dynamic>) reply)? onSyncHello;
  /// Called when host receives sync_changes from a client.
  void Function(Map<String, dynamic> msg)? onSyncChanges;

  Future<void> start({
    required int port,
    required String deviceName,
    VesselState Function()? getState,
    /// Permanent device UUID — included in UDP announcements.
    String deviceId = '',
    /// Returns current stateVersion in ms — rebuilt each 5s UDP tick.
    int Function()? getStateVersionMs,
  }) async {
    final handler = webSocketHandler(
      (WebSocketChannel channel, String? protocol) {
        _clients.add(channel);
        onClientCountChanged?.call(_clients.length);

        // Send current VesselState immediately on connect
        _sendToChannel(channel, _buildStateMessage(_lastState));

        // Notify LanSyncService to send sync_hello to this client
        onNewClientConnected?.call(
          (msg) => _sendToChannel(channel, jsonEncode(msg)),
        );

        channel.stream.listen(
          (message) => _handleClientMessage(message as String, channel),
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

    // UDP discovery broadcast every 5 seconds (dynamic — includes current sv)
    await _startUdpDiscovery(port, deviceName, deviceId, getStateVersionMs);
  }

  Future<void> _startUdpDiscovery(
    int port,
    String deviceName,
    String deviceId,
    int Function()? getStateVersionMs,
  ) async {
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpSocket!.broadcastEnabled = true;

      final localIp = await _getLocalIp();

      void sendAnnouncement() {
        final sv = getStateVersionMs?.call() ?? 0;
        final data = utf8.encode(jsonEncode({
          'type': serviceType,
          'name': deviceName.isNotEmpty ? deviceName : deviceId.substring(0, 8),
          'host': localIp,
          'port': port,
          'ws': 'ws://$localIp:$port',
          'deviceId': deviceId,
          'sv': sv,
        }));
        _udpSocket?.send(data, InternetAddress('255.255.255.255'), discoveryPort);
      }

      // Send immediately, then every 5 seconds
      sendAnnouncement();
      _discoveryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        sendAnnouncement();
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

  void broadcastJson(Map<String, dynamic> message) {
    final msg = jsonEncode(message);
    for (final client in List.of(_clients)) {
      _sendToChannel(client, msg);
    }
  }

  void _handleClientMessage(String raw, WebSocketChannel channel) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final type = json['type'] as String?;
      final data = json['data'] as Map<String, dynamic>?;

      switch (type) {
        case 'mob':
          final alert = MobAlert.fromJson(data!);
          onMobReceived?.call(alert);
          broadcastMob(alert);
          break;
        case 'mob_cancel':
          onMobCancelReceived?.call();
          broadcastJson(json);
          break;
        case 'log_append':
          if (data != null) {
            onLogAppend?.call(data);
            broadcastJson(json);
          }
          break;
        case 'alarm':
          if (data != null) {
            onAlarmSync?.call(data);
            broadcastJson(json);
          }
          break;
        case 'task_upsert':
          if (data != null) {
            onTaskUpsert?.call(data);
            broadcastJson(json);
          }
          break;
        case 'issue_upsert':
          if (data != null) {
            onIssueUpsert?.call(data);
            broadcastJson(json);
          }
          break;
        case 'voyage_upsert':
          if (data != null) {
            onVoyageUpsert?.call(data);
            broadcastJson(json);
          }
          break;
        case 'kanban_sync':
          broadcastJson(json);
          onKanbanSync?.call(json);
          break;
        case 'alarm_rules_sync':
          broadcastJson(json);
          final rules = json['rules'] as List<dynamic>?;
          if (rules != null) {
            for (final r in rules) {
              onAlarmRuleSync?.call(r as Map<String, dynamic>);
            }
          }
          break;
        case 'alarm_instance_sync':
          if (data != null) {
            onAlarmInstanceSync?.call(data);
            broadcastJson(json);
          }
          break;
        case 'alarm_action_sync':
          if (data != null) {
            onAlarmActionSync?.call(data);
            broadcastJson(json);
          }
          break;
        case 'ping':
          // Respond immediately so client watchdog stays satisfied.
          _sendToChannel(
            channel,
            jsonEncode({'type': 'pong', 'at': json['at']}),
          );
          break;
        case 'mob_rule_sync':
          if (data != null) {
            onMobRuleSync?.call(data);
            broadcastJson(json);
          }
          break;
        case 'notify_channel_sync':
          if (data != null) {
            onNotifyChannelSync?.call(data);
            broadcastJson(json);
          }
          break;
        case 'settings_sync':
          if (data != null) {
            onSettingsSyncReceived?.call(data);
            broadcastJson(json);
          }
          break;
        case 'sk_credentials':
          if (data != null) {
            onSkCredentialsReceived?.call(data);
            broadcastJson(json);
          }
          break;
        case 'network_join_sync':
          onNetworkJoinSync?.call();
          broadcastJson(json);
          break;
        case 'vessel_state_push':
          // Client with SK is sharing its vessel state — apply if we lack SK data,
          // then let the 2Hz stateTimer relay it to all other clients automatically.
          if (data != null) {
            try {
              onVesselStatePush?.call(VesselState.fromJson(data));
            } catch (_) {}
          }
          break;
        case 'sync_hello':
          // Client is introducing itself — reply to this specific client only
          onSyncHello?.call(
            json,
            (reply) => _sendToChannel(channel, jsonEncode(reply)),
          );
          break;
        case 'sync_changes':
          // Client is pushing records — apply and forward to all other clients
          onSyncChanges?.call(json);
          broadcastJson(json);
          break;
        default:
          break;
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
