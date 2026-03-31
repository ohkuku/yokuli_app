import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/home/views/home_screen.dart';
import '../features/dashboard/views/dashboard_screen.dart';
import '../features/signalk/views/signalk_screen.dart';
import '../features/power/views/power_screen.dart';
import '../features/logbook/views/log_screen.dart';
import '../features/settings/views/settings_screen.dart';
import '../features/ais/views/ais_screen.dart';
import '../features/voyage/views/voyage_screen.dart';
import '../features/kanban/views/kanban_screen.dart';
import '../features/notifications/views/notifications_screen.dart';
import '../features/alarm_center/views/alarm_center_screen.dart';
import '../features/alarm_center/views/alarm_rule_edit_screen.dart';
import '../core/models/alarm_rule.dart';
import '../features/voyage/views/voyage_detail_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        name: 'dashboard',
        pageBuilder: (context, state) => _slidePage(state, const DashboardScreen()),
      ),
      GoRoute(
        path: '/signalk',
        name: 'signalk',
        pageBuilder: (context, state) => _slidePage(state, const SignalKScreen()),
      ),
      GoRoute(
        path: '/power',
        name: 'power',
        pageBuilder: (context, state) => _slidePage(state, const PowerScreen()),
      ),
      GoRoute(
        path: '/log',
        name: 'log',
        pageBuilder: (context, state) => _slidePage(state, const LogScreen()),
      ),
      GoRoute(
        path: '/ais',
        name: 'ais',
        pageBuilder: (context, state) => _slidePage(state, const AisScreen()),
      ),
      GoRoute(
        path: '/voyage',
        name: 'voyage',
        pageBuilder: (context, state) => _slidePage(state, const VoyageScreen()),
      ),
      GoRoute(
        path: '/kanban',
        name: 'kanban',
        pageBuilder: (context, state) => _slidePage(state, const KanbanScreen()),
      ),
      GoRoute(
        path: '/alarm-center',
        name: 'alarm-center',
        pageBuilder: (context, state) => _slidePage(state, const AlarmCenterScreen()),
      ),
      GoRoute(
        path: '/alarm-rule-edit',
        name: 'alarm-rule-edit',
        pageBuilder: (context, state) {
          final extra = state.extra as AlarmRule?;
          return _slidePage(state, AlarmRuleEditScreen(existing: extra));
        },
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        pageBuilder: (context, state) => _slidePage(state, const SettingsScreen()),
      ),
      GoRoute(
        path: '/notifications',
        name: 'notifications',
        pageBuilder: (context, state) =>
            _slidePage(state, const NotificationsScreen()),
      ),
      GoRoute(
        path: '/voyage/:id',
        name: 'voyage-detail',
        pageBuilder: (context, state) => _slidePage(
            state,
            VoyageDetailScreen(
                voyageId: state.pathParameters['id']!)),
      ),
    ],
  );
});

CustomTransitionPage<void> _slidePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}
