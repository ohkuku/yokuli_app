import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../../models/ais_state.dart';
import '../../models/vessel_state.dart';
import '../../providers/connection_provider.dart'
    show ConnectionNotifier, ConnectionStatus, SignalKFailureReason, connectionProvider;
import '../../providers/vessel_provider.dart';
import 'signalk_auth.dart';
import 'signalk_parser.dart';
import 'signalk_parser_ais.dart';

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
  Timer? _watchdogTimer;
  DateTime? _lastDeltaReceived;
  int _consecutiveErrors = 0;
  static const _maxConsecutiveErrors = 3;

  /// The own-vessel context string received in the SK hello message, e.g.
  /// 'vessels.urn:mrn:imo:mmsi:338234631'.  Used to distinguish own-ship AIS
  /// identity updates from other vessel targets.
  String? _selfContext;

  String? _httpBaseUrl; // e.g. http://host:port — derived from wsUrl on connect

  /// Called with every raw delta JSON map before the parser processes it.
  /// Wire this to [MobWatcherService.onDelta] to evaluate auto-trigger rules.
  void Function(Map<String, dynamic> delta)? onRawDelta;

  SignalKClient(this._ref);

  ConnectionNotifier get _conn => _ref.read(connectionProvider.notifier);

  Future<void> connect(String wsUrl, {String? token}) async {
    await disconnect();
    _intentionalDisconnect = false;
    _currentUrl  = wsUrl;
    _currentToken = token;
    // Derive HTTP base URL from the WebSocket URL for REST API calls.
    _httpBaseUrl = wsUrl
        .replaceFirst(RegExp(r'^wss?'), 'http')
        .replaceFirst(RegExp(r'/signalk/.*'), '');
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
    } catch (e) {
      _conn.setSignalKStatus(ConnectionStatus.error, error: e.toString());
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;

      // Hello message – Signal K sends this immediately after the WS is opened.
      if (json.containsKey('version') && json.containsKey('roles')) {
        // Successful connection — reset error counter.
        _consecutiveErrors = 0;
        // Store the own-vessel context so the AIS parser can distinguish self.
        _selfContext = json['self'] as String?;

        _conn.setSignalKStatus(ConnectionStatus.connected);

        // Send own-vessel subscribe (navigation, wind, depth, electrical).
        _channel?.sink.add(
          jsonEncode(SignalKParser.buildSubscribeMessage()),
        );
        // Send AIS subscribe for all vessels context.
        _channel?.sink.add(
          jsonEncode(SignalKParser.buildAisSubscribeMessage()),
        );
        // Subscribe to notifications and raw NMEA sentences (MOB auto-trigger).
        _channel?.sink.add(
          jsonEncode(SignalKParser.buildMobSubscribeMessage()),
        );
        _startWatchdog();
        // Fetch static own-vessel info (name, MMSI) from REST API.
        _fetchSelfInfo(token: _currentToken);
        return;
      }

      // Delta message.
      if (json.containsKey('updates')) {
        _lastDeltaReceived = DateTime.now();
        // Fire raw delta callback before processing (used by MobWatcherService).
        onRawDelta?.call(json);
        final current = _ref.read(vesselProvider);
        final updated = SignalKParser.applyDelta(
          current,
          json,
          selfContext: _selfContext,
        );
        _ref.read(vesselProvider.notifier).update(updated);
      }
    } catch (_) {
      // Ignore parse errors.
    }
  }

  void _onError(Object error) {
    _consecutiveErrors++;
    _conn.setSignalKStatus(ConnectionStatus.error, error: error.toString());
    if (!_intentionalDisconnect) {
      if (_consecutiveErrors >= _maxConsecutiveErrors) {
        // Persistent failure — address is unreachable. Notify app to redirect
        // the user back to setup so they can fix the Signal K address.
        _conn.setSignalKPermanentFailure(SignalKFailureReason.addressUnreachable);
      } else {
        _scheduleReconnect();
      }
    }
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

  /// Starts a periodic watchdog that forces a reconnect if the connection is
  /// "connected" but no delta messages have been received for 60 seconds.
  /// This handles the common case where the SK server restarts and the TCP
  /// connection appears open (half-open) but no data flows.
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _lastDeltaReceived = DateTime.now();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_intentionalDisconnect) return;
      final last = _lastDeltaReceived;
      if (last == null) return;
      if (DateTime.now().difference(last) > const Duration(seconds: 60)) {
        // Stale connection — force close so _onDone triggers a reconnect.
        _channel?.sink.close(ws_status.goingAway);
      }
    });
  }

  /// Fetch own-vessel static configuration (name, MMSI, callsign) from
  /// the Signal K REST API and apply it to [vesselProvider.aisOwnShip].
  Future<void> _fetchSelfInfo({String? token}) async {
    final base = _httpBaseUrl;
    if (base == null) return;
    try {
      final uri = Uri.parse('$base/signalk/v1/api/vessels/self');
      final headers = <String, String>{};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final response = await http.get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      String? mmsi;
      String? name;
      String? callSign;

      // MMSI from the context field or mmsi path
      if (data.containsKey('mmsi')) {
        mmsi = data['mmsi']?.toString();
      }
      // Try to extract MMSI from the vessel context key if not directly present
      if (mmsi == null && _selfContext != null) {
        mmsi = SignalKAisParser.extractMmsi(_selfContext!);
      }

      // Name: vessels/self/name or vessels/self/name/value
      final nameVal = data['name'];
      if (nameVal is String) {
        name = nameVal;
      } else if (nameVal is Map) {
        name = nameVal['value']?.toString();
      }

      // Callsign
      final comms = data['communication'];
      if (comms is Map) {
        final vhf = comms['callsignVhf'];
        if (vhf is String) callSign = vhf;
        else if (vhf is Map) callSign = vhf['value']?.toString();
      }

      if (mmsi != null || name != null || callSign != null) {
        final current = _ref.read(vesselProvider).aisOwnShip;
        final updated = (current ?? const AisOwnShipState()).copyWith(
          mmsi: mmsi ?? current?.mmsi,
          name: name ?? current?.name,
          callSign: callSign ?? current?.callSign,
          lastUpdated: DateTime.now(),
        );
        _ref.read(vesselProvider.notifier).applyPartial(
          VesselState(
            aisOwnShip: updated,
            batteries: const {},
            solar: const {},
            aisTargets: const {},
            lastUpdated: DateTime.now(),
          ),
        );
      }
    } catch (_) {
      // Non-fatal — own-ship info may be populated later via WS deltas.
    }
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _lastDeltaReceived = null;
    await _sub?.cancel();
    await _channel?.sink.close(ws_status.goingAway);
    _channel = null;
    _sub = null;
    _selfContext = null;
    _httpBaseUrl = null;
    _conn.setSignalKStatus(ConnectionStatus.disconnected);
  }

  bool get isConnected =>
      _ref.read(connectionProvider).signalK == ConnectionStatus.connected;

  /// Returns the own-vessel context string from the last hello message, or
  /// null if not yet connected.
  String? get selfContext => _selfContext;

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
      'electrical.solar.*.outputPower',
    ];
  }
}

final signalKClientProvider = Provider<SignalKClient>((ref) {
  final client = SignalKClient(ref);
  ref.onDispose(client.disconnect);
  return client;
});
