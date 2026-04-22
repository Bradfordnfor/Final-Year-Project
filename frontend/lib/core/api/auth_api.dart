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
}
