import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
    );
  }
}
