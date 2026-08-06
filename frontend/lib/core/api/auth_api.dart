import '../models/user.dart';
import 'api_client.dart';

class AuthApi {
  final ApiClient _client;
  AuthApi(this._client);

  Future<TokenResponse> login(String email, String password) async {
    final response = await _client.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    return TokenResponse.fromJson(response.data as Map<String, dynamic>);
  }

  Future<UserModel> getMe() async {
    final response = await _client.get('/auth/me');
    return UserModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Sets the password for a pending account via an activation token and logs
  /// the user in. Returns the same token/user shape as `/auth/login`.
  Future<TokenResponse> activate(String token, String newPassword) async {
    final response = await _client.post('/auth/activate', data: {
      'token': token,
      'new_password': newPassword,
    });
    return TokenResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// Confirms an email-change token, switching the account to the new address.
  Future<void> confirmEmail(String token) async {
    await _client.post('/auth/confirm-email', data: {'token': token});
  }

  /// Requests a fresh activation email for a pending account. The backend
  /// always responds generically, so callers must not reveal whether the
  /// account exists.
  Future<void> resendActivation(String email) async {
    await _client.post('/auth/resend-activation', data: {'email': email});
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
    await _client.post('/auth/change-password', data: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  /// Requests an email change. The backend emails a confirmation link to the
  /// new address and does NOT switch the account email until it is confirmed.
  /// Returns the pending (new) address for display.
  Future<String> changeEmail(String email) async {
    final response =
        await _client.post('/auth/change-email', data: {'email': email});
    return (response.data as Map<String, dynamic>)['pending_email'] as String;
  }
}
