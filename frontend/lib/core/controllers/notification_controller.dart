import 'package:get/get.dart';

import '../api/api_client.dart';
import '../api/timetable_api.dart';
import '../models/timetable.dart';
import 'auth_controller.dart';

class NotificationController extends GetxController {
  static NotificationController get to => Get.find();

  final RxList<AppNotification> notifications = <AppNotification>[].obs;
  final RxBool isLoading = false.obs;

  RxInt get unreadCount =>
      notifications.where((n) => !n.isRead).length.obs;

  TimetableApi get _api =>
      TimetableApi(ApiClient(token: AuthController.to.token));

  @override
  void onInit() {
    super.onInit();
    fetchNotifications();
  }

  Future<void> fetchNotifications() async {
    if (AuthController.to.token == null) return;
    isLoading.value = true;
    try {
      notifications.value = await _api.getMyNotifications();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> markRead(int notificationId) async {
    await _api.markNotificationRead(notificationId);
    final idx = notifications.indexWhere((n) => n.id == notificationId);
    if (idx != -1) {
      final n = notifications[idx];
      notifications[idx] = AppNotification(
        id: n.id,
        message: n.message,
        notificationType: n.notificationType,
        isRead: true,
        createdAt: n.createdAt,
      );
    }
  }

  Future<void> markAllRead() async {
    final unread = notifications.where((n) => !n.isRead).toList();
    await Future.wait(unread.map((n) => markRead(n.id)));
  }

  int get unreadCountValue => notifications.where((n) => !n.isRead).length;
}
