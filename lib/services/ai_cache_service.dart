// services/ai_cache_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AICacheService {
  static const String _cacheKey = 'ai_metric_insights_cache';

  Future<Map<String, String>> getCachedInsights() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cachedString = prefs.getString(_cacheKey);
    if (cachedString != null) {
      return Map<String, String>.from(json.decode(cachedString));
    }
    return {};
  }

  Future<void> saveInsights(Map<String, String> insights) async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedString = json.encode(insights);
    await prefs.setString(_cacheKey, encodedString);
  }
}