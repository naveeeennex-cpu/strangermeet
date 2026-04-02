import 'package:google_sign_in/google_sign_in.dart';

import 'api_service.dart';
import 'storage_service.dart';
import '../models/user.dart';

class AuthService {
  final ApiService _api = ApiService();
  final StorageService _storage = StorageService();

  static final _googleSignIn = GoogleSignIn(
    serverClientId:
        '610696728606-hjv0463opi1e5umn1nas2e3589ss9dqv.apps.googleusercontent.com',
  );

  // ── Email / password ────────────────────────────────────────────────────────

  Future<User> login(String email, String password) async {
    final response = await _api.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    final token = response.data['access_token'] as String;
    await _storage.saveToken(token);
    final userResponse = await _api.get('/users/me');
    final user = User.fromJson(userResponse.data);
    await _storage.saveUserId(user.id);
    return user;
  }

  Future<User> signup({
    required String name,
    required String email,
    String? password,
    required String username,
    String phone = '',
    List<String> interests = const [],
    String role = 'customer',
    String occupation = '',
    String collegeName = '',
    String companyName = '',
    String designation = '',
    String googleId = '',
    String profileImageUrl = '',
  }) async {
    final response = await _api.post('/auth/signup', data: {
      'name': name,
      'email': email,
      if (password != null) 'password': password,
      'username': username,
      'phone': phone,
      'interests': interests,
      'role': role,
      'occupation': occupation,
      'college_name': collegeName,
      'company_name': companyName,
      'designation': designation,
      'google_id': googleId,
      'profile_image_url': profileImageUrl,
    });
    final token = response.data['access_token'] as String;
    await _storage.saveToken(token);
    final userResponse = await _api.get('/users/me');
    final user = User.fromJson(userResponse.data);
    await _storage.saveUserId(user.id);
    return user;
  }

  // ── Google Sign-In ──────────────────────────────────────────────────────────

  /// Returns either:
  /// - `{'user': User}` for existing users (already logged in + token saved)
  /// - `{'is_new_user': true, 'google_id': ..., 'email': ..., 'name': ..., 'picture': ...}`
  ///   for new users who need to complete onboarding
  Future<Map<String, dynamic>> signInWithGoogle() async {
    final account = await _googleSignIn.signIn();
    if (account == null) throw Exception('Google sign-in cancelled');

    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) throw Exception('Could not get Google ID token');

    final response = await _api.post('/auth/google', data: {'id_token': idToken});
    final data = response.data as Map<String, dynamic>;

    if (data['is_new_user'] == true) {
      return data; // caller handles onboarding
    }

    // Existing user — save token and return User
    final token = data['access_token'] as String;
    await _storage.saveToken(token);
    final userResponse = await _api.get('/users/me');
    final user = User.fromJson(userResponse.data);
    await _storage.saveUserId(user.id);
    return {'user': user, 'role': data['role'] ?? 'customer'};
  }

  // ── Session helpers ─────────────────────────────────────────────────────────

  Future<void> logout() async {
    try { await _googleSignIn.signOut(); } catch (_) {}
    await _storage.clearAll();
  }

  Future<String?> getToken() async => await _storage.getToken();

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
