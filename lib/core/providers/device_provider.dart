import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceInfo {
  final String deviceId;       // permanent UUID for this physical device
  final DateTime stateVersion; // last local mutation timestamp

  const DeviceInfo({required this.deviceId, required this.stateVersion});
}

class DeviceNotifier extends Notifier<DeviceInfo> {
  static const _kId = 'p2p_device_id';
  static const _kSv = 'p2p_state_version_ms';

  @override
  DeviceInfo build() {
    _load();
    return DeviceInfo(deviceId: _makeId(), stateVersion: DateTime.now());
  }

  static String _makeId() {
    final rng = Random.secure();
    return List.generate(8, (_) => rng.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kId);
    if (id == null) {
      id = _makeId();
      await prefs.setString(_kId, id);
    }
    final svMs =
        prefs.getInt(_kSv) ?? DateTime.now().millisecondsSinceEpoch;
    state = DeviceInfo(
      deviceId: id,
      stateVersion: DateTime.fromMillisecondsSinceEpoch(svMs),
    );
  }

  /// Call after any LOCAL mutation (never after applying remote data).
  Future<void> bump() async {
    final now = DateTime.now();
    state = DeviceInfo(deviceId: state.deviceId, stateVersion: now);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSv, now.millisecondsSinceEpoch);
  }

  /// Called when we receive a full dump from a peer with newer state.
  Future<void> syncTo(DateTime peerVersion) async {
    if (peerVersion.isAfter(state.stateVersion)) {
      state = DeviceInfo(deviceId: state.deviceId, stateVersion: peerVersion);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kSv, peerVersion.millisecondsSinceEpoch);
    }
  }
}

final deviceProvider =
    NotifierProvider<DeviceNotifier, DeviceInfo>(DeviceNotifier.new);
