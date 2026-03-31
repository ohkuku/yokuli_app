import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yokuli_app/core/providers/lan_broadcast.dart';
import 'package:yokuli_app/core/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deviceName-only update does not broadcast shared vessel settings', () async {
    SharedPreferences.setMockInitialValues({
      'device_name': 'A',
      'vessel_name': 'Vessel A',
    });

    final sent = <Map<String, dynamic>>[];
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(lanBroadcastProvider.notifier).state = (msg) {
      sent.add(msg);
    };

    await container.read(settingsProvider.notifier).load();
    final current = container.read(settingsProvider);
    await container.read(settingsProvider.notifier).update(
          current.copyWith(deviceName: 'B-device'),
        );

    expect(sent, isEmpty);
  });

  test('vesselName update broadcasts only changed shared fields', () async {
    SharedPreferences.setMockInitialValues({
      'device_name': 'A',
      'vessel_name': 'Vessel A',
    });

    final sent = <Map<String, dynamic>>[];
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(lanBroadcastProvider.notifier).state = (msg) {
      sent.add(msg);
    };

    await container.read(settingsProvider.notifier).load();
    final current = container.read(settingsProvider);
    await container.read(settingsProvider.notifier).update(
          current.copyWith(vesselName: 'Vessel B'),
        );

    expect(sent.length, 1);
    expect(sent.first['type'], 'settings_sync');
    final data = sent.first['data'] as Map<String, dynamic>;
    expect(data['vesselName'], 'Vessel B');
    expect(data.containsKey('deviceName'), isFalse);
  });
}

