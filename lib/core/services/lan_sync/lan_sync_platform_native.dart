import '../../../models/mob_alert.dart';
import '../../../models/vessel_state.dart';
import 'lan_sync_platform_base.dart';
import 'sync_host.dart';
import 'sync_client.dart';

/// Native (Android / iOS / desktop) implementation.
/// Wraps SyncHost (shelf WS server + UDP broadcast) and SyncClient.
class LanSyncPlatformImpl extends LanSyncPlatform {
  final SyncHost _host = SyncHost();
  final SyncClient _client = SyncClient();

  @override
  bool get canBeHost => true;

  @override
  bool get supportsAutoDiscovery => true;

  // --- Host ---

  @override
  Future<void> startHost(int port, String vesselName) async {
    _host.onClientCountChanged = (count) => onPeerCountChanged?.call(count);
    _host.onMobReceived = (alert) => onMobReceived?.call(alert);
    await _host.start(port: port, vesselName: vesselName);
  }

  @override
  Future<void> stopHost() => _host.stop();

  @override
  void updateHostState(VesselState state) => _host.updateState(state);

  @override
  void broadcastMob(MobAlert alert) => _host.broadcastMob(alert);

  @override
  bool get isHostRunning => _host.isRunning;

  // --- Client ---

  @override
  Future<void> connectAsClient(String wsUrl) async {
    _client.onStateReceived = (state) => onStateReceived?.call(state);
    _client.onMobReceived = (alert) => onMobReceived?.call(alert);
    _client.onConnectionChanged = (c) => onClientConnectionChanged?.call(c);
    await _client.connect(wsUrl);
  }

  @override
  Future<void> disconnectClient() => _client.disconnect();

  @override
  void sendMob(MobAlert alert) => _client.sendMob(alert);

  @override
  bool get isClientConnected => _client.isConnected;

  // --- Discovery ---

  @override
  Future<String> getLocalIp() => SyncHost.getLocalIp();

  @override
  Future<List<DiscoveredHost>> scanForHosts(String subnet) =>
      HostDiscovery.scanSubnet(subnet: subnet);
}
