import '../../models/mob_alert.dart';
import '../../models/vessel_state.dart';

/// Host discovered on the LAN
typedef DiscoveredHost = ({String name, String host, int port, String ws});

/// Abstract platform interface for LAN sync.
/// Native (mobile/desktop): can be Host or Client.
/// Web: Client only, no UDP discovery, no server.
abstract class LanSyncPlatform {
  /// Whether this platform can act as a WebSocket host/server.
  bool get canBeHost;

  /// Whether automatic LAN host discovery (UDP broadcast) is supported.
  bool get supportsAutoDiscovery;

  // --- Callbacks ---
  void Function(VesselState state)? onStateReceived;
  void Function(MobAlert alert)? onMobReceived;
  void Function(bool connected)? onClientConnectionChanged;
  void Function(int count)? onPeerCountChanged;

  // --- Host operations (native only) ---
  Future<void> startHost(int port, String vesselName);
  Future<void> stopHost();
  void updateHostState(VesselState state);
  void broadcastMob(MobAlert alert);
  bool get isHostRunning;

  // --- Client operations ---
  Future<void> connectAsClient(String wsUrl);
  Future<void> disconnectClient();
  void sendMob(MobAlert alert);
  bool get isClientConnected;

  // --- Discovery ---
  /// Returns this device's local IP (used to show host address in settings).
  Future<String> getLocalIp();

  /// Scan a subnet for running Yokuli hosts.
  /// Returns empty list on web.
  Future<List<DiscoveredHost>> scanForHosts(String subnet);
}
