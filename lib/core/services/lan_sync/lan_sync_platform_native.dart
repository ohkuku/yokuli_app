import '../../models/mob_alert.dart';
import '../../models/vessel_state.dart';
import 'lan_sync_platform_base.dart';
import 'sync_host.dart';
import 'sync_client.dart' hide DiscoveredHost;

/// Native (Android / iOS / desktop) implementation.
/// Every native device runs as a WS server AND can connect as a client.
/// UDP discovery runs automatically when the server is started.
class LanSyncPlatformImpl extends LanSyncPlatform {
  final SyncHost _host = SyncHost();
  final SyncClient _client = SyncClient();
  final HostDiscovery _discovery = HostDiscovery();

  @override
  bool get canBeHost => true;

  @override
  bool get supportsAutoDiscovery => true;

  // --- Host ---

  @override
  Future<void> startHost(
    int port,
    String vesselName, {
    String deviceId = '',
    int Function()? getStateVersionMs,
  }) async {
    _host.onClientCountChanged = (count) => onPeerCountChanged?.call(count);
    _host.onMobReceived = (alert) => onMobReceived?.call(alert);
    _host.onMobCancelReceived = () => onMobCancelReceived?.call();
    _host.onLogAppend = (data) => onLogAppend?.call(data);
    _host.onAlarmSync = (data) => onAlarmSync?.call(data);
    _host.onTaskUpsert = (data) => onTaskUpsert?.call(data);
    _host.onIssueUpsert = (data) => onIssueUpsert?.call(data);
    _host.onVoyageUpsert = (data) => onVoyageUpsert?.call(data);
    _host.onKanbanSync = (data) => onKanbanSync?.call(data);
    _host.onNewClientConnected = (sendTo) => onNewClientConnected?.call(sendTo);
    _host.onSyncHello = (msg, reply) => onSyncHello?.call(msg, reply);
    _host.onSyncChanges = (msg) => onSyncChanges?.call(msg);
    await _host.start(
      port: port,
      vesselName: vesselName,
      deviceId: deviceId,
      getStateVersionMs: getStateVersionMs,
    );
  }

  @override
  Future<void> stopHost() async {
    _discovery.stop();
    await _host.stop();
  }

  @override
  void updateHostState(VesselState state) => _host.updateState(state);

  @override
  void broadcastMob(MobAlert alert) => _host.broadcastMob(alert);

  @override
  void broadcastJson(Map<String, dynamic> message) =>
      _host.broadcastJson(message);

  @override
  bool get isHostRunning => _host.isRunning;

  // --- Client ---

  @override
  Future<void> connectAsClient(String wsUrl) async {
    _client.onStateReceived = (state) => onStateReceived?.call(state);
    _client.onMobReceived = (alert) => onMobReceived?.call(alert);
    _client.onMobCancelReceived = () => onMobCancelReceived?.call();
    _client.onConnectionChanged = (c) => onClientConnectionChanged?.call(c);
    _client.onLogAppend = (data) => onLogAppend?.call(data);
    _client.onAlarmSync = (data) => onAlarmSync?.call(data);
    _client.onTaskUpsert = (data) => onTaskUpsert?.call(data);
    _client.onIssueUpsert = (data) => onIssueUpsert?.call(data);
    _client.onVoyageUpsert = (data) => onVoyageUpsert?.call(data);
    _client.onKanbanSync = (data) => onKanbanSync?.call(data);
    _client.onSkCredentialsReceived = (data) => onSkCredentialsReceived?.call(data);
    _client.onSettingsSyncReceived = (data) => onSettingsSyncReceived?.call(data);
    _client.onSyncMetaReceived = (svMs, peerId) =>
        onSyncMetaReceived?.call(svMs, peerId);
    _client.onSyncHelloReceived = (msg) => onSyncHelloReceived?.call(msg);
    _client.onSyncChanges = (msg) => onSyncChanges?.call(msg);
    await _client.connect(wsUrl);
  }

  @override
  Future<void> disconnectClient() => _client.disconnect();

  @override
  void sendMob(MobAlert alert) => _client.sendMob(alert);

  @override
  void sendJson(Map<String, dynamic> message) => _client.sendJson(message);

  @override
  bool get isClientConnected => _client.isConnected;

  // --- Discovery ---

  @override
  Future<void> startDiscovery() async {
    _discovery.stream.listen((peer) => onPeerDiscovered?.call(peer));
    await _discovery.start();
  }

  @override
  void stopDiscovery() => _discovery.stop();

  @override
  Future<String> getLocalIp() => SyncHost.getLocalIp();

  @override
  Future<List<DiscoveredHost>> scanForHosts(String subnet) =>
      HostDiscovery.scanSubnet(subnet: subnet);
}
