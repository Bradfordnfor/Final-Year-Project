import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/auth_controller.dart';
import '../controllers/notification_controller.dart';
import '../routes.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _destinations = [
    _Dest(icon: Icons.dashboard_outlined, label: 'Dashboard', route: AppRoutes.dashboard),
    _Dest(icon: Icons.calendar_month_outlined, label: 'Timetable', route: AppRoutes.timetable),
    _Dest(icon: Icons.auto_fix_high_outlined, label: 'Generation', route: AppRoutes.generation),
    _Dest(icon: Icons.warning_amber_outlined, label: 'Conflicts', route: AppRoutes.conflicts),
    _Dest(icon: Icons.bar_chart_outlined, label: 'Analytics', route: AppRoutes.analytics),
    _Dest(icon: Icons.manage_accounts_outlined, label: 'Management', route: AppRoutes.management),
  ];

  int _selectedIndex(String route) {
    final idx = _destinations.indexWhere((d) => d.route == route);
    return idx < 0 ? 0 : idx;
  }

  void _navigate(String route) => Get.offAllNamed(route);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final currentRoute = Get.currentRoute;
    final selected = _selectedIndex(currentRoute);

    if (width >= 1200) {
      return _SidebarLayout(
        destinations: _destinations,
        selected: selected,
        onNav: _navigate,
        child: child,
      );
    } else if (width >= 800) {
      return _RailLayout(
        destinations: _destinations,
        selected: selected,
        onNav: _navigate,
        child: child,
      );
    } else {
      return _BottomNavLayout(
        destinations: _destinations,
        selected: selected,
        onNav: _navigate,
        child: child,
      );
    }
  }
}

// ── Sidebar (≥1200 px) ────────────────────────────────────────────────────────

class _SidebarLayout extends StatelessWidget {
  final List<_Dest> destinations;
  final int selected;
  final void Function(String) onNav;
  final Widget child;

  const _SidebarLayout({
    required this.destinations,
    required this.selected,
    required this.onNav,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          NavigationDrawer(
            selectedIndex: selected,
            onDestinationSelected: (i) => onNav(destinations[i].route),
            children: [
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'UB Timetabling',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              ...destinations.map(
                (d) => NavigationDrawerDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label),
                ),
              ),
              const Divider(),
              _NotificationTile(),
              const _LogoutTile(),
            ],
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ── NavigationRail (800–1200 px) ─────────────────────────────────────────────

class _RailLayout extends StatelessWidget {
  final List<_Dest> destinations;
  final int selected;
  final void Function(String) onNav;
  final Widget child;

  const _RailLayout({
    required this.destinations,
    required this.selected,
    required this.onNav,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selected,
            onDestinationSelected: (i) => onNav(destinations[i].route),
            labelType: NavigationRailLabelType.selected,
            leading: _NotificationBadgeIcon(),
            trailing: const Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: _LogoutTile(iconOnly: true),
                ),
              ),
            ),
            destinations: destinations
                .map((d) => NavigationRailDestination(
                      icon: Icon(d.icon),
                      label: Text(d.label),
                    ))
                .toList(),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ── BottomNavigationBar (<800 px) ─────────────────────────────────────────────

class _BottomNavLayout extends StatelessWidget {
  final List<_Dest> destinations;
  final int selected;
  final void Function(String) onNav;
  final Widget child;

  const _BottomNavLayout({
    required this.destinations,
    required this.selected,
    required this.onNav,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UB Timetabling'),
        actions: [
          _NotificationBadgeIcon(),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => AuthController.to.logout(),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (i) => onNav(destinations[i].route),
        destinations: destinations
            .map((d) => NavigationDestination(
                  icon: Icon(d.icon),
                  label: d.label,
                ))
            .toList(),
      ),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _NotificationBadgeIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ctrl = NotificationController.to;
    return Obx(() {
      final count = ctrl.unreadCountValue;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Get.offAllNamed(AppRoutes.notifications),
            tooltip: 'Notifications',
          ),
          if (count > 0)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  count > 9 ? '9+' : '$count',
                  style: const TextStyle(color: Colors.white, fontSize: 9),
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _NotificationTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ctrl = NotificationController.to;
    return Obx(() {
      final count = ctrl.unreadCountValue;
      return ListTile(
        leading: Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          child: const Icon(Icons.notifications_outlined),
        ),
        title: const Text('Notifications'),
        onTap: () => Get.offAllNamed(AppRoutes.notifications),
      );
    });
  }
}

class _LogoutTile extends StatelessWidget {
  final bool iconOnly;
  const _LogoutTile({this.iconOnly = false});

  @override
  Widget build(BuildContext context) {
    if (iconOnly) {
      return IconButton(
        icon: const Icon(Icons.logout),
        onPressed: () => AuthController.to.logout(),
        tooltip: 'Logout',
      );
    }
    return ListTile(
      leading: const Icon(Icons.logout),
      title: const Text('Logout'),
      onTap: () => AuthController.to.logout(),
    );
  }
}

// ── Data class ────────────────────────────────────────────────────────────────

class _Dest {
  final IconData icon;
  final String label;
  final String route;
  const _Dest({required this.icon, required this.label, required this.route});
}
