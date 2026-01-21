// services/daily_questions_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DailyQuestions {
  final DateTime date;
  final String? bedtime;
  final String? wakeTime;
  final bool? usedUsualTimes; // NEW: Did they use their usual times?
  final bool? napped;
  final bool? feltRested;
  final bool? usedSleepAid;
  final bool? usualEnvironment;
  final bool? consumedSubstances;
  final bool? screenTimeBeforeBed;
  final bool? feltStressed;
  final int? activityIntensity; // NEW: 0-100 scale

  DailyQuestions({
    required this.date,
    this.bedtime,
    this.wakeTime,
    this.usedUsualTimes, // NEW
    this.napped,
    this.feltRested,
    this.usedSleepAid,
    this.usualEnvironment,
    this.consumedSubstances,
    this.screenTimeBeforeBed,
    this.feltStressed,
    this.activityIntensity, // NEW
  });

  Map<String, dynamic> toJson() {
    return {
      'date': date.millisecondsSinceEpoch,
      'bedtime': bedtime,
      'wakeTime': wakeTime,
      'usedUsualTimes': usedUsualTimes, // NEW
      'napped': napped,
      'feltRested': feltRested,
      'usedSleepAid': usedSleepAid,
      'usualEnvironment': usualEnvironment,
      'consumedSubstances': consumedSubstances,
      'screenTimeBeforeBed': screenTimeBeforeBed,
      'feltStressed': feltStressed,
      'activityIntensity': activityIntensity, // NEW
    };
  }

  double? get calculatedSleepDuration {
    if (bedtime == null || wakeTime == null) return null;

    try {
      final bedtimeParts = bedtime!.split(':');
      final wakeTimeParts = wakeTime!.split(':');

      if (bedtimeParts.length != 2 || wakeTimeParts.length != 2) return null;

      final bedtimeHour = int.parse(bedtimeParts[0]);
      final bedtimeMinute = int.parse(bedtimeParts[1]);
      final wakeHour = int.parse(wakeTimeParts[0]);
      final wakeMinute = int.parse(wakeTimeParts[1]);

      DateTime bedtimeDt = DateTime(2023, 1, 1, bedtimeHour, bedtimeMinute);
      DateTime wakeDt = DateTime(2023, 1, 1, wakeHour, wakeMinute);

      if (wakeDt.isBefore(bedtimeDt)) {
        wakeDt = wakeDt.add(const Duration(days: 1));
      }

      final duration = wakeDt.difference(bedtimeDt);
      return duration.inMinutes / 60.0;
    } catch (e) {
      print('Error calculating sleep duration: $e');
      return null;
    }
  }

  factory DailyQuestions.fromJson(Map<String, dynamic> json) {
    return DailyQuestions(
      date: DateTime.fromMillisecondsSinceEpoch(json['date']),
      bedtime: json['bedtime'],
      wakeTime: json['wakeTime'],
      usedUsualTimes: json['usedUsualTimes'], // NEW
      napped: json['napped'],
      feltRested: json['feltRested'],
      usedSleepAid: json['usedSleepAid'],
      usualEnvironment: json['usualEnvironment'],
      consumedSubstances: json['consumedSubstances'],
      screenTimeBeforeBed: json['screenTimeBeforeBed'],
      feltStressed: json['feltStressed'],
      activityIntensity: json['activityIntensity'], // NEW
    );
  }
}

class DailyQuestionsService {
  static const String _dailyQuestionsKey = 'daily_questions';
  static const String _lastSubmissionDateKey = 'last_daily_questions_date';

  Future<bool> shouldShowQuestions() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSubmission = prefs.getString(_lastSubmissionDateKey);

    if (lastSubmission == null) {
      return true;
    }

    final lastDate = DateTime.parse(lastSubmission);
    final today = DateTime.now();

