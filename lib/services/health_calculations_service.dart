import 'dart:math' as math;
import 'daily_questions_service.dart';
import 'package:zyora_final/local_storage_service.dart';

class HealthCalculationsService {
  static SleepNeedResult calculateSleepNeed({
    required int age,
    required int rhrBaseline,
    required int rhrToday,
    required int hrvToday,
    required int hrvBaseline,
    required int steps,
    required int calories,
    required double? sleepFromForm,
    required int spo2,
    required int stress,
    required double bodyTemperature,
    required int breathingRate,
    DailyQuestions? dailyQuestions,
    int? activityIntensity, // NEW
  }) {
    int virtualSteps = steps;
    if (activityIntensity != null) {
      // Scale: 0-25% = 2000 steps, 26-50% = 5000 steps, 51-75% = 8000 steps, 76-100% = 12000 steps
      if (activityIntensity <= 25) {
        virtualSteps = 2000;
      } else if (activityIntensity <= 50) {
        virtualSteps = 5000;
      } else if (activityIntensity <= 75) {
        virtualSteps = 8000;
      } else {
        virtualSteps = 12000;
      }
    }

    double baseSleep = age <= 17 ? 9.5 : 8.0;

    print(' CALCULATION INPUTS:');
    print(' RHR Today: $rhrToday, Baseline: $rhrBaseline');
    print(' HRV Today: $hrvToday, Baseline: $hrvBaseline');
    print(' Stress: $stress');
    print(' Sleep: ${sleepFromForm ?? baseSleep}');
    print('️ Temp: $bodyTemperature');
    print('️ Breathing: $breathingRate');
    if (activityIntensity != null) {
      print(
        ' Activity Intensity: $activityIntensity% (Virtual Steps: $virtualSteps)',
      );
    }

    double recovery = _calculateMedicalRecoveryScore(
      rhrBaseline: rhrBaseline,
      rhrToday: rhrToday,
      hrvBaseline: hrvBaseline,
      hrvToday: hrvToday,
      sleepHours: sleepFromForm ?? baseSleep,
      stress: stress,
      bodyTemperature: bodyTemperature,
      breathingRate: breathingRate,
      spo2: spo2,
      dailyQuestions: dailyQuestions,
    );

    double healthScore = _calculateMedicalHealthScore(
      recovery: recovery,
      rhr: rhrToday,
      hrv: hrvToday,
      spo2: spo2,
      steps: virtualSteps, // Use virtual steps
      sleepHours: sleepFromForm ?? baseSleep,
      stress: stress,
      bodyTemperature: bodyTemperature,
      breathingRate: breathingRate,
      stressFromQuestions: dailyQuestions?.feltStressed ?? false,
    );

    double sleepNeed = _calculateSmartSleepNeed(
      recovery,
      sleepFromForm ?? baseSleep,
      baseSleep,
    );

    print(' MEDICAL-GRADE CALCULATION COMPLETE');
    print(' Recovery: ${recovery.toStringAsFixed(1)}%');
    print('️  RHR: $rhrToday bpm (Baseline: $rhrBaseline)');
    print(' HRV: $hrvToday ms (Baseline: $hrvBaseline)');
    print(' Health Score: ${healthScore.toStringAsFixed(1)}/100');
    print(' Sleep Need: ${sleepNeed.toStringAsFixed(1)}h');

    return SleepNeedResult(
      sleepNeed: sleepNeed,
      recoveryPercent: recovery,
      baseSleepRequired: baseSleep,
      healthScore: healthScore,
      hrvStatus: _getHRVStatus(hrvToday),
      rhrStatus: _getRHRStatus(rhrToday),
    );
  }

