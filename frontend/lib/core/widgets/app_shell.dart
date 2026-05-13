import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/auth_controller.dart';
import '../controllers/notification_controller.dart';
import '../models/user.dart';
import '../routes.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  // Primary items (main nav bar / rail) — role-filtered in build
  static final _primary = [
    _Dest(
      icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard,
      label: 'Dashboard', route: AppRoutes.dashboard,
    ),
    _Dest(
      icon: Icons.calendar_month_outlined, activeIcon: Icons.calendar_month,
      label: 'Timetable', route: AppRoutes.timetable,
      visible: (u) => !u.isStudent,
    ),
    _Dest(
      icon: Icons.auto_fix_high_outlined, activeIcon: Icons.auto_fix_high,
      label: 'Generate', route: AppRoutes.generation,
      visible: (u) => u.canManageTimetable,
    ),
    _Dest(
      icon: Icons.manage_accounts_outlined, activeIcon: Icons.manage_accounts,
      label: 'Manage', route: AppRoutes.management,
      visible: (u) => u.canManageUniversity || u.isLecturer,
    ),
  ];

  // Secondary items (sidebar Tools section / More drawer) — role-filtered in build
  static final _secondary = [
    _Dest(
      icon: Icons.school_outlined, activeIcon: Icons.school,
      label: 'Faculty Setup', route: AppRoutes.facultySetup,
      visible: (u) => u.canSetupFaculty,
    ),
    _Dest(
      icon: Icons.warning_amber_outlined, activeIcon: Icons.warning_amber,
      label: 'Conflicts', route: AppRoutes.conflicts,
      visible: (u) => u.canManageTimetable,
    ),
    _Dest(
      icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart,
      label: 'Analytics', route: AppRoutes.analytics,
      visible: (u) => u.canManageTimetable || u.canManageUniversity,
    ),
    _Dest(
      icon: Icons.notifications_outlined, activeIcon: Icons.notifications,
      label: 'Notifications', route: AppRoutes.notifications,
    ),
    _Dest(
      icon: Icons.upload_file_outlined, activeIcon: Icons.upload_file,
      label: 'Bulk Import', route: AppRoutes.bulkImport,
      visible: (u) => u.canManageUniversity,
    ),
    _Dest(
      icon: Icons.public_outlined, activeIcon: Icons.public,
      label: 'Public View', route: AppRoutes.publicTimetable,
    ),
  ];

  int _selectedIndex(String route, List<_Dest> all) {
    final idx = all.indexWhere((d) => d.route == route);
    return idx < 0 ? 0 : idx;
  }

  void _navigate(String route) => Get.offAllNamed(route);

  @override
  Widget build(BuildContext context) {
    final user = AuthController.to.user.value;
    final filteredPrimary = user == null
        ? _primary
        : _primary.where((d) => d.visible(user)).toList();
    final filteredSecondary = user == null
        ? _secondary
        : _secondary.where((d) => d.visible(user)).toList();

    final width = MediaQuery.of(context).size.width;
    final currentRoute = Get.currentRoute;
    final allVisible = [...filteredPrimary, ...filteredSecondary];
    final selected = _selectedIndex(currentRoute, allVisible);

    if (width >= 1100) {
      return _SidebarLayout(
        primary: filteredPrimary,
        secondary: filteredSecondary,
        selected: selected,
        onNav: _navigate,
        child: child,
      );
    } else if (width >= 720) {
      return _RailLayout(
        destinations: allVisible,
        selected: selected,
        onNav: _navigate,
        child: child,
      );
    } else {
      return _BottomNavLayout(
        primary: filteredPrimary,
        secondary: filteredSecondary,
        selected: selected,
        onNav: _navigate,
        child: child,
      );
    }
  }
}

// ── Sidebar (≥1100 px) ────────────────────────────────────────────────────────

class _SidebarLayout extends StatelessWidget {
  final List<_Dest> primary;
  final List<_Dest> secondary;
  final int selected;
  final void Function(String) onNav;
  final Widget child;

