import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yokuli_app/core/models/alarm_rule.dart';
import 'package:yokuli_app/core/models/mob_trigger_rule.dart';
import 'package:yokuli_app/core/providers/alarm_rule_provider.dart';
import 'package:yokuli_app/core/providers/lan_broadcast.dart';
import 'package:yokuli_app/features/mob/providers/mob_provider.dart';

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A->B realtime rule sync regression', () {
    late ProviderContainer a;
    late ProviderContainer b;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      a = ProviderContainer();
      b = ProviderContainer();

      a.read(lanBroadcastProvider.notifier).state = (msg) {
        final type = msg['type'] as String?;
        if (type == 'mob_rule_sync') {
          b.read(mobProvider.notifier).applyRuleRemote(
                Map<String, dynamic>.from(msg['data'] as Map),
              );
        }
        if (type == 'alarm_rules_sync') {
          final rules = (msg['rules'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          b.read(alarmRuleProvider.notifier).applyRemote(rules);
        }
      };
    });

    tearDown(() {
      a.dispose();
      b.dispose();
    });

    testWidgets('MOB rule CRUD syncs in realtime', (tester) async {
      final now = DateTime.now();
      final rule = MobTriggerRule(
        id: 'mob_rule_1',
        name: 'MOB notify',
        enabled: true,
        type: MobTriggerType.signalkNotification,
        config: const {
          'pathPattern': 'mob',
          'states': ['emergency'],
        },
        createdAt: now,
        updatedAt: now,
      );

      await a.read(mobProvider.notifier).addRule(rule);
      await _flush();
      expect(
        b.read(mobProvider).rules.any((r) => r.id == rule.id),
        isTrue,
      );

      final updated = rule.copyWith(
        enabled: false,
        updatedAt: now.add(const Duration(seconds: 1)),
      );
      await a.read(mobProvider.notifier).updateRule(updated);
      await _flush();
      final fromB = b.read(mobProvider).rules.firstWhere((r) => r.id == rule.id);
      expect(fromB.enabled, isFalse);

      await a.read(mobProvider.notifier).deleteRule(rule.id);
      await _flush();
      expect(
        b.read(mobProvider).rules.any((r) => r.id == rule.id),
        isFalse,
      );
    });

    testWidgets('Alarm rule CRUD syncs in realtime', (tester) async {
      final now = DateTime.now();
      final rule = AlarmRule(
        id: 'alarm_rule_custom_1',
        name: 'Depth Watch',
        enabled: true,
        level: AlarmLevel.warning,
        condition: const AlarmCondition(
          source: AlarmConditionSource.vesselMetric,
          metric: 'depth_keel',
          operator: AlarmOperator.lessEqual,
          threshold: 2.8,
        ),
        responsePlan: const AlarmResponsePlan(inApp: true, sound: true),
        snoozeMins: 5,
        isBuiltIn: false,
        updatedAt: now,
        sourceDeviceId: 'A',
      );

      await a.read(alarmRuleProvider.notifier).upsert(rule);
      await _flush();
      expect(
        b.read(alarmRuleProvider).any((r) => r.id == rule.id),
        isTrue,
      );

      final renamed = rule.copyWith(
        name: 'Depth Watch Updated',
        updatedAt: now.add(const Duration(seconds: 1)),
      );
      await a.read(alarmRuleProvider.notifier).upsert(renamed);
      await _flush();
      final fromB = b.read(alarmRuleProvider).firstWhere((r) => r.id == rule.id);
      expect(fromB.name, 'Depth Watch Updated');

      await a.read(alarmRuleProvider.notifier).delete(rule.id);
      await _flush();
      final deleted = b.read(alarmRuleProvider).firstWhere((r) => r.id == rule.id);
      expect(deleted.deleted, isTrue);
    });
  });
}

