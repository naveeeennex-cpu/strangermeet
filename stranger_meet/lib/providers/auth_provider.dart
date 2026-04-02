import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';
import '../services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

enum AuthStatus { initial, loading, authenticated, unauthenticated, error, needsOnboarding }

class AuthState {
  final AuthStatus status;
  final User? user;
  final String? errorMessage;
  final Map<String, dynamic>? pendingGoogleData;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.errorMessage,
    this.pendingGoogleData,
  });

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    String? errorMessage,
    Map<String, dynamic>? pendingGoogleData,
    bool clearPendingGoogleData = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage,
      pendingGoogleData: clearPendingGoogleData
          ? null
          : (pendingGoogleData ?? this.pendingGoogleData),
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;

  AuthNotifier(this._authService) : super(const AuthState());

  Future<void> checkAuthStatus() async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final isLoggedIn = await _authService.isLoggedIn();
      if (isLoggedIn) {
        final user = await _authService.getCurrentUser();
        state = AuthState(
          status: AuthStatus.authenticated,
          user: user,
        );
      } else {
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
    } catch (e) {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final user = await _authService.login(email, password);
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
      );
    } catch (e) {
      state = AuthState(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> signInWithGoogle() async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final result = await _authService.signInWithGoogle();
      if (result['is_new_user'] == true) {
        state = AuthState(
          status: AuthStatus.needsOnboarding,
          pendingGoogleData: result,
        );
      } else {
        state = AuthState(
          status: AuthStatus.authenticated,
          user: result['user'] as User,
        );
      }
    } catch (e) {
      state = AuthState(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> signup({
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
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final user = await _authService.signup(
        name: name,
        email: email,
        password: password,
        username: username,
        phone: phone,
        interests: interests,
        role: role,
        occupation: occupation,
        collegeName: collegeName,
        companyName: companyName,
        designation: designation,
        googleId: googleId,
        profileImageUrl: profileImageUrl,
      );
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
      );
    } catch (e) {
      state = AuthState(
        status: AuthStatus.error,
        errorMessage: e.toString(),
        pendingGoogleData: state.pendingGoogleData,
      );
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> fetchCurrentUser() async {
    try {
      final user = await _authService.getCurrentUser();
      if (user != null) {
        state = state.copyWith(user: user);
      }
    } catch (_) {}
  }

  Future<void> updateProfile({
    String? bio,
    List<String>? interests,
    String? profileImageUrl,
  }) async {
    try {
      final user = await _authService.updateProfile(
        bio: bio,
        interests: interests,
        profileImageUrl: profileImageUrl,
      );
      state = state.copyWith(user: user);
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  void clearPendingGoogleData() {
    state = state.copyWith(
      clearPendingGoogleData: true,
      status: AuthStatus.unauthenticated,
    );
  }
}

final authStateProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthNotifier(authService);
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).user;
});
