import 'api_service.dart';
import 'storage_service.dart';
import '../models/user.dart';

class AuthService {
  final ApiService _api = ApiService();
  final StorageService _storage = StorageService();

  Future<User> login(String email, String password) async {
    final response = await _api.post('/auth/login', data: {
      'email': email,
      'password': password,
    });

    final token = response.data['access_token'] as String;
    await _storage.saveToken(token);

    // Fetch user profile with the token
    final userResponse = await _api.get('/users/me');
    final user = User.fromJson(userResponse.data);
    await _storage.saveUserId(user.id);

    return user;
  }

  Future<User> signup({
    required String name,
    required String email,
    required String password,
    String phone = '',
    List<String> interests = const [],
    String role = 'customer',
  }) async {
    final response = await _api.post('/auth/signup', data: {
      'name': name,
      'email': email,
      'password': password,
      'phone': phone,
      'interests': interests,
      'role': role,
    });

    final token = response.data['access_token'] as String;
    await _storage.saveToken(token);

    // Fetch user profile with the token
    final userResponse = await _api.get('/users/me');
    final user = User.fromJson(userResponse.data);
    await _storage.saveUserId(user.id);

    return user;
  }

  Future<void> logout() async {
    await _storage.clearAll();
  }

  Future<String?> getToken() async {
    return await _storage.getToken();
  }

  Future<bool> isLoggedIn() async {
    final token = await _storage.getToken();
    return token != null && token.isNotEmpty;
  }

  Future<User> getCurrentUser() async {
    final response = await _api.get('/users/me');
    return User.fromJson(response.data);
  }

  Future<User> updateProfile({
    String? bio,
    List<String>? interests,
    String? profileImageUrl,
  }) async {
    final data = <String, dynamic>{};
    if (bio != null) data['bio'] = bio;
    if (interests != null) data['interests'] = interests;
    if (profileImageUrl != null) data['profile_image_url'] = profileImageUrl;

    final response = await _api.put('/users/me', data: data);
    return User.fromJson(response.data);
  }
}
