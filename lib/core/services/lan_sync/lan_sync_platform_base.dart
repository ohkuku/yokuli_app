import '../../models/mob_alert.dart';
import '../../models/vessel_state.dart';

/// Host discovered on the LAN (via UDP or TCP scan).
typedef DiscoveredHost = ({
  String name,
  String host,
  int port,
  String ws,
  /// Permanent device UUID, empty string if unknown (TCP scan fallback).
  String deviceId,
  /// stateVersion in milliseconds since epoch; 0 if unknown.
  int stateVersionMs,
});

/// Abstract platform interface for LAN sync.
/// Native (mobile/desktop): runs WS server + UDP discovery automatically.
/// Web: Client only, no UDP discovery, no server.
abstract class LanSyncPlatform {
  /// Whether this platform can act as a WebSocket host/server.
  bool get canBeHost;

  /// Whether automatic LAN host discovery (UDP broadcast) is supported.
  bool get supportsAutoDiscovery;

  // --- Callbacks ---
  void Function(VesselState state)? onStateReceived;
  void Function(MobAlert alert)? onMobReceived;
  void Function()? onMobCancelReceived;
  void Function(bool connected)? onClientConnectionChanged;
  void Function(int count)? onPeerCountChanged;
  void Function(Map<String, dynamic> data)? onLogAppend;
  void Function(Map<String, dynamic> data)? onAlarmSync;
  void Function(Map<String, dynamic> data)? onTaskUpsert;
  void Function(Map<String, dynamic> data)? onIssueUpsert;
  void Function(Map<String, dynamic> data)? onVoyageUpsert;
  void Function(Map<String, dynamic>)? onKanbanSync;
  void Function(Map<String, dynamic> data)? onSkCredentialsReceived;
  void Function(Map<String, dynamic> data)? onSettingsSyncReceived;
  /// Host only: called when a new client connects; receives a send-to-one function
  /// that LanSyncService uses to send sync_hello to the new client.
  void Function(void Function(Map<String, dynamic>))? onNewClientConnected;
  /// Called when a peer announces itself (or updates its stateVersionMs) via UDP.
  void Function(DiscoveredHost peer)? onPeerDiscovered;
  /// Called when client receives a sync_meta message from the server it connected to.
  void Function(int svMs, String peerId)? onSyncMetaReceived;

  // --- Cursor-based sync callbacks ---

  /// Host only: called when host receives sync_hello from a client.
  /// [reply] sends a message directly to that specific client.
  void Function(
    Map<String, dynamic> msg,
    void Function(Map<String, dynamic>) reply,
  )? onSyncHello;

  /// Client only: called when client receives sync_hello from the server.
  void Function(Map<String, dynamic> msg)? onSyncHelloReceived;

  /// Called when either side receives sync_changes (batch of records).
  void Function(Map<String, dynamic> msg)? onSyncChanges;

  // --- Host operations (native only) ---
  Future<void> startHost(
    int port,
    String vesselName, {
    String deviceId,
    int Function()? getStateVersionMs,
  });
  Future<void> stopHost();
  void updateHostState(VesselState state);
  void broadcastMob(MobAlert alert);
  void broadcastJson(Map<String, dynamic> message);
  bool get isHostRunning;

  // --- Client operations ---
  Future<void> connectAsClient(String wsUrl);
  Future<void> disconnectClient();
  void sendMob(MobAlert alert);
  void sendJson(Map<String, dynamic> message);
  bool get isClientConnected;

  // --- Discovery ---
  Future<void> startDiscovery();
  void stopDiscovery();

  /// Returns this device's local IP (used to show host address in settings).
  Future<String> getLocalIp();

  /// Scan a subnet for running Yokuli hosts (fallback; no deviceId/sv available).
  /// Returns empty list on web.
  Future<List<DiscoveredHost>> scanForHosts(String subnet);
}