  static double _calculateMedicalRecoveryScore({
    required int rhrBaseline,
    required int rhrToday,
    required int hrvBaseline,
    required int hrvToday,
    required double sleepHours,
    required int stress,
    required double bodyTemperature,
    required int breathingRate,
    required int spo2,
    DailyQuestions? dailyQuestions,
  }) {
    double score = 50.0;

    print('RECOVERY CALCULATION BREAKDOWN:');

    double hrvRatio = hrvBaseline > 0 ? hrvToday / hrvBaseline.toDouble() : 0.0;
    print('HRV Ratio: $hrvRatio (Today: $hrvToday, Baseline: $hrvBaseline)');

    // Handle invalid/missing HRV (0)
    if (hrvToday <= 0) {
      score -= 5;
      print('HRV: -5 (Missing Data)');
    } else if (hrvRatio >= 1.1) {
      score += 20;
      print('HRV: +20 (Excellent)');
    } else if (hrvRatio >= 1.0) {
      score += 15;
      print('HRV: +15 (Very Good)');
    } else if (hrvRatio >= 0.9) {
      score += 5;
      print('HRV: +5 (Good)');
    } else if (hrvRatio >= 0.8) {
      score -= 10;
      print('HRV: -10 (Fair)');
    } else if (hrvRatio >= 0.7) {
      score -= 20;
      print('HRV: -20 (Poor)');
    } else {
      score -= 30;
      print('HRV: -30 (Very Poor)');
    }

    double rhrChange = (rhrToday - rhrBaseline).toDouble();
    print('RHR Change: $rhrChange (Today: $rhrToday, Baseline: $rhrBaseline)');

    // Handle invalid/missing RHR (0 or unrealistically low)
    if (rhrToday <= 30) {
      score -= 10;
      print('RHR: -10 (Missing/Invalid Data)');
    } else if (rhrChange <= -5) {
      score += 12;
      print('RHR: +12 (Excellent)');
    } else if (rhrChange <= -2) {
      score += 8;
      print('RHR: +8 (Very Good)');
    } else if (rhrChange <= 2) {
      score += 5;
      print('RHR: +5 (Normal)');
    } else if (rhrChange <= 5) {
      score -= 5;
      print('RHR: -5 (Elevated)');
    } else if (rhrChange <= 10) {
      score -= 12;
      print('RHR: -12 (High)');
    } else {
      score -= 20;
      print('RHR: -20 (Very High)');
    }

    print('Sleep Hours: $sleepHours');
    if (sleepHours >= 8.0) {
      score += 10;
      print('Sleep: +10 (Excellent)');
    } else if (sleepHours >= 7.5) {
      score += 8;
      print('Sleep: +8 (Very Good)');
    } else if (sleepHours >= 7.0) {
      score += 5;
      print('Sleep: +5 (Good)');
    } else if (sleepHours >= 6.0) {
      score += 2;
      print('Sleep: +2 (Fair)');
    } else if (sleepHours >= 5.0) {
      score -= 5;
      print('Sleep: -5 (Poor)');
    } else {
      score -= 10;
      print('Sleep: -10 (Very Poor)');
    }

    print('Stress Level: $stress');
    if (stress <= 25) {
      score += 5;
      print('Stress: +5 (Low)');
    } else if (stress >= 70) {
      score -= 5;
      print('Stress: -8 (High)');
    }

    if (bodyTemperature > 37.2) {
      score -= 5;
      print('Temp: -5 (Elevated)');
    }
    if (breathingRate > 20) {
      score -= 3;
      print('Breathing: -3 (Elevated)');
    }

    print('SpO2: $spo2%');
    if (spo2 >= 98) {
      score += 3;
      print('SpO2: +3 (Excellent)');
    } else if (spo2 >= 96) {
      score += 1;
      print('SpO2: +1 (Good)');
    } else if (spo2 < 94) {
      score -= 3;
      print('SpO2: -3 (Low)');
    }

    if (dailyQuestions != null) {
      if (dailyQuestions.feltRested == true) {
        score += 3;
        print('Felt Rested: +3');
      }
      if (dailyQuestions.feltStressed == true) {
        score -= 3;
        print('Felt Stressed: -3');
      }
      if (dailyQuestions.usedSleepAid == true) {
        score -= 2;
        print('Used Sleep Aid: -2');
      }
    }

    double finalScore = score.clamp(10, 100);
    print(' FINAL RECOVERY SCORE: $finalScore%');

    return finalScore;
  }

