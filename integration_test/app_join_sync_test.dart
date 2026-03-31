import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yokuli_app/app.dart';
import 'package:yokuli_app/core/services/lan_sync/lan_sync_service.dart';

void main() {
  testWidgets('shows global edit-lock overlay while join sync is in progress', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const YokulApp(),
      ),
    );

    container.read(networkJoinInProgressProvider.notifier).state = true;
    await tester.pumpAndSettle();

    expect(find.text('正在同步网络数据，暂时禁止编辑…'), findsOneWidget);
  });
}

