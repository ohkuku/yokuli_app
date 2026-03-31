import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yokuli_app/app.dart';
import 'package:yokuli_app/core/models/mob_alert.dart';
import 'package:yokuli_app/features/mob/providers/mob_provider.dart';
import 'package:yokuli_app/features/mob/views/mob_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('A triggers/cancels MOB -> B enters active state and navigates to MOB page', (tester) async {
    final b = ProviderContainer();
    addTearDown(b.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: b,
        child: const YokulApp(),
      ),
    );

    final alert = MobAlert(
      id: 'mob_evt_1',
      triggeredAt: DateTime.now(),
      triggeredByDevice: 'A',
    );

    // Simulate A publishing MOB event to B over LAN.
    b.read(mobProvider.notifier).receiveMob(alert);
    await tester.pumpAndSettle();

    expect(b.read(mobProvider).isMobActive, isTrue);
    expect(find.byType(MobScreen), findsOneWidget);

    // Simulate A publishing MOB cancel event to B over LAN.
    b.read(mobProvider.notifier).receiveMobCancel();
    await tester.pumpAndSettle();

    expect(b.read(mobProvider).isMobActive, isFalse);
  });
}