  static double _calculateMedicalHealthScore({
    required double recovery,
    required int rhr,
    required int hrv,
    required int spo2,
    required int steps,
    required double sleepHours,
    required int stress,
    required double bodyTemperature,
    required int breathingRate,
    required bool stressFromQuestions,
  }) {
    double score = recovery * 0.3;
    print('HEALTH SCORE BREAKDOWN:');
    print(
      ' Recovery Base: ${recovery.toStringAsFixed(1)} * 0.3 = ${(recovery * 0.3).toStringAsFixed(1)}',
    );

    if (hrv >= 60) {
      score += 25;
      print('HRV: +25 (Excellent)');
    } else if (hrv >= 50) {
      score += 20;
      print('HRV: +20 (Very Good)');
    } else if (hrv >= 40) {
      score += 15;
      print('HRV: +15 (Good)');
    } else if (hrv >= 30) {
      score += 10;
      print('HRV: +10 (Fair)');
    } else if (hrv >= 20) {
      score += 5;
      print('HRV: +5 (Poor)');
    } else {
      print('HRV: +0 (Very Poor)');
    }

    if (rhr <= 55) {
      score += 20;
      print('RHR: +20 (Excellent)');
    } else if (rhr <= 60) {
      score += 18;
      print('RHR: +18 (Very Good)');
    } else if (rhr <= 65) {
      score += 15;
      print('RHR: +15 (Good)');
    } else if (rhr <= 70) {
      score += 12;
      print('RHR: +12 (Fair)');
    } else if (rhr <= 75) {
      score += 8;
      print('RHR: +8 (Below Average)');
    } else if (rhr <= 80) {
      score += 4;
      print('RHR: +4 (Poor)');
    } else {
      print('RHR: +0 (Very Poor)');
    }

    if (steps >= 10000) {
      score += 10;
      print('Steps: +10 (Excellent)');
    } else if (steps >= 8000) {
      score += 8;
      print('Steps: +8 (Very Good)');
    } else if (steps >= 6000) {
      score += 6;
      print('Steps: +6 (Good)');
    } else if (steps >= 4000) {
      score += 4;
      print('Steps: +4 (Fair)');
    } else if (steps >= 2000) {
      score += 2;
      print('Steps: +2 (Below Average)');
    } else {
      print('Steps: +0 (Low)');
    }

    if (sleepHours >= 8.0) {
      score += 10;
      print('Sleep: +10 (Excellent)');
    } else if (sleepHours >= 7.5) {
      score += 8;
      print('Sleep: +8 (Very Good)');
    } else if (sleepHours >= 7.0) {
      score += 6;
      print('Sleep: +6 (Good)');
    } else if (sleepHours >= 6.5) {
      score += 4;
      print('Sleep: +4 (Fair)');
    } else if (sleepHours >= 6.0) {
      score += 2;
      print('Sleep: +2 (Poor)');
    } else {
      print('Sleep: +0 (Very Poor)');
    }

    if (stress <= 25 && !stressFromQuestions) {
      score += 5;
      print('Stress: +5 (Low)');
    } else if (stress >= 70 || stressFromQuestions) {
      score -= 5;
      print('Stress: -5 (High)');
    } else {
      print('Stress: +0 (Medium)');
    }

    if (bodyTemperature >= 36.1 && bodyTemperature <= 37.2) {
      score += 5;
      print('Body Temperature: +5 (Normal)');
    } else {
      print('Body Temperature: +0 (Abnormal)');
    }

    double finalScore = score.clamp(20, 100);
    print('FINAL HEALTH SCORE: $finalScore/100');

    return finalScore;
  }

  static double _calculateSmartSleepNeed(
    double recovery,
    double actualSleep,
    double baseSleep,
  ) {
    if (recovery >= 85) return 0;

    double sleepDebt = baseSleep - actualSleep;
    double recoveryDeficit = (100 - recovery) / 100;

    return (sleepDebt + recoveryDeficit).clamp(0, 3.0);
  }

  static String _getHRVStatus(int hrv) {
    if (hrv >= 60) return 'Excellent';
    if (hrv >= 50) return 'Very Good';
    if (hrv >= 40) return 'Good';
    if (hrv >= 30) return 'Fair';
    return 'Poor';
  }

  static String _getRHRStatus(int rhr) {
    if (rhr <= 55) return 'Excellent';
    if (rhr <= 60) return 'Very Good';
    if (rhr <= 65) return 'Good';
    if (rhr <= 70) return 'Fair';
    if (rhr <= 75) return 'Below Average';
    return 'Poor';
  }

