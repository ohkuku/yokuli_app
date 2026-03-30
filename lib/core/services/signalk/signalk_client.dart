import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../../models/vessel_state.dart';
import '../../providers/connection_provider.dart'
    show ConnectionNotifier, ConnectionStatus, connectionProvider;
import '../../providers/vessel_provider.dart';
import 'signalk_auth.dart';
import 'signalk_parser.dart';

/// Manages the WebSocket connection to a Signal K server.
/// Notifies [connectionProvider] of status changes.
/// Writes parsed data into [vesselProvider].
class SignalKClient {
  final Ref _ref;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  String? _currentUrl;
  String? _currentToken;
  bool _intentionalDisconnect = false;
  Timer? _reconnectTimer;

  SignalKClient(this._ref);

  ConnectionNotifier get _conn => _ref.read(connectionProvider.notifier);

  Future<void> connect(String wsUrl, {String? token}) async {
    await disconnect();
    _intentionalDisconnect = false;
    _currentUrl  = wsUrl;
    _currentToken = token;
    _doConnect(wsUrl, token: token);
  }

  void _doConnect(String wsUrl, {String? token}) {
    _conn.setSignalKStatus(ConnectionStatus.connecting);
    try {
      final uri = token != null && token.isNotEmpty
          ? Uri.parse(SignalKAuth.withToken(wsUrl, token))
          : Uri.parse(wsUrl);
      _channel = WebSocketChannel.connect(uri);
      _sub = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );
      // Send subscribe after connection (Signal K sends hello first)
    } catch (e) {
      _conn.setSignalKStatus(ConnectionStatus.error, error: e.toString());
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;

      // Hello message
      if (json.containsKey('version') && json.containsKey('roles')) {
        _conn.setSignalKStatus(ConnectionStatus.connected);
        // Subscribe to paths we need
        _channel?.sink.add(
          jsonEncode(SignalKParser.buildSubscribeMessage()),
        );
        return;
      }

      // Delta message
      if (json.containsKey('updates')) {
        final current = _ref.read(vesselProvider);
        final updated = SignalKParser.applyDelta(current, json);
        _ref.read(vesselProvider.notifier).update(updated);
      }
    } catch (_) {
      // Ignore parse errors
    }
  }

  void _onError(Object error) {
    _conn.setSignalKStatus(ConnectionStatus.error, error: error.toString());
    if (!_intentionalDisconnect) _scheduleReconnect();
  }

  void _onDone() {
    _conn.setSignalKStatus(ConnectionStatus.disconnected);
    if (!_intentionalDisconnect) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_intentionalDisconnect && _currentUrl != null) {
        _doConnect(_currentUrl!, token: _currentToken);
      }
    });
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close(ws_status.goingAway);
    _channel = null;
    _sub = null;
    _conn.setSignalKStatus(ConnectionStatus.disconnected);
  }

  bool get isConnected =>
      _ref.read(connectionProvider).signalK == ConnectionStatus.connected;

  /// Discover available Signal K paths via REST API
  static Future<List<String>> discoverPaths(String baseHttpUrl) async {
    // baseHttpUrl e.g. http://192.168.1.10:3000
    // GET /signalk/v1/api/vessels/self returns full tree
    // For discovery we just return well-known paths
    return [
      'navigation.speedOverGround',
      'navigation.courseOverGroundTrue',
      'navigation.headingTrue',
      'navigation.position',
      'environment.wind.speedTrue',
      'environment.wind.directionTrue',
      'environment.wind.speedApparent',
      'environment.wind.angleApparent',
      'environment.depth.belowKeel',
      'electrical.batteries.*.voltage',
    ];
  }
}

final signalKClientProvider = Provider<SignalKClient>((ref) {
  final client = SignalKClient(ref);
  ref.onDispose(client.disconnect);
  return client;
});
