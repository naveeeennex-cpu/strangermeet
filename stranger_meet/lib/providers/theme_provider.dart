import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.dark) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    const storage = FlutterSecureStorage();
    final theme = await storage.read(key: 'theme_mode');
    if (theme == 'light') {
      state = ThemeMode.light;
    } else {
      state = ThemeMode.dark; // Default to dark
    }
  }

  Future<void> toggleTheme() async {
    const storage = FlutterSecureStorage();
    if (state == ThemeMode.dark) {
      state = ThemeMode.light;
      await storage.write(key: 'theme_mode', value: 'light');
    } else {
      state = ThemeMode.dark;
      await storage.write(key: 'theme_mode', value: 'dark');
    }
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    const storage = FlutterSecureStorage();
    await storage.write(
        key: 'theme_mode', value: mode == ThemeMode.dark ? 'dark' : 'light');
  }

  bool get isDark => state == ThemeMode.dark;
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});
