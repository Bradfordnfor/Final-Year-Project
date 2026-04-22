import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

import '../api/api_client.dart';
import '../api/auth_api.dart';
import '../models/user.dart';
import '../routes.dart';

class AuthController extends GetxController {
  static AuthController get to => Get.find();

  final _storage = const FlutterSecureStorage();
  static const _tokenKey = 'auth_token';

  final Rx<UserModel?> user = Rx<UserModel?>(null);
  final RxBool isLoading = false.obs;
  final RxString errorMessage = ''.obs;

  bool get isLoggedIn => user.value != null;

  String? _token;

  @override
  void onInit() {
    super.onInit();
    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    _token = await _storage.read(key: _tokenKey);
    if (_token == null) return;
    try {
      final me = await AuthApi(ApiClient(token: _token)).getMe();
      user.value = me;
    } catch (_) {
      await _storage.delete(key: _tokenKey);
      _token = null;
    }
  }

  Future<void> login(String email, String password) async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final result = await AuthApi(ApiClient()).login(email, password);
      _token = result.accessToken;
      await _storage.write(key: _tokenKey, value: _token);
      user.value = result.user;
      Get.offAllNamed(AppRoutes.dashboard);
    } on Exception catch (e) {
      errorMessage.value = _extractMessage(e);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    _token = null;
    user.value = null;
    Get.offAllNamed(AppRoutes.login);
  }

  String? get token => _token;

  String _extractMessage(Exception e) {
    final msg = e.toString();
    if (msg.contains('401') || msg.contains('Unauthorized')) {
      return 'Invalid email or password.';
    }
    if (msg.contains('SocketException') || msg.contains('connection')) {
      return 'Cannot reach server. Check your connection.';
    }
    return 'An error occurred. Please try again.';
  }
}
