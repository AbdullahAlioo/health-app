// services/user_profile_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class UserProfile {
  final int? age;
  final double? weight; // NEW: Add weight field
  final String? usualBedtime; // Format: "HH:mm" (24-hour)
  final String? usualWakeTime; // Format: "HH:mm" (24-hour)
  final DateTime? createdAt;

  UserProfile({
    this.age,
    this.weight, // NEW: Add weight to constructor
    this.usualBedtime,
    this.usualWakeTime,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'age': age,
      'weight': weight, // NEW: Add weight to toJson
      'usualBedtime': usualBedtime,
      'usualWakeTime': usualWakeTime,
      'createdAt': createdAt?.millisecondsSinceEpoch,
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      age: json['age'],
      weight: json['weight']?.toDouble(), // NEW: Add weight to fromJson, ensure it's a double
      usualBedtime: json['usualBedtime'],
      usualWakeTime: json['usualWakeTime'],
      createdAt: json['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'])
          : null,
    );
  }

  // NEW: Calculate usual sleep duration
  double? get usualSleepDuration {
    if (usualBedtime == null || usualWakeTime == null) return null;

    try {
      final bedParts = usualBedtime!.split(':');
      final wakeParts = usualWakeTime!.split(':');

      if (bedParts.length != 2 || wakeParts.length != 2) return null;

      final bedHour = int.parse(bedParts[0]);
      final bedMinute = int.parse(bedParts[1]);
      final wakeHour = int.parse(wakeParts[0]);
      final wakeMinute = int.parse(wakeParts[1]);

      DateTime bedtimeDt = DateTime(2023, 1, 1, bedHour, bedMinute);
      DateTime wakeDt = DateTime(2023, 1, 1, wakeHour, wakeMinute);

      if (wakeDt.isBefore(bedtimeDt)) {
        wakeDt = wakeDt.add(const Duration(days: 1));
      }

      final duration = wakeDt.difference(bedtimeDt);
      return duration.inMinutes / 60.0;
    } catch (e) {
      print('Error calculating usual sleep duration: $e');
      return null;
    }
  }
}

class UserProfileService {
  static const String _userProfileKey = 'user_profile';

  Future<void> saveUserProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final profileJson = profile.toJson();
    await prefs.setString(_userProfileKey, json.encode(profileJson));
  }

  Future<UserProfile?> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final profileString = prefs.getString(_userProfileKey);
    if (profileString != null) {
      try {
        final profileJson = json.decode(profileString);
        return UserProfile.fromJson(profileJson);
      } catch (e) {
        print('Error parsing user profile: $e');
        return null;
      }
    }
    return null;
  }

  Future<void> clearUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userProfileKey);
  }

  // NEW: Update sleep times only
  Future<void> updateSleepTimes(String bedtime, String wakeTime) async {
    final currentProfile = await getUserProfile();
    if (currentProfile != null) {
      final updatedProfile = UserProfile(
        age: currentProfile.age,
        weight: currentProfile.weight, // NEW: Copy existing weight
        usualBedtime: bedtime,
        usualWakeTime: wakeTime,
        createdAt: currentProfile.createdAt,
      );
      await saveUserProfile(updatedProfile);
    }
  }

  // NEW: Update weight only
  Future<void> updateWeight(double weight) async {
    final currentProfile = await getUserProfile();
    if (currentProfile != null) {
      final updatedProfile = UserProfile(
        age: currentProfile.age,
        weight: weight, // NEW: Update weight
        usualBedtime: currentProfile.usualBedtime,
        usualWakeTime: currentProfile.usualWakeTime,
        createdAt: currentProfile.createdAt,
      );
      await saveUserProfile(updatedProfile);
    } else {
      // If no profile exists, create a new one with just the weight
      final newProfile = UserProfile(
        weight: weight,
        createdAt: DateTime.now(), // Set creation time for new profile
      );
      await saveUserProfile(newProfile);
    }
  }
}