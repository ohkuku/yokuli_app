import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/home/views/home_screen.dart';
import '../features/dashboard/views/dashboard_screen.dart';
import '../features/signalk/views/signalk_screen.dart';
import '../features/power/views/power_screen.dart';
import '../features/logbook/views/logbook_screen.dart';
import '../features/logbook/views/log_screen.dart';
import '../features/safety/views/safety_screen.dart';
import '../features/maintenance/views/maintenance_screen.dart';
import '../features/settings/views/settings_screen.dart';
import '../features/ais/views/ais_screen.dart';
import '../features/voyage/views/voyage_screen.dart';
import '../features/tasks/views/tasks_screen.dart';
import '../features/issues/views/issues_screen.dart';

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
        builder: (context, state) => const DashboardScreen(),
        pageBuilder: (context, state) => _slidePage(state, const DashboardScreen()),
      ),
      GoRoute(
        path: '/signalk',
        name: 'signalk',
        builder: (context, state) => const SignalKScreen(),
        pageBuilder: (context, state) => _slidePage(state, const SignalKScreen()),
      ),
      GoRoute(
        path: '/power',
        name: 'power',
        builder: (context, state) => const PowerScreen(),
        pageBuilder: (context, state) => _slidePage(state, const PowerScreen()),
      ),
      GoRoute(
        path: '/logbook',
        name: 'logbook',
        builder: (context, state) => const LogbookScreen(),
        pageBuilder: (context, state) => _slidePage(state, const LogbookScreen()),
      ),
      GoRoute(
        path: '/log',
        name: 'log',
        builder: (context, state) => const LogScreen(),
        pageBuilder: (context, state) => _slidePage(state, const LogScreen()),
      ),
      GoRoute(
        path: '/ais',
        name: 'ais',
        builder: (context, state) => const AisScreen(),
        pageBuilder: (context, state) => _slidePage(state, const AisScreen()),
      ),
      GoRoute(
        path: '/voyage',
        name: 'voyage',
        builder: (context, state) => const VoyageScreen(),
        pageBuilder: (context, state) => _slidePage(state, const VoyageScreen()),
      ),
      GoRoute(
        path: '/tasks',
        name: 'tasks',
        builder: (context, state) => const TasksScreen(),
        pageBuilder: (context, state) => _slidePage(state, const TasksScreen()),
      ),
      GoRoute(
        path: '/issues',
        name: 'issues',
        builder: (context, state) => const IssuesScreen(),
        pageBuilder: (context, state) => _slidePage(state, const IssuesScreen()),
      ),
      GoRoute(
        path: '/safety',
        name: 'safety',
        builder: (context, state) => const SafetyScreen(),
        pageBuilder: (context, state) => _slidePage(state, const SafetyScreen()),
      ),
      GoRoute(
        path: '/maintenance',
        name: 'maintenance',
        builder: (context, state) => const MaintenanceScreen(),
        pageBuilder: (context, state) => _slidePage(state, const MaintenanceScreen()),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
        pageBuilder: (context, state) => _slidePage(state, const SettingsScreen()),
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