  static BaselineData calculateBaselines(
    List<HealthDataPoint> historicalData, [
    List<DailyQuestions>? allQuestions,
  ]) {
    print(
      '🎯 CALCULATING SMART BASELINES FROM ${historicalData.length} POINTS',
    );

    if (historicalData.isEmpty) {
      return BaselineData(rhrBaseline: 65, hrvBaseline: 45);
    }

    // 1. Calculate daily RHRs and HRVs for each day in history
    final dailyRHRs = calculateDailyRHRs(historicalData, allQuestions ?? []);
    final dailyHRVs = calculateDailyHRVs(historicalData, allQuestions ?? []);

    // 2. Average the daily values (not individual points!)
    double totalRHR = 0;
    int rhrCount = 0;
    dailyRHRs.values.forEach((v) {
      if (v > 0) {
        totalRHR += v;
        rhrCount++;
      }
    });

    double totalHRV = 0;
    int hrvCount = 0;
    dailyHRVs.values.forEach((v) {
      if (v > 10) {
        // HRV should be at least 10 to be considered valid
        totalHRV += v;
        hrvCount++;
      }
    });

    final rhrBaseline = rhrCount > 0 ? (totalRHR / rhrCount).round() : 65;
    final hrvBaseline = hrvCount > 0 ? (totalHRV / hrvCount).round() : 45;

    print(
      '🎯 FINAL SMART BASELINES: RHR=$rhrBaseline bpm, HRV=$hrvBaseline ms (from $rhrCount days)',
    );

    return BaselineData(rhrBaseline: rhrBaseline, hrvBaseline: hrvBaseline);
  }

  // NEW: Calculate Daily RHRs from heart rate logs and daily questions
  static Map<String, int> calculateDailyRHRs(
    List<HealthDataPoint> allPoints,
    List<DailyQuestions> allQuestions,
  ) {
    Map<String, List<HealthDataPoint>> hrPointsByDate = {};
    Map<String, DailyQuestions> questionsByDate = {};

    for (var q in allQuestions) {
      final dateStr = q.date.toIso8601String().split('T')[0];
      questionsByDate[dateStr] = q;
    }

    for (var p in allPoints) {
      final dateStr = p.timestamp.toIso8601String().split('T')[0];
      hrPointsByDate.putIfAbsent(dateStr, () => []).add(p);
    }

    Map<String, int> dailyRHRs = {};

    hrPointsByDate.forEach((dateStr, points) {
      final questions = questionsByDate[dateStr];
      final reportDate = DateTime.parse(dateStr);

      if (questions?.bedtime != null && questions?.wakeTime != null) {
        final window = getSleepWindow(
          reportDate,
          questions!.bedtime!,
          questions.wakeTime!,
        );
        if (window != null) {
          final windowPoints = points
              .where(
                (p) =>
                    p.timestamp.isAfter(window['start']!) &&
                    p.timestamp.isBefore(window['end']!),
              )
              .map((p) => p.heartRate)
              .toList();

          if (windowPoints.isNotEmpty) {
            dailyRHRs[dateStr] = calculateRHRFromList(windowPoints);
            return;
          }
        }
      }

      // Fallback: 2 AM to 5 AM window
      final start = DateTime(
        reportDate.year,
        reportDate.month,
        reportDate.day,
        2,
        0,
      );
      final end = DateTime(
        reportDate.year,
        reportDate.month,
        reportDate.day,
        5,
        0,
      );

      final nightPoints = points
          .where((p) => p.timestamp.isAfter(start) && p.timestamp.isBefore(end))
          .map((p) => p.heartRate)
          .toList();

      if (nightPoints.isNotEmpty) {
        dailyRHRs[dateStr] = calculateRHRFromList(nightPoints);
      } else {
        // Absolute fallback: use the lowest 50 heart rate samples from the whole day
        final hRList = points.map((p) => p.heartRate).toList();
        if (hRList.isNotEmpty) {
          hRList.sort();
          final lowestPoints = hRList.sublist(0, math.min(50, hRList.length));
          dailyRHRs[dateStr] = calculateRHRFromList(lowestPoints);
        } else {
          dailyRHRs[dateStr] = 60; // Use a reasonable default instead of 65
        }
      }
    });

    return dailyRHRs;
  }

