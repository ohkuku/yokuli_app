import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device role in the LAN mesh
enum DeviceRole { standalone, host, client }

class AppSettings {
  final String vesselName;
  final String signalKUrl; // e.g. ws://192.168.1.10:3000/signalk/v1/stream
  final DeviceRole deviceRole;
  final String hostIp; // when role == client
  final int hostPort;
  final bool autoConnectSignalK;
  final bool autoConnectLan;
  final bool keepScreenOn;

  const AppSettings({
    this.vesselName = 'My Vessel',
    this.signalKUrl = '',
    this.deviceRole = DeviceRole.standalone,
    this.hostIp = '',
    this.hostPort = 8765,
    this.autoConnectSignalK = false,
    this.autoConnectLan = false,
    this.keepScreenOn = true,
  });

  AppSettings copyWith({
    String? vesselName,
    String? signalKUrl,
    DeviceRole? deviceRole,
    String? hostIp,
    int? hostPort,
    bool? autoConnectSignalK,
    bool? autoConnectLan,
    bool? keepScreenOn,
  }) =>
      AppSettings(
        vesselName: vesselName ?? this.vesselName,
        signalKUrl: signalKUrl ?? this.signalKUrl,
        deviceRole: deviceRole ?? this.deviceRole,
        hostIp: hostIp ?? this.hostIp,
        hostPort: hostPort ?? this.hostPort,
        autoConnectSignalK: autoConnectSignalK ?? this.autoConnectSignalK,
        autoConnectLan: autoConnectLan ?? this.autoConnectLan,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      );
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _keyVesselName = 'vessel_name';
  static const _keySignalKUrl = 'signalk_url';
  static const _keyDeviceRole = 'device_role';
  static const _keyHostIp = 'host_ip';
  static const _keyHostPort = 'host_port';
  static const _keyAutoConnectSK = 'auto_connect_sk';
  static const _keyAutoConnectLan = 'auto_connect_lan';
  static const _keyKeepScreenOn = 'keep_screen_on';

  @override
  AppSettings build() {
    _loadFromPrefs();
    return const AppSettings();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      vesselName: prefs.getString(_keyVesselName) ?? 'My Vessel',
      signalKUrl: prefs.getString(_keySignalKUrl) ?? '',
      deviceRole: DeviceRole.values.firstWhere(
        (e) => e.name == prefs.getString(_keyDeviceRole),
        orElse: () => DeviceRole.standalone,
      ),
      hostIp: prefs.getString(_keyHostIp) ?? '',
      hostPort: prefs.getInt(_keyHostPort) ?? 8765,
      autoConnectSignalK: prefs.getBool(_keyAutoConnectSK) ?? false,
      autoConnectLan: prefs.getBool(_keyAutoConnectLan) ?? false,
      keepScreenOn: prefs.getBool(_keyKeepScreenOn) ?? true,
    );
  }

  Future<void> update(AppSettings updated) async {
    state = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVesselName, updated.vesselName);
    await prefs.setString(_keySignalKUrl, updated.signalKUrl);
    await prefs.setString(_keyDeviceRole, updated.deviceRole.name);
    await prefs.setString(_keyHostIp, updated.hostIp);
    await prefs.setInt(_keyHostPort, updated.hostPort);
    await prefs.setBool(_keyAutoConnectSK, updated.autoConnectSignalK);
    await prefs.setBool(_keyAutoConnectLan, updated.autoConnectLan);
    await prefs.setBool(_keyKeepScreenOn, updated.keepScreenOn);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
