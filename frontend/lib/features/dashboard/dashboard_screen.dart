import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/constants.dart';
import '../../core/controllers/auth_controller.dart';
import '../../core/controllers/notification_controller.dart';
import '../../core/controllers/timetable_controller.dart';
import '../../core/routes.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    TimetableController.to.fetchRuns();
    NotificationController.to.fetchNotifications();
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthController.to.user.value;
    if (user == null) return const SizedBox.shrink();

    final roleLabel =
        AppConstants.roleLabels[user.role] ?? user.role;

    return Obx(() {
      final timetables = TimetableController.to.runs;
      final unread = NotificationController.to.unreadCountValue;

      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Greeting
          Text(
            'Welcome, ${user.fullName}',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            roleLabel,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 24),

          // Stats row
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _StatCard(
                icon: Icons.calendar_month_outlined,
                label: user.isStudent ? 'Published Timetables' : 'Timetable Runs',
                value: '${timetables.length}',
                color: Theme.of(context).colorScheme.primary,
                onTap: user.isStudent
                    ? () => Get.offAllNamed(AppRoutes.publicTimetable)
                    : () => Get.offAllNamed(AppRoutes.timetable),
              ),
              _StatCard(
                icon: Icons.notifications_outlined,
                label: 'Unread Notifications',
                value: '$unread',
                color: unread > 0
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.secondary,
                onTap: () => Get.offAllNamed(AppRoutes.notifications),
              ),
              if (user.canManageTimetable && timetables.isNotEmpty)
                _StatCard(
                  icon: Icons.warning_amber_outlined,
                  label: 'Conflicts',
                  value: '${TimetableController.to.conflicts.length}',
                  color: Theme.of(context).colorScheme.tertiary,
                  onTap: () => Get.offAllNamed(AppRoutes.conflicts),
                ),
            ],
          ),
          const SizedBox(height: 32),

          // Quick actions — only for users who can manage timetables
          if (user.canManageTimetable) ...[
            Text(
              'Quick Actions',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ActionChip(
                  icon: Icons.add,
                  label: 'New Timetable',
                  onTap: () => Get.offAllNamed(AppRoutes.timetable),
                ),
                _ActionChip(
                  icon: Icons.auto_fix_high_outlined,
                  label: 'Generate',
                  onTap: () => Get.offAllNamed(AppRoutes.timetable),
                ),
                _ActionChip(
                  icon: Icons.bar_chart_outlined,
                  label: 'Analytics',
                  onTap: () => Get.offAllNamed(AppRoutes.analytics),
                ),
                if (user.canManageUniversity)
                  _ActionChip(
                    icon: Icons.manage_accounts_outlined,
                    label: 'Management',
                    onTap: () => Get.offAllNamed(AppRoutes.management),
                  ),
              ],
            ),
            const SizedBox(height: 32),
          ],

          // Recent timetables
          if (timetables.isNotEmpty) ...[
            Text(
              user.isStudent ? 'Published Timetables' : 'Recent Timetables',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ...timetables.take(5).map(
                  (t) => Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.calendar_month_outlined,
                        color: _statusColor(context, t.status),
                      ),
                      title: Text(t.name),
                      subtitle: Text(
                          '${t.facultyIds.length} facult${t.facultyIds.length == 1 ? 'y' : 'ies'}'),
                      trailing: user.isStudent ? null : _StatusBadge(t.status),
                      onTap: () {
                        TimetableController.to.selectRun(t.id);
                        Get.offAllNamed(user.isStudent
                            ? AppRoutes.publicTimetable
                            : AppRoutes.timetable);
                      },
                    ),
                  ),
                ),
          ],
        ],
      );
    });
  }

  Color _statusColor(BuildContext context, String status) {
    final cs = Theme.of(context).colorScheme;
    return switch (status) {
      'published' => Colors.green,
      'approved' => cs.primary,
      'under_review' => cs.secondary,
      _ => cs.outline,
    };
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionChip(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'published' => Colors.green,
      'approved' => Theme.of(context).colorScheme.primary,
      'under_review' => Theme.of(context).colorScheme.secondary,
      _ => Theme.of(context).colorScheme.outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