  // NEW: Calculate Daily HRVs from heart rate logs and daily questions
  static Map<String, int> calculateDailyHRVs(
    List<HealthDataPoint> allPoints,
    List<DailyQuestions> allQuestions,
  ) {
    Map<String, List<HealthDataPoint>> hrPointsByDate = {};
    Map<String, DailyQuestions> questionsByDate = {};

    for (var q in allQuestions) {
      final dateStr = q.date.toIso8601String().split('T')[0];
      questionsByDate[dateStr] = q;
    }

    for (var p in allPoints) {
      final dateStr = p.timestamp.toIso8601String().split('T')[0];
      hrPointsByDate.putIfAbsent(dateStr, () => []).add(p);
    }

    Map<String, int> dailyHRVs = {};

    hrPointsByDate.forEach((dateStr, points) {
      final questions = questionsByDate[dateStr];
      final reportDate = DateTime.parse(dateStr);

      if (questions?.bedtime != null && questions?.wakeTime != null) {
        final window = getSleepWindow(
          reportDate,
          questions!.bedtime!,
          questions.wakeTime!,
        );
        if (window != null) {
          final windowPoints = points
              .where(
                (p) =>
                    p.timestamp.isAfter(window['start']!) &&
                    p.timestamp.isBefore(window['end']!),
              )
              .map((p) => p.heartRate)
              .toList();

          if (windowPoints.length >= 2) {
            dailyHRVs[dateStr] = calculateHRVFromList(windowPoints);
            return;
          }
        }
      }

      // Fallback: 2 AM to 5 AM window
      final start = DateTime(
        reportDate.year,
        reportDate.month,
        reportDate.day,
        2,
        0,
      );
      final end = DateTime(
        reportDate.year,
        reportDate.month,
        reportDate.day,
        5,
        0,
      );

      final nightPoints = points
          .where((p) => p.timestamp.isAfter(start) && p.timestamp.isBefore(end))
          .map((p) => p.heartRate)
          .toList();

      if (nightPoints.length >= 2) {
        dailyHRVs[dateStr] = calculateHRVFromList(nightPoints);
      } else {
        // Absolute fallback: use the last 50 heart rate samples of the day
        final hRList = points.map((p) => p.heartRate).toList();
        if (hRList.length >= 2) {
          final lastPoints = hRList.sublist(math.max(0, hRList.length - 50));
          dailyHRVs[dateStr] = calculateHRVFromList(lastPoints);
        } else {
          dailyHRVs[dateStr] = 45; // Ultimate fallback
        }
      }
    });

    return dailyHRVs;
  }

  // NEW: Combined helper for MetricDetailScreen
  static Map<String, Map<String, int>> calculateDailyBaselines(
    List<HealthDataPoint> allPoints,
    List<DailyQuestions> allQuestions,
  ) {
    final rhrs = calculateDailyRHRs(allPoints, allQuestions);
    final hrvs = calculateDailyHRVs(allPoints, allQuestions);

    Map<String, Map<String, int>> results = {};

    Set<String> allDates = {...rhrs.keys, ...hrvs.keys};
    for (var date in allDates) {
      results[date] = {'rhr': rhrs[date] ?? 65, 'hrv': hrvs[date] ?? 45};
    }
    return results;
  }

  static double calculateTrend(List<Map<String, dynamic>> weeklyData) {
    if (weeklyData.length < 2) return 0.0;

    final todayValue = (weeklyData.last['value'] as double).toDouble();
    final yesterdayValue =
        (weeklyData[weeklyData.length - 2]['value'] as double).toDouble();

    if (yesterdayValue == 0) {
      return todayValue > 0 ? 100.0 : 0.0;
    }

    return ((todayValue - yesterdayValue) / yesterdayValue) * 100;
  }

