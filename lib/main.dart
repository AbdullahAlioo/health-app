import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'package:zyora_final/services/ble_service.dart';
import 'package:zyora_final/services/background_ble_service.dart';
import 'package:zyora_final/services/daily_questions_service.dart';
import 'package:zyora_final/screens/daily_questions_screen.dart';
import 'package:zyora_final/services/boot_complete_receiver.dart';
import 'package:zyora_final/services/theme_service.dart';
import 'package:zyora_final/widgets/dashboard_skeleton_screen.dart';
// Source - https://stackoverflow.com/a
// Posted by Ma'moon Al-Akash, modified by community. See post 'Timeline' for change history
// Retrieved 2026-01-11, License - CC BY-SA 4.0

import 'dart:io';
import 'package:zyora_final/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Notification Service
  await NotificationService().initialize();

  // Initialize services
  final bleService = BLEService();
  final backgroundBleService = BackgroundBLEService();
  final themeService = ThemeService();
  // Source - https://stackoverflow.com/a
  // Posted by Ma'moon Al-Akash, modified by community. See post 'Timeline' for change history
  // Retrieved 2026-01-11, License - CC BY-SA 4.0

  HttpOverrides.global = MyHttpOverrides();

  // Check if it's first launch
  final prefs = await SharedPreferences.getInstance();
  bool hasSeenWelcome = prefs.getBool('hasSeenWelcome') ?? false;

  // Initialize boot receiver - this will start the background service ONCE
  await BootCompleteReceiver.initialize();

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider.value(value: themeService)],
      child: MyApp(
        hasSeenWelcome: hasSeenWelcome,
        bleService: bleService,
        backgroundBleService: backgroundBleService,
      ),
    ),
  );
}
// Source - https://stackoverflow.com/a
// Posted by Ma'moon Al-Akash, modified by community. See post 'Timeline' for change history
// Retrieved 2026-01-11, License - CC BY-SA 4.0

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

class MyApp extends StatelessWidget {
  final bool hasSeenWelcome;
  final BLEService bleService;
  final BackgroundBLEService backgroundBleService;

  const MyApp({
    super.key,
    required this.hasSeenWelcome,
    required this.bleService,
    required this.backgroundBleService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zyora Watch',
      debugShowCheckedModeBanner: false,
      themeMode: Provider.of<ThemeService>(context).themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.light(
          primary: const Color(0xFF1173D4),
          secondary: const Color(0xFF34C759),
          surface: Colors.white,
          background: const Color(0xFFF8FAFD),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFB8B8B8),
          secondary: Color(0xFF808080),
          surface: Color(0xFF1A1A1A),
          background: Color(0xFF0A0A0A),
          onBackground: Color(0xFFE8E8E8),
          onSurface: Color(0xFFE8E8E8),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
      ),
      home: AppWrapper(
        hasSeenWelcome: hasSeenWelcome,
        bleService: bleService,
        backgroundBleService: backgroundBleService,
      ),
    );
  }
}

class AppWrapper extends StatefulWidget {
  final bool hasSeenWelcome;
  final BLEService bleService;
  final BackgroundBLEService backgroundBleService;

  const AppWrapper({
    super.key,
    required this.hasSeenWelcome,
    required this.bleService,
    required this.backgroundBleService,
  });

  @override
  State<AppWrapper> createState() => _AppWrapperState();
}

class _AppWrapperState extends State<AppWrapper> {
  late bool _hasSeenWelcome;
  bool _isConnected = false;
  bool _isInitializing = true;
  bool _showDailyQuestions = false;
  final DailyQuestionsService _dailyQuestionsService = DailyQuestionsService();

  @override
  void initState() {
    super.initState();
    _hasSeenWelcome = widget.hasSeenWelcome;
    _initializeApp();
  }

