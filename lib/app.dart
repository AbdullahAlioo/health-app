import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'screens/welcome_screen.dart';
import 'screens/main_navigation.dart';
import 'services/ble_service.dart';
import 'services/background_ble_service.dart';
import 'services/theme_service.dart';

class ZyoraApp extends StatelessWidget {
  final bool hasSeenWelcome;
  final BLEService bleService;
  final BackgroundBLEService backgroundBleService;
  final bool isConnected;
  final VoidCallback onWelcomeComplete;

  const ZyoraApp({
    super.key,
    required this.hasSeenWelcome,
    required this.bleService,
    required this.backgroundBleService,
    required this.isConnected,
    required this.onWelcomeComplete,
  });

  @override
  Widget build(BuildContext context) {
    // Access the theme mode from the provider
    final themeService = Provider.of<ThemeService>(context);

    return MaterialApp(
      title: 'Zyora',
      debugShowCheckedModeBanner: false,
      themeMode: themeService.themeMode,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      home: hasSeenWelcome
          ? MainNavigation(
              bleService: bleService,
              backgroundBleService: backgroundBleService,
            )
          : WelcomeScreen(
              bleService: bleService,
              onComplete: onWelcomeComplete,
            ),
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF1173D4),
        secondary: Color(0xFF34C759),
        surface: Colors.white,
        background: Color(0xFFF8FAFD),
        onBackground: Colors.black87,
        onSurface: Colors.black87,
      ),
      scaffoldBackgroundColor: const Color(0xFFF8FAFD),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      textTheme: GoogleFonts.interTextTheme().copyWith(
        displayLarge: GoogleFonts.inter(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
        displayMedium: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: Colors.black87,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: Colors.black54,
        ),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
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
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: const Color(0xFFE8E8E8),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFE8E8E8)),
      ),
      textTheme: GoogleFonts.interTextTheme().copyWith(
        displayLarge: GoogleFonts.inter(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFE8E8E8),
        ),
        displayMedium: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: const Color(0xFFE8E8E8),
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: const Color(0xFFE8E8E8),
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: const Color(0xFFB8B8B8),
        ),
      ),
    );
  }
}
