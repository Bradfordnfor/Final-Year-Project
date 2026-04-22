import 'package:get/get.dart';
import '../features/auth/login_screen.dart';

class AppRoutes {
  static const login = '/login';

  static final pages = [
    GetPage(name: login, page: () => const LoginScreen()),
  ];
}