  static double calculateTrendFromWeeklyData(
    List<Map<String, dynamic>> weeklyData,
  ) {
    if (weeklyData.length < 2) return 0.0;

    final todayValue = (weeklyData.last['value'] as double);
    final yesterdayValue =
        (weeklyData[weeklyData.length - 2]['value'] as double);

    if (yesterdayValue == 0) {
      return todayValue > 0 ? 100.0 : 0.0;
    }

    return ((todayValue - yesterdayValue) / yesterdayValue) * 100;
  }

  // NEW: Calculate RHR from a list of HR values during sleep
  static int calculateRHRFromList(List<int> hrValues) {
    if (hrValues.isEmpty) return 65; // Fallback

    // Sort to find the lowest values
    List<int> sortedValues = List.from(hrValues)..sort();

    // Take the lowest 20% of values and average them to avoid outliers
    int count = (sortedValues.length * 0.20)
        .clamp(1, sortedValues.length)
        .toInt();
    double sum = 0;
    for (int i = 0; i < count; i++) {
      sum += sortedValues[i];
    }

    return (sum / count).round();
  }

  // NEW: Calculate HRV (RMSSD approximation) from a list of HR values during sleep
  static int calculateHRVFromList(List<int> hrValues) {
    if (hrValues.length < 2) return 45; // Fallback

    // Simple RMSSD approximation from HR values
    // RMSSD = sqrt(mean(successive_differences^2))
    // Successive difference in ms = |(60000/hr1) - (60000/hr2)|

    double sumSquaredDiffs = 0;
    int count = 0;

    for (int i = 0; i < hrValues.length - 1; i++) {
      if (hrValues[i] > 0 && hrValues[i + 1] > 0) {
        double rr1 = 60000 / hrValues[i];
        double rr2 = 60000 / hrValues[i + 1];
        double diff = rr1 - rr2;
        sumSquaredDiffs += diff * diff;
        count++;
      }
    }

    if (count == 0 || sumSquaredDiffs == 0) return 45;

    int calculatedHRV = math.sqrt(sumSquaredDiffs / count).round();

    // If calculated HRV is extremely low (less than 20), it's likely due to
    // constant BPM samples (e.g. 60, 60, 60) from the sensor.
    // In this case, we return a more realistic minimum or a safe default.
    return calculatedHRV.clamp(25, 150);
  }

  // Helper to convert bedtime/waketime strings to DateTime objects
  static Map<String, DateTime>? getSleepWindow(
    DateTime reportDate,
    String bedtime,
    String wakeTime,
  ) {
    try {
      final bedParts = bedtime.split(':');
      final wakeParts = wakeTime.split(':');

      int bedHour = int.parse(bedParts[0]);
      int bedMinute = int.parse(bedParts[1]);
      int wakeHour = int.parse(wakeParts[0]);
      int wakeMinute = int.parse(wakeParts[1]);

      // Bedtime is usually on the day BEFORE the report date (or very early morning of)
      DateTime sleepStart = DateTime(
        reportDate.year,
        reportDate.month,
        reportDate.day,
        bedHour,
        bedMinute,
      );

      // If bedtime is late (e.g. 10 PM), and report is today,
      // sleep actually started yest evening.
      if (bedHour > 12) {
        sleepStart = sleepStart.subtract(const Duration(days: 1));
      }

      DateTime sleepEnd = DateTime(
        reportDate.year,
        reportDate.month,
        reportDate.day,
        wakeHour,
        wakeMinute,
      );

      // If sleep end is before sleep start, it means they woke up the next day relative to start
      if (sleepEnd.isBefore(sleepStart)) {
        sleepEnd = sleepEnd.add(const Duration(days: 1));
      }

      return {'start': sleepStart, 'end': sleepEnd};
    } catch (e) {
      print('Error parsing sleep window: $e');
      return null;
    }
  }
}

class SleepNeedResult {
  final double sleepNeed;
  final double recoveryPercent;
  final double baseSleepRequired;
  final double healthScore;
  final String hrvStatus;
  final String rhrStatus;

  SleepNeedResult({
    required this.sleepNeed,
    required this.recoveryPercent,
    required this.baseSleepRequired,
    required this.healthScore,
    required this.hrvStatus,
    required this.rhrStatus,
  });
}

class BaselineData {
  final int rhrBaseline;
  final int hrvBaseline;

  BaselineData({required this.rhrBaseline, required this.hrvBaseline});
}
