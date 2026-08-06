import 'package:dio/dio.dart';
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

  /// True when the last login attempt failed because the email is unverified,
  /// so the UI can offer a "resend activation" action.
  final RxBool needsActivation = false.obs;
  String _lastLoginEmail = '';

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
    needsActivation.value = false;
    _lastLoginEmail = email;
    try {
      final result = await AuthApi(ApiClient()).login(email, password);
      await applyToken(result);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final detail = (e.response?.data as Map?)?['detail'] as String?;
      if (code == 403) {
        needsActivation.value = detail?.toLowerCase().contains('not verified') ?? false;
        errorMessage.value = detail ??
            'Email not verified. Check your inbox or request a new activation link.';
      } else if (code == 401) {
        errorMessage.value = 'Invalid email or password.';
      } else {
        errorMessage.value = detail ?? 'An error occurred. Please try again.';
      }
    } catch (_) {
      errorMessage.value = 'Cannot reach server. Check your connection.';
    } finally {
      isLoading.value = false;
    }
  }

  /// Resends the activation email to the last email a login was attempted with.
  /// Always shows a generic message — never reveals whether the account exists.
  Future<void> resendActivation() async {
    if (_lastLoginEmail.isEmpty) return;
    try {
      await AuthApi(ApiClient()).resendActivation(_lastLoginEmail);
    } catch (_) {
      // Ignore — the generic message below must not leak backend state.
    }
    Get.snackbar(
      'Check your inbox',
      "If that account exists, we've sent a new activation link.",
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
    );
  }

  /// Stores a successful token/user (from login or activation), persists the
  /// token, and routes to the landing screen for the user's role.
  Future<void> applyToken(TokenResponse result) async {
    _token = result.accessToken;
    await _storage.write(key: _tokenKey, value: _token);
    user.value = result.user;
    Get.offAllNamed(
      result.user.isSuperAdmin ? AppRoutes.universities : AppRoutes.dashboard,
    );
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    _token = null;
    user.value = null;
    Get.offAllNamed(AppRoutes.login);
  }

  String? get token => _token;
}
