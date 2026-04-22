import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';

import '../../core/controllers/notification_controller.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _ctrl = NotificationController.to;

  @override
  void initState() {
    super.initState();
    _ctrl.fetchNotifications();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (_ctrl.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }

      if (_ctrl.notifications.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.notifications_none, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text('No notifications yet',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.grey)),
            ],
          ).animate().fadeIn(duration: 300.ms),
        );
      }

      final unread = _ctrl.unreadCountValue;

      return Column(
        children: [
          if (unread > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Text('$unread unread',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(
                    onPressed: _ctrl.markAllRead,
                    child: const Text('Mark all read'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _ctrl.notifications.length,
              itemBuilder: (_, i) {
                final n = _ctrl.notifications[i];
                return ListTile(
                  leading: Icon(
                    n.isRead
                        ? Icons.notifications_none
                        : Icons.notifications_active,
                    color: n.isRead
                        ? Colors.grey
                        : Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    n.message,
                    style: TextStyle(
                        fontWeight:
                            n.isRead ? FontWeight.normal : FontWeight.w600),
                  ),
                  subtitle: Text(
                    n.notificationType.replaceAll('_', ' '),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Text(
                    _formatDate(n.createdAt),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  tileColor: n.isRead ? null : Colors.blue.shade50,
                  onTap: () {
                    if (!n.isRead) _ctrl.markRead(n.id);
                  },
                )
                    .animate(delay: Duration(milliseconds: i * 40))
                    .fadeIn(duration: 200.ms)
                    .slideX(begin: 0.05, end: 0, curve: Curves.easeOut);
              },
            ),
          ),
        ],
      );
    });
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
