import 'package:get/get.dart';

import '../features/analytics/analytics_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/conflicts/conflicts_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/faculty_setup/faculty_setup_screen.dart';
import '../features/generation/generation_screen.dart';
import '../features/management/management_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/public_timetable/public_timetable_screen.dart';
import '../features/bulk_import/bulk_import_screen.dart';
import '../features/bulk_import/course_bulk_import_screen.dart';
import '../features/timetable/timetable_screen.dart';
import '../features/universities/universities_screen.dart';
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
  static const facultySetup = '/faculty-setup';
  static const publicTimetable = '/public';
  static const bulkImport = '/bulk-import';
  static const courseBulkImport = '/course-bulk-import';
  static const universities = '/universities';

  static final pages = [
    GetPage(name: login, page: () => const LoginScreen()),
    GetPage(name: dashboard, page: () => const AppShell(child: DashboardScreen())),
    GetPage(name: timetable, page: () => const AppShell(child: TimetableScreen())),
    GetPage(name: generation, page: () => const AppShell(child: GenerationScreen())),
    GetPage(name: conflicts, page: () => const AppShell(child: ConflictsScreen())),
    GetPage(name: notifications, page: () => const AppShell(child: NotificationsScreen())),
    GetPage(name: analytics, page: () => const AppShell(child: AnalyticsScreen())),
    GetPage(name: management, page: () => const AppShell(child: ManagementScreen())),
    GetPage(name: facultySetup, page: () => const AppShell(child: FacultySetupScreen())),
    GetPage(name: publicTimetable, page: () => const PublicTimetableScreen()),
    GetPage(name: bulkImport, page: () => const AppShell(child: BulkImportScreen())),
    GetPage(name: courseBulkImport, page: () => const AppShell(child: CourseBulkImportScreen())),
    GetPage(name: universities, page: () => const AppShell(child: UniversitiesScreen())),
  ];
}
