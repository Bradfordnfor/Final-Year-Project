import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'core/controllers/auth_controller.dart';
import 'core/controllers/notification_controller.dart';
import 'core/controllers/timetable_controller.dart';
import 'core/routes.dart';
import 'core/theme.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'UB Timetabling',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      initialRoute: AppRoutes.login,
      getPages: AppRoutes.pages,
      initialBinding: BindingsBuilder(() {
        Get.put(AuthController());
        Get.put(TimetableController());
        Get.put(NotificationController());
      }),
    );
  }
}