  const _SidebarLayout({
    required this.primary, required this.secondary,
    required this.selected, required this.onNav, required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final allDests = [...primary, ...secondary];

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 260,
            child: Material(
              color: cs.surfaceContainer,
              child: Column(
                children: [
                  // Logo / app name
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
                    child: Row(
                      children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.school, color: cs.onPrimary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('TimeTable', style: tt.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface,
                              )),
                              Text('University of Buea', style: tt.labelSmall?.copyWith(
                                color: cs.outline,
                              )),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: cs.outlineVariant, height: 1),
                  const SizedBox(height: 8),
                  const _SectionLabel('Main'),
                  ...primary.map((d) => _SidebarItem(
                    dest: d,
                    isSelected: allDests.indexOf(d) == selected,
                    onTap: () => onNav(d.route),
                  )),
                  if (secondary.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const _SectionLabel('Tools'),
                    ...secondary.map((d) => _SidebarItem(
                      dest: d,
                      isSelected: allDests.indexOf(d) == selected,
                      onTap: () => onNav(d.route),
                    )),
                  ],
                  const Spacer(),
                  Divider(color: cs.outlineVariant, height: 1),
                  _NotificationTile(),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Logout'),
                    onTap: () => AuthController.to.logout(),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          VerticalDivider(color: cs.outlineVariant, width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.outline,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final _Dest dest;
  final bool isSelected;
  final VoidCallback onTap;
  const _SidebarItem({required this.dest, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Material(
        color: isSelected ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  isSelected ? dest.activeIcon : dest.icon,
                  size: 20,
                  color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 14),
                Text(
                  dest.label,
                  style: TextStyle(
                    color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── NavigationRail (720–1100 px) ─────────────────────────────────────────────

class _RailLayout extends StatelessWidget {
  final List<_Dest> destinations;
  final int selected;
  final void Function(String) onNav;
  final Widget child;

  const _RailLayout({
    required this.destinations, required this.selected,
    required this.onNav, required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: cs.surfaceContainer,
            selectedIndex: selected.clamp(0, destinations.length - 1),
            onDestinationSelected: (i) => onNav(destinations[i].route),
            labelType: NavigationRailLabelType.selected,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _NotificationBadgeIcon(),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    icon: const Icon(Icons.logout),
                    onPressed: () => AuthController.to.logout(),
                    tooltip: 'Logout',
                  ),
                ),
              ),
            ),
            destinations: destinations
                .map((d) => NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.activeIcon),
                      label: Text(d.label),
                    ))
                .toList(),
          ),
          VerticalDivider(color: cs.outlineVariant, width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ── BottomNavigationBar (<720 px) — max 4 primary + More ─────────────────────

class _BottomNavLayout extends StatelessWidget {
  final List<_Dest> primary;
  final List<_Dest> secondary;
  final int selected;
  final void Function(String) onNav;
  final Widget child;

  const _BottomNavLayout({
    required this.primary, required this.secondary,
    required this.selected, required this.onNav, required this.child,
  });

  int get _bottomSelected {
    if (selected < primary.length) return selected;
    return primary.length; // "More" tab
  }

  void _openMore(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ...secondary.map((d) => ListTile(
              leading: Icon(d.icon),
              title: Text(d.label),
              onTap: () {
                Navigator.pop(context);
                onNav(d.route);
              },
            )),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () => AuthController.to.logout(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.school, color: Theme.of(context).colorScheme.primary, size: 22),
            const SizedBox(width: 8),
            const Text('UB Timetabling'),
          ],
        ),
        actions: [
          _NotificationBadgeIcon(),
        ],
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _bottomSelected,
        onDestinationSelected: (i) {
          if (i < primary.length) {
            onNav(primary[i].route);
          } else {
            _openMore(context);
          }
        },
        destinations: [
          ...primary.map((d) => NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.activeIcon),
                label: d.label,
              )),
          const NavigationDestination(
            icon: Icon(Icons.more_horiz_outlined),
            selectedIcon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
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
              right: 4, top: 4,
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

// ── Data class ────────────────────────────────────────────────────────────────

class _Dest {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;
  final bool Function(UserModel) visible;

  _Dest({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
    bool Function(UserModel)? visible,
  }) : visible = visible ?? _always;

  static bool _always(UserModel _) => true;
}
