import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device role in the LAN mesh
enum DeviceRole { standalone, host, client }

class AppSettings {
  final String deviceName;  // this device's display name (not synced to peers)
  final String vesselName;
  final String signalKUrl; // legacy; use signalKHost+signalKPort for new setups
  final String signalKHost; // e.g. 192.168.1.10 or signalk.local
  final int signalKPort;    // default 3000
  final String signalKUsername;
  final String signalKPassword; // stored in plain text (no security requirement)
  final DeviceRole deviceRole;
  final String hostIp; // when role == client
  final int hostPort;
  final bool autoConnectSignalK;
  final bool autoConnectLan;
  final bool keepScreenOn;
  final List<String> tileOrder; // home screen tile ordering

  const AppSettings({
    this.deviceName = '',
    this.vesselName = 'My Vessel',
    this.signalKUrl = '',
    this.signalKHost = '',
    this.signalKPort = 3000,
    this.signalKUsername = '',
    this.signalKPassword = '',
    this.deviceRole = DeviceRole.standalone,
    this.hostIp = '',
    this.hostPort = 8765,
    this.autoConnectSignalK = false,
    this.autoConnectLan = false,
    this.keepScreenOn = true,
    this.tileOrder = const [],
  });

  bool get hasCredentials =>
      signalKUsername.isNotEmpty && signalKPassword.isNotEmpty;

  /// The WebSocket URL to connect to Signal K.
  /// Prefers host+port if signalKHost is set, otherwise falls back to signalKUrl.
  String get effectiveSignalKUrl {
    if (signalKHost.isNotEmpty) {
      // Sanitise: strip any scheme/path that the user may have accidentally
      // saved (e.g. by pasting a full URL into the host field).
      final host = _sanitizeHost(signalKHost);
      if (host.isNotEmpty) {
        return 'ws://$host:$signalKPort/signalk/v1/stream?subscribe=all';
      }
    }
    return signalKUrl;
  }

  static String _sanitizeHost(String input) {
    var s = input.trim()
        .replaceFirst(RegExp(r'^(wss?|https?)://'), '');
    final slash = s.indexOf('/');
    if (slash >= 0) s = s.substring(0, slash);
    // Strip embedded port (leave IPv6 alone)
    if (!s.startsWith('[')) {
      final colon = s.lastIndexOf(':');
      if (colon > 0) {
        final maybePort = int.tryParse(s.substring(colon + 1));
        if (maybePort != null) s = s.substring(0, colon);
      }
    }
    return s.trim();
  }

  AppSettings copyWith({
    String? deviceName,
    String? vesselName,
    String? signalKUrl,
    String? signalKHost,
    int? signalKPort,
    String? signalKUsername,
    String? signalKPassword,
    DeviceRole? deviceRole,
    String? hostIp,
    int? hostPort,
    bool? autoConnectSignalK,
    bool? autoConnectLan,
    bool? keepScreenOn,
    List<String>? tileOrder,
  }) =>
      AppSettings(
        deviceName: deviceName ?? this.deviceName,
        vesselName: vesselName ?? this.vesselName,
        signalKUrl: signalKUrl ?? this.signalKUrl,
        signalKHost: signalKHost ?? this.signalKHost,
        signalKPort: signalKPort ?? this.signalKPort,
        signalKUsername: signalKUsername ?? this.signalKUsername,
        signalKPassword: signalKPassword ?? this.signalKPassword,
        deviceRole: deviceRole ?? this.deviceRole,
        hostIp: hostIp ?? this.hostIp,
        hostPort: hostPort ?? this.hostPort,
        autoConnectSignalK: autoConnectSignalK ?? this.autoConnectSignalK,
        autoConnectLan: autoConnectLan ?? this.autoConnectLan,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
        tileOrder: tileOrder ?? this.tileOrder,
      );
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _keyDeviceName     = 'device_name';
  static const _keyVesselName     = 'vessel_name';
  static const _keySignalKUrl     = 'signalk_url';
  static const _keySignalKHost    = 'signalk_host';
  static const _keySignalKPort2   = 'signalk_port2';
  static const _keySignalKUser    = 'signalk_username';
  static const _keySignalKPass    = 'signalk_password';
  static const _keyDeviceRole     = 'device_role';
  static const _keyHostIp         = 'host_ip';
  static const _keyHostPort       = 'host_port';
  static const _keyAutoConnectSK  = 'auto_connect_sk';
  static const _keyAutoConnectLan = 'auto_connect_lan';
  static const _keyKeepScreenOn   = 'keep_screen_on';
  static const _keyTileOrder      = 'tile_order';

  @override
  AppSettings build() {
    _loadFromPrefs();
    return const AppSettings();
  }

  /// Awaitable version — call this at startup before reading settings.
  Future<void> load() => _loadFromPrefs();

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final tileOrderStr = prefs.getString(_keyTileOrder) ?? '';
    state = AppSettings(
      deviceName:      prefs.getString(_keyDeviceName)  ?? '',
      vesselName:      prefs.getString(_keyVesselName)  ?? 'My Vessel',
      signalKUrl:      prefs.getString(_keySignalKUrl)  ?? '',
      signalKHost:     prefs.getString(_keySignalKHost) ?? '',
      signalKPort:     prefs.getInt(_keySignalKPort2)   ?? 3000,
      signalKUsername: prefs.getString(_keySignalKUser) ?? '',
      signalKPassword: prefs.getString(_keySignalKPass) ?? '',
      deviceRole: DeviceRole.values.firstWhere(
        (e) => e.name == prefs.getString(_keyDeviceRole),
        orElse: () => DeviceRole.standalone,
      ),
      hostIp:            prefs.getString(_keyHostIp)      ?? '',
      hostPort:          prefs.getInt(_keyHostPort)       ?? 8765,
      autoConnectSignalK: prefs.getBool(_keyAutoConnectSK)  ?? false,
      autoConnectLan:    prefs.getBool(_keyAutoConnectLan) ?? false,
      keepScreenOn:      prefs.getBool(_keyKeepScreenOn)  ?? true,
      tileOrder: tileOrderStr.isEmpty
          ? const []
          : tileOrderStr.split(',').where((s) => s.isNotEmpty).toList(),
    );
  }

  Future<void> update(AppSettings updated) async {
    state = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDeviceName,    updated.deviceName);
    await prefs.setString(_keyVesselName,    updated.vesselName);
    await prefs.setString(_keySignalKUrl,    updated.signalKUrl);
    await prefs.setString(_keySignalKHost,   updated.signalKHost);
    await prefs.setInt(_keySignalKPort2,     updated.signalKPort);
    await prefs.setString(_keySignalKUser,   updated.signalKUsername);
    await prefs.setString(_keySignalKPass,   updated.signalKPassword);
    await prefs.setString(_keyDeviceRole,    updated.deviceRole.name);
    await prefs.setString(_keyHostIp,        updated.hostIp);
    await prefs.setInt(_keyHostPort,         updated.hostPort);
    await prefs.setBool(_keyAutoConnectSK,   updated.autoConnectSignalK);
    await prefs.setBool(_keyAutoConnectLan,  updated.autoConnectLan);
    await prefs.setBool(_keyKeepScreenOn,    updated.keepScreenOn);
    await prefs.setString(_keyTileOrder,     updated.tileOrder.join(','));
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