  /// Initializes the app based on whether user has seen welcome screen
  Future<void> _initializeApp() async {
    try {
      // Set up listeners for background service
      await _setupBackgroundListeners();

      if (_hasSeenWelcome) {
        // Check if we should show daily questions
        final shouldShowQuestions = await _dailyQuestionsService
            .shouldShowQuestions();

        if (mounted) {
          setState(() {
            _showDailyQuestions = shouldShowQuestions;
          });
        }

        // Set up BLE listeners for main service
        _setupBLEListeners();

        // Only attempt auto-connect if not showing questions
        if (!_showDailyQuestions) {
          await _attemptAutoConnect();
        }
      }
    } catch (e) {
      debugPrint('Error during app initialization: $e');
    } finally {
      // Mark initialization as complete
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  /// Sets up listeners for main BLE connection status changes
  void _setupBLEListeners() {
    widget.bleService.connectionStream.listen((connected) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
        });
      }
    });
  }

  /// Sets up listeners for background BLE service
  Future<void> _setupBackgroundListeners() async {
    // Update UI when background service receives data
    widget.backgroundBleService.onDataReceived = (healthData) {
      if (mounted) {
        // Update any UI components if needed
        print(
          '🎯 Background service received data: ${healthData.heartRate} BPM',
        );
        // You can update state here if needed to reflect new data
      }
    };

    // Update UI when background service connection status changes
    widget.backgroundBleService.onConnectionStatusChanged = (connected) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
        });
      }
    };

    // 🔥 CRITICAL: Sync background data to database when app starts
    // This ensures all data collected while app was closed is now visible
    await widget.backgroundBleService.syncBackgroundDataToDatabase();
  }

  /// Attempts to auto-connect to the last known device with 3.5s timeout
  Future<void> _attemptAutoConnect() async {
    try {
      // Use a timeout of 3.5 seconds - if connection takes longer, proceed anyway
      final connected = await widget.bleService.autoConnect().timeout(
        const Duration(milliseconds: 3500),
        onTimeout: () {
          debugPrint('⏱️ Connection timeout (3.5s) - proceeding to dashboard');
          return false;
        },
      );

      if (mounted) {
        setState(() {
          _isConnected = connected;
        });
      }

      // If auto-connect failed, background service will handle reconnection
      if (!connected) {
        debugPrint(
          'Auto-connect failed or timed out - Kotlin background service will handle reconnection',
        );
      }
    } catch (e) {
      debugPrint('Error during auto-connect: $e');
      // Background service will handle reconnection
      if (mounted) {
        setState(() {
          _isConnected = false;
        });
      }
    }
  }

  /// Callback when user completes the welcome screen
  Future<void> _onWelcomeComplete() async {
    // Save that user has seen welcome screen
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenWelcome', true);

    if (mounted) {
      setState(() {
        _hasSeenWelcome = true;
      });
    }

    // Set up BLE listeners after welcome screen
    _setupBLEListeners();

    // Start scanning for devices after welcome
    try {
      await widget.bleService.scanForDevices();
    } catch (e) {
      debugPrint('Error starting device scan: $e');
    }
  }

  /// Callback when user completes daily questions
  Future<void> _onDailyQuestionsComplete() async {
    if (mounted) {
      setState(() {
        _showDailyQuestions = false;
      });
    }

    // Set up BLE listeners after questions
    _setupBLEListeners();

    // Now attempt auto-connect after questions are completed
    await _attemptAutoConnect();
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator only during initial app setup for returning users
    if (_isInitializing && _hasSeenWelcome) {
      return const DashboardSkeletonScreen();
    }

    // Show daily questions if needed (only for returning users who haven't answered today)
    if (_showDailyQuestions && _hasSeenWelcome) {
      return DailyQuestionsScreen(onCompleted: _onDailyQuestionsComplete);
    }

    // New users see welcome screen, returning users ALWAYS see dashboard
    return ZyoraApp(
      hasSeenWelcome: _hasSeenWelcome,
      bleService: widget.bleService,
      backgroundBleService: widget.backgroundBleService,
      isConnected: _isConnected,
      onWelcomeComplete: _onWelcomeComplete,
    );
  }

  @override
  void dispose() {
    // 🔥 CRITICAL: Don't stop background service on dispose - let it run continuously
    // even when the app is closed or terminated. The service will run independently.
    super.dispose();
  }
}
