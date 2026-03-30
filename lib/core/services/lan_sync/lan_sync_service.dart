import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/mob_alert.dart';
import '../../models/vessel_state.dart';
import '../../providers/connection_provider.dart'
    show ConnectionNotifier, ConnectionStatus, connectionProvider;
import '../../providers/settings_provider.dart' show DeviceRole, settingsProvider;
import '../../providers/vessel_provider.dart';
import 'sync_client.dart';
import 'sync_host.dart';

/// Coordinates between SyncHost (when role=host) and SyncClient (when role=client).
/// Watches vesselProvider for state changes and forwards them to clients.
class LanSyncService {
  final Ref _ref;
  final SyncHost _host = SyncHost();
  final SyncClient _client = SyncClient();
  final HostDiscovery _discovery = HostDiscovery();
  StreamSubscription? _vesselSub;

  // MOB callback for the app
  void Function(MobAlert alert)? onMobAlert;

  LanSyncService(this._ref);

  ConnectionNotifier get _conn => _ref.read(connectionProvider.notifier);

  Future<void> start() async {
    final settings = _ref.read(settingsProvider);
    switch (settings.deviceRole) {
      case DeviceRole.host:
        await _startHost(settings.hostPort, settings.vesselName);
      case DeviceRole.client:
        await _startClient('ws://${settings.hostIp}:${settings.hostPort}');
      case DeviceRole.standalone:
        // Nothing to do
        break;
    }
  }

  Future<void> _startHost(int port, String vesselName) async {
    _host.onClientCountChanged = (count) {
      _conn.setLanSyncStatus(
        count > 0 ? ConnectionStatus.connected : ConnectionStatus.connecting,
      );
    };
    _host.onMobReceived = (alert) => onMobAlert?.call(alert);

    await _host.start(port: port, vesselName: vesselName);
    _conn.setLanSyncStatus(ConnectionStatus.connecting); // waiting for clients

    // Push vessel state updates to connected clients
    _vesselSub = Stream.periodic(const Duration(milliseconds: 500)).listen((_) {
      if (_host.isRunning) {
        _host.updateState(_ref.read(vesselProvider));
      }
    });
  }

  Future<void> _startClient(String wsUrl) async {
    _client.onStateReceived = (state) {
      _ref.read(vesselProvider.notifier).update(state);
    };
    _client.onMobReceived = (alert) => onMobAlert?.call(alert);
    _client.onConnectionChanged = (connected) {
      _conn.setLanSyncStatus(
        connected ? ConnectionStatus.connected : ConnectionStatus.connecting,
      );
    };
    await _client.connect(wsUrl);
  }

  Future<void> stop() async {
    await _vesselSub?.cancel();
    await _host.stop();
    await _client.disconnect();
    _discovery.stop();
    _conn.setLanSyncStatus(ConnectionStatus.disconnected);
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  /// Trigger MOB alert — works on both host and client
  void triggerMob(MobAlert alert) {
    final role = _ref.read(settingsProvider).deviceRole;
    if (role == DeviceRole.host) {
      _host.broadcastMob(alert);
    } else if (role == DeviceRole.client) {
      _client.sendMob(alert);
    }
    onMobAlert?.call(alert);
  }

  SyncHost get host => _host;
  SyncClient get client => _client;
  HostDiscovery get discovery => _discovery;

  String? get hostAddress => null; // resolved via SyncHost._getLocalIp
}

final lanSyncServiceProvider = Provider<LanSyncService>((ref) {
  final service = LanSyncService(ref);
  ref.onDispose(service.stop);
  return service;
});