    return !_isSameDay(lastDate, today);
  }

  Future<void> saveQuestions(DailyQuestions questions) async {
    final prefs = await SharedPreferences.getInstance();

    final allQuestions = await getAllQuestions();
    allQuestions.add(questions);

    final questionsJsonList = allQuestions.map((q) => q.toJson()).toList();
    await prefs.setString(_dailyQuestionsKey, json.encode(questionsJsonList));

    await prefs.setString(
      _lastSubmissionDateKey,
      DateTime.now().toIso8601String(),
    );
  }

  Future<List<DailyQuestions>> getAllQuestions() async {
    final prefs = await SharedPreferences.getInstance();
    final questionsString = prefs.getString(_dailyQuestionsKey);

    if (questionsString == null) {
      return [];
    }

    try {
      final List<dynamic> questionsJson = json.decode(questionsString);
      return questionsJson
          .map((json) => DailyQuestions.fromJson(json))
          .toList();
    } catch (e) {
      print('Error parsing daily questions: $e');
      return [];
    }
  }

  Future<DailyQuestions?> getLatestQuestions() async {
    final allQuestions = await getAllQuestions();
    if (allQuestions.isEmpty) return null;

    allQuestions.sort((a, b) => b.date.compareTo(a.date));
    return allQuestions.first;
  }

  Future<DailyQuestions?> getTodaysQuestions() async {
    final allQuestions = await getAllQuestions();
    final today = DateTime.now();

    for (var questions in allQuestions) {
      if (_isSameDay(questions.date, today)) {
        return questions;
      }
    }

    return null;
  }

  // NEW: Get questions for a specific date
  Future<DailyQuestions?> getQuestionsForDate(DateTime date) async {
    final allQuestions = await getAllQuestions();

    for (var questions in allQuestions) {
      if (_isSameDay(questions.date, date)) {
        return questions;
      }
    }

    return null;
  }

  // NEW: Get submission count (for determining if user is in first 3 days)
  Future<int> getSubmissionCount() async {
    final allQuestions = await getAllQuestions();
    return allQuestions.length;
  }

  // NEW: Get last 3 days of sleep data for averaging
  Future<List<DailyQuestions>> getLast3DaysSleepData() async {
    final allQuestions = await getAllQuestions();
    allQuestions.sort((a, b) => b.date.compareTo(a.date));

    // Filter to only include entries with sleep data
    final withSleepData = allQuestions
        .where((q) => q.bedtime != null && q.wakeTime != null)
        .toList();

    return withSleepData.take(3).toList();
  }

  // NEW: Calculate average sleep times from recent data
  Future<Map<String, String>?> calculateAverageSleepTimes() async {
    final recentData = await getLast3DaysSleepData();

    if (recentData.length < 3) return null;

    // Calculate average bedtime
    int totalBedMinutes = 0;
    int totalWakeMinutes = 0;

    for (var data in recentData) {
      final bedParts = data.bedtime!.split(':');
      final wakeParts = data.wakeTime!.split(':');

      int bedHour = int.parse(bedParts[0]);
      int bedMinute = int.parse(bedParts[1]);
      int wakeHour = int.parse(wakeParts[0]);
      int wakeMinute = int.parse(wakeParts[1]);

      // Convert to minutes from midnight
      totalBedMinutes += (bedHour * 60 + bedMinute);
      totalWakeMinutes += (wakeHour * 60 + wakeMinute);
    }

    int avgBedMinutes = totalBedMinutes ~/ recentData.length;
    int avgWakeMinutes = totalWakeMinutes ~/ recentData.length;

    String bedtime =
        '${(avgBedMinutes ~/ 60).toString().padLeft(2, '0')}:${(avgBedMinutes % 60).toString().padLeft(2, '0')}';
    String wakeTime =
        '${(avgWakeMinutes ~/ 60).toString().padLeft(2, '0')}:${(avgWakeMinutes % 60).toString().padLeft(2, '0')}';

    return {'bedtime': bedtime, 'wakeTime': wakeTime};
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
}
