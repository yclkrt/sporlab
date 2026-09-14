// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lingo_easy/lingo_easy.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sporlab/core/providers/theme_provider.dart';
import 'package:sporlab/core/router/app_router.dart';
import 'package:sporlab/core/services/notification_service.dart';
import 'package:sporlab/core/theme/app_theme.dart';
import 'package:timezone/data/latest_all.dart' as tz;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize timezone data for notifications
  tz.initializeTimeZones();

  // Load saved theme synchronously before app starts
  ThemeMode initialThemeMode = ThemeMode.dark; // fallback
  try {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(ThemeNotifier.themeKey) ?? 0;
    if (themeIndex >= 0 && themeIndex < ThemeMode.values.length) {
      initialThemeMode = ThemeMode.values[themeIndex];
    }
  } catch (e) {
    debugPrint('Error loading theme: $e');
  }

  // Start app immediately with saved theme
  runApp(
    ProviderScope(
      overrides: [
        themeProvider.overrideWith((ref) {
          final notifier = ThemeNotifier.withInitialMode(initialThemeMode);
          return notifier;
        }),
      ],
      child: const MyApp(),
    ),
  );

  // Request permissions and initialize services in background
  // This won't block app startup
  _initializeInBackground();
}

/// Initialize services in background after app starts
Future<void> _initializeInBackground() async {
  // Request necessary permissions
  await _requestPermissions();

  // Initialize notification service
  try {
    await NotificationService().initialize();
  } catch (e) {
    debugPrint('Error initializing notifications: $e');
  }
}

/// Gerekli izinleri iste
Future<void> _requestPermissions() async {
  // Android 13+ (API 33+) için bildirim izni
  try {
    final notificationStatus = await Permission.notification.status;
    if (!notificationStatus.isGranted) {
      await Permission.notification.request();
    }
  } catch (e) {
    debugPrint('Error requesting notification permission: $e');
  }

  // Android 10+ (API 29+) için aktivite tanıma izni (adım sayacı için)
  try {
    final activityStatus = await Permission.activityRecognition.status;
    if (!activityStatus.isGranted) {
      await Permission.activityRecognition.request();
    }
  } catch (e) {
    debugPrint('Error requesting activity recognition permission: $e');
  }
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'SporLab',
      themeMode: themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return LingoWrapper(
          defaultLocale: 'tr',
          supportedLocales: const ['en', 'tr'],
          assetsPath: 'assets/lang',
          loadingWidget: const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Yükleniyor...', style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
