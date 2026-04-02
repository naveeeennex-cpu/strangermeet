import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';

import 'config/theme.dart';
import 'config/router.dart';
import 'config/constants.dart';
import 'providers/theme_provider.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Firebase (required for FCM push notifications)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialise FCM + local notifications
  await NotificationService.instance.init();

  runApp(
    const ProviderScope(
      child: StrangerMeetApp(),
    ),
  );
}

class StrangerMeetApp extends ConsumerWidget {
  const StrangerMeetApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      routerConfig: router,
    );
  }
}
