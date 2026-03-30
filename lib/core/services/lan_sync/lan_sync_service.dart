import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/mob_alert.dart';
import '../../models/vessel_state.dart';
import '../../providers/connection_provider.dart'
    show ConnectionNotifier, ConnectionStatus, connectionProvider;
import '../../providers/settings_provider.dart' show DeviceRole, settingsProvider;
import '../../providers/vessel_provider.dart';
import 'lan_sync_platform.dart'; // conditional export → native or web impl

/// Coordinates LAN sync using the platform-appropriate adapter.
/// - Native: can be Host (shelf WS server + UDP) or Client
/// - Web:    Client only (no server, no UDP discovery)
class LanSyncService {
  final Ref _ref;
  final LanSyncPlatformImpl _platform = LanSyncPlatformImpl();
  Timer? _stateTimer;

  void Function(MobAlert alert)? onMobAlert;

  LanSyncService(this._ref) {
    _platform.onStateReceived = (state) {
      _ref.read(vesselProvider.notifier).update(state);
    };
    _platform.onMobReceived = (alert) => onMobAlert?.call(alert);
    _platform.onClientConnectionChanged = (connected) {
      _conn.setLanSyncStatus(
        connected ? ConnectionStatus.connected : ConnectionStatus.connecting,
      );
    };
    _platform.onPeerCountChanged = (count) {
      _conn.setPeerCount(count);
      // Host status stays connected regardless of client count
    };
  }

  ConnectionNotifier get _conn => _ref.read(connectionProvider.notifier);

  bool get canBeHost => _platform.canBeHost;
  bool get supportsAutoDiscovery => _platform.supportsAutoDiscovery;

  Future<void> start() async {
    final settings = _ref.read(settingsProvider);
    // On web, force client mode regardless of saved role
    final role = kIsWeb ? DeviceRole.client : settings.deviceRole;

    switch (role) {
      case DeviceRole.host:
        _conn.setLanSyncStatus(ConnectionStatus.connecting);
        await _platform.startHost(settings.hostPort, settings.vesselName);
        _conn.setLanSyncStatus(ConnectionStatus.connected);
        // Push VesselState to connected clients at 2 Hz
        _stateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
          if (_platform.isHostRunning) {
            _platform.updateHostState(_ref.read(vesselProvider));
          }
        });

      case DeviceRole.client:
        if (settings.hostIp.isNotEmpty) {
          _conn.setLanSyncStatus(ConnectionStatus.connecting);
          await _platform.connectAsClient(
            'ws://${settings.hostIp}:${settings.hostPort}',
          );
        }

      case DeviceRole.standalone:
        break;
    }
  }

  Future<void> stop() async {
    _stateTimer?.cancel();
    await _platform.stopHost();
    await _platform.disconnectClient();
    _conn.setLanSyncStatus(ConnectionStatus.disconnected);
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  void triggerMob(MobAlert alert) {
    final settings = _ref.read(settingsProvider);
    final role = kIsWeb ? DeviceRole.client : settings.deviceRole;
    if (role == DeviceRole.host) {
      _platform.broadcastMob(alert);
    } else {
      _platform.sendMob(alert);
    }
    onMobAlert?.call(alert);
  }

  /// Returns this device's local IP (empty string on web).
  Future<String> getLocalIp() => _platform.getLocalIp();

  /// Scan LAN subnet for Yokuli hosts. Returns [] on web.
  Future<List<DiscoveredHost>> scanForHosts(String subnet) =>
      _platform.scanForHosts(subnet);
}

final lanSyncServiceProvider = Provider<LanSyncService>((ref) {
  final service = LanSyncService(ref);
  ref.onDispose(service.stop);
  return service;
});
