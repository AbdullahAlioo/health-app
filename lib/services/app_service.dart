import 'package:shared_preferences/shared_preferences.dart';

class AppService {
  static const String _firstLaunchKey = 'hasSeenWelcome';

  // Check if it's the first app launch
  static Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_firstLaunchKey) ?? true;
  }

  // Mark app as launched (not first time anymore)
  static Future<void> setAppLaunched() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firstLaunchKey, false);
  }

  // Reset first launch (for testing purposes)
  static Future<void> resetFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firstLaunchKey, true);
  }
}