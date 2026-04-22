import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../features/auth/login_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/timetable/timetable_screen.dart';
import 'widgets/app_shell.dart';

class AppRoutes {
  static const login = '/login';
  static const dashboard = '/dashboard';
  static const timetable = '/timetable';
  static const generation = '/generation';
  static const conflicts = '/conflicts';
  static const notifications = '/notifications';
  static const analytics = '/analytics';
  static const management = '/management';

  static final pages = [
    GetPage(name: login, page: () => const LoginScreen()),
    GetPage(
      name: dashboard,
      page: () => const AppShell(child: DashboardScreen()),
    ),
    GetPage(
      name: timetable,
      page: () => const AppShell(child: TimetableScreen()),
    ),
    GetPage(
      name: generation,
      page: () => const AppShell(child: _Placeholder('Generation')),
    ),
    GetPage(
      name: conflicts,
      page: () => const AppShell(child: _Placeholder('Conflicts')),
    ),
    GetPage(
      name: notifications,
      page: () => const AppShell(child: _Placeholder('Notifications')),
    ),
    GetPage(
      name: analytics,
      page: () => const AppShell(child: _Placeholder('Analytics')),
    ),
    GetPage(
      name: management,
      page: () => const AppShell(child: _Placeholder('Management')),
    ),
  ];
}

class _Placeholder extends StatelessWidget {
  final String title;
  const _Placeholder(this.title);

  @override
  Widget build(BuildContext context) => Center(
        child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
      );
}
