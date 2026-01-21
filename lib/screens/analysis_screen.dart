// analysis_screen.dart - UPDATED WITH REAL SLEEP AND RECOVERY DATA
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import 'package:zyora_final/services/ble_service.dart';
import 'package:zyora_final/local_storage_service.dart';
import 'package:zyora_final/services/ai_description_service.dart';
import 'package:zyora_final/services/health_calculations_service.dart';
import 'package:zyora_final/services/daily_questions_service.dart';
import 'package:zyora_final/services/user_profile_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnalysisScreen extends StatefulWidget {
  final BLEService bleService;

  const AnalysisScreen({super.key, required this.bleService});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;

  List<HealthDataPoint> _healthData = [];
  bool _isLoading = true;
  Map<String, dynamic> _analytics = {};
  final AIDescriptionService _aiService = AIDescriptionService();
  final DailyQuestionsService _dailyQuestionsService = DailyQuestionsService();
  final UserProfileService _userProfileService = UserProfileService();

  String _aiInsight = '';
  bool _isGeneratingInsight = false;
  UserProfile? _userProfile;
  DailyQuestions? _latestQuestions;
  int _selectedTimeRange = 365; // Default to 'All' to show all data
  Map<String, double> _correlations = {};
  Map<String, double> _stabilityIndices = {};
  bool _isCalculatingHealth = false;
  Map<String, Map<String, int>> _dailyCalculatedBaselines = {};
  BaselineData? _currentBaselines;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeController.forward();
    _slideController.forward();
    _loadUserData();
    _loadAnalyticsData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh data when screen comes into focus
    _loadAnalyticsData();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      _userProfile = await _userProfileService.getUserProfile();
      _latestQuestions = await _dailyQuestionsService.getLatestQuestions();

      // Debug logging
      print('👤 USER DATA LOADED:');
      print('   User Age: ${_userProfile?.age}');
      print(
        '   Latest Questions Sleep: ${_latestQuestions?.calculatedSleepDuration}',
      );
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  Widget _buildGradientBorderCard({
    required Widget child,
    double borderRadius = 20,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF000000),
            const Color.fromARGB(255, 9, 9, 9),
            const Color.fromARGB(255, 126, 126, 126).withOpacity(0.3),
            const Color.fromARGB(255, 9, 9, 9),
            const Color(0xFF000000),
          ],
          stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius - 1.5),
            color: const Color(0xFF0D0D0D).withOpacity(0.9),
          ),
          child: child,
        ),
      ),
    );
  }

  Future<void> _loadAnalyticsData() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final data = await widget.bleService.getAllHealthData();

      if (mounted) {
        setState(() {
          _healthData = data;
          // Filtering logic will happen in calculation
        });
      }

      await _calculateComprehensiveAnalytics();
      await _calculateCorrelations();
      await _calculateStabilityIndices();
      await _calculateMilestones();
      await _generateAIInsight();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading analytics data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _calculateCorrelations() async {
    if (_healthData.length < 5) return;

    // Simple correlation between Sleep and Recovery
    final sleepValues = _healthData.map((e) => e.sleep).toList();
    final recoveryValues = _healthData
        .map((e) => e.recovery.toDouble())
        .toList();

    // This is a simplified proxy for correlation
    _correlations['sleep_recovery'] = _calculatePearson(
      sleepValues,
      recoveryValues,
    );
  }

  double _calculatePearson(List<double> x, List<double> y) {
    if (x.isEmpty || y.isEmpty || x.length != y.length) return 0;
    int n = x.length;
    double sumX = x.reduce((a, b) => a + b);
    double sumY = y.reduce((a, b) => a + b);
    double sumXY = 0;
    double sumX2 = 0;
    double sumY2 = 0;
    for (int i = 0; i < n; i++) {
      sumXY += x[i] * y[i];
      sumX2 += x[i] * x[i];
      sumY2 += y[i] * y[i];
    }
    double numerator = n * sumXY - sumX * sumY;
    double denominator = sqrt(
      (n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY),
    );
    if (denominator == 0) return 0;
    return numerator / denominator;
  }

  Map<String, dynamic> _milestones = {};

  Future<void> _calculateMilestones() async {
    if (_healthData.isEmpty) return;

    int minRHR = 200;
    int maxHRV = 0;
    double maxSleep = 0;
    int bestRecovery = 0;

    for (var p in _healthData) {
      if (p.rhr > 0 && p.rhr < minRHR) minRHR = p.rhr;
      if (p.hrv > maxHRV) maxHRV = p.hrv;
      if (p.sleep > maxSleep) maxSleep = p.sleep;
      if (p.recovery > bestRecovery) bestRecovery = p.recovery;
    }

    setState(() {
      _milestones = {
        'minRHR': minRHR == 200 ? '--' : minRHR,
        'maxHRV': maxHRV == 0 ? '--' : maxHRV,
        'maxSleep': maxSleep == 0 ? '--' : maxSleep.toStringAsFixed(1),
        'bestRecovery': bestRecovery == 0 ? '--' : bestRecovery,
      };
    });
  }

  Future<void> _calculateStabilityIndices() async {
    if (_healthData.length < 3) return;

    final hrvValues = _healthData.map((e) => e.hrv.toDouble()).toList();
    final rhrValues = _healthData.map((e) => e.rhr.toDouble()).toList();
    final sleepValues = _healthData.map((e) => e.sleep).toList();

    setState(() {
      _stabilityIndices['hrv'] = _calculateCV(
        hrvValues,
      ); // Coefficient of Variation
      _stabilityIndices['rhr'] = _calculateCV(rhrValues);
      _stabilityIndices['sleep'] = _calculateCV(sleepValues);
    });
  }

  double _calculateCV(List<double> values) {
    if (values.isEmpty) return 0;
    double mean = values.reduce((a, b) => a + b) / values.length;
    if (mean == 0) return 0;
    double variance =
        values.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) /
        values.length;
    double stdDev = sqrt(variance);
    // CV = (stdDev / mean) * 100. Lower is more stable.
    // We'll return 100 - CV to make "Higher = More Stable"
    return (100 - (stdDev / mean * 100)).clamp(0, 100);
  }

  Future<void> _generateAIInsight() async {
    if (_healthData.isEmpty) return;

    setState(() {
      _isGeneratingInsight = true;
    });

    try {
      final latestData = _healthData.isNotEmpty ? _healthData.first : null;
      if (latestData != null) {
        var healthData = HealthData(
          heartRate: latestData.heartRate,
          steps: latestData.steps,
          spo2: latestData.spo2,
          calories: latestData.calories,
          sleep: latestData.sleep,
          recovery: latestData.recovery,
          stress: latestData.stress,
          rhr: latestData.rhr,
          hrv: latestData.hrv,
          bodyTemperature: latestData.bodyTemperature,
          breathingRate: latestData.breathingRate,
        );

        // SYNC SMART METRICS FROM STORAGE (Calculated by Dashboard)
        // This ensures AI chat doesn't see old/raw defaults (like 60/45/85)
        try {
          final prefs = await SharedPreferences.getInstance();
          final todayStr = DateTime.now().toIso8601String().split('T')[0];
          final lastScoreDate = prefs.getString('last_score_date');

          if (lastScoreDate == todayStr) {
            final smartRecovery = prefs.getInt('daily_recovery_score');
            final smartRHR = prefs.getInt('daily_calculated_rhr');
            final smartHRV = prefs.getInt('daily_calculated_hrv');

            if (smartRecovery != null && smartRHR != null && smartHRV != null) {
              healthData = healthData.copyWith(
                recovery: smartRecovery,
                rhr: smartRHR,
                hrv: smartHRV,
              );
              print(
                '🔮 AI context synced with smart metrics: Recovery=$smartRecovery, RHR=$smartRHR, HRV=$smartHRV',
              );
            }
          }
        } catch (e) {
          print('Error syncing AI smart metrics: $e');
        }

        final insight = await _aiService.getMetricDescription(
          metricName: 'Overall Health',
          currentValue: '${_analytics['healthScore'] ?? 85}',
          unit: 'Score',
          currentData: healthData,
        );

        if (mounted) {
          setState(() {
            _aiInsight = insight;
            _isGeneratingInsight = false;
          });
        }
      }
    } catch (e) {
      print('Error generating AI insight: $e');
      if (mounted) {
        setState(() {
          _isGeneratingInsight = false;
          _aiInsight =
              'Analyzing your health patterns to provide personalized insights...';
        });
      }
    }
  }

  Future<void> _calculateComprehensiveAnalytics() async {
    if (_healthData.isEmpty) return;

    try {
      setState(() {
        _isCalculatingHealth = true;
      });

      // Filter health data based on selected time range
      final now = DateTime.now();
      final filteredData = _healthData.where((e) {
        final daysDiff = now.difference(e.timestamp).inDays;
        return daysDiff < _selectedTimeRange;
      }).toList();

      if (filteredData.isEmpty) {
        setState(() {
          _isCalculatingHealth = false;
          _isLoading = false;
        });
        return;
      }

      // Get latest questions data for sleep calculation
      _latestQuestions = await _dailyQuestionsService.getLatestQuestions();
      double? sleepFromForm = _latestQuestions?.calculatedSleepDuration;

      final allQuestions = await _dailyQuestionsService.getAllQuestions();
      _currentBaselines = HealthCalculationsService.calculateBaselines(
        _healthData,
        allQuestions,
      );

      final latestDataPoint = _healthData.first;

      // SMART TODAY METRICS: DON'T TRUST LATEST DATA POINT (it's often stale/default)
      // Use the same Daily mapping logic the dashboard uses
      _dailyCalculatedBaselines =
          HealthCalculationsService.calculateDailyBaselines(
            _healthData,
            allQuestions,
          );
      final todayKey = DateTime.now().toIso8601String().split('T')[0];
      final dayMetrics = _dailyCalculatedBaselines[todayKey];

      // SYNC SMART METRICS FROM STORAGE (Calculated by Dashboard)
      // This ensures Dashboard and Analysis show IDENTICAL scores
      int rhrToday = dayMetrics?['rhr'] ?? latestDataPoint.rhr;
      int hrvToday = dayMetrics?['hrv'] ?? latestDataPoint.hrv;
      double? recoverySync;
      double? healthSync;

      try {
        final prefs = await SharedPreferences.getInstance();
        final todayStr = DateTime.now().toIso8601String().split('T')[0];
        final lastScoreDate = prefs.getString('last_score_date');

        if (lastScoreDate == todayStr) {
          final smartRecovery = prefs.getInt('daily_recovery_score');
          final smartRHR = prefs.getInt('daily_calculated_rhr');
          final smartHRV = prefs.getInt('daily_calculated_hrv');
          final smartHealth = prefs.getInt('daily_health_score');

          if (smartRHR != null) rhrToday = smartRHR;
          if (smartHRV != null) hrvToday = smartHRV;
          if (smartRecovery != null) recoverySync = smartRecovery.toDouble();
          if (smartHealth != null) healthSync = smartHealth.toDouble();

          print(
            '📦 Syncing Analysis with Dashboard: Recovery=$recoverySync, RHR=$rhrToday, HRV=$hrvToday',
          );
        }
      } catch (e) {
        print('Error syncing with SharedPreferences: $e');
      }

      // MEDICAL-GRADE CALCULATION WITH HRV & RHR (FULLY SYNCED WITH DASHBOARD)
      final calcResult = HealthCalculationsService.calculateSleepNeed(
        age: _userProfile?.age ?? 25,
        rhrBaseline: _currentBaselines?.rhrBaseline ?? 65,
        rhrToday: rhrToday,
        hrvBaseline: _currentBaselines?.hrvBaseline ?? 45,
        hrvToday: hrvToday,
        steps: latestDataPoint.steps,
        calories: latestDataPoint.calories,
        sleepFromForm: sleepFromForm,
        spo2: latestDataPoint.spo2,
        stress: latestDataPoint.stress,
        bodyTemperature: latestDataPoint.bodyTemperature,
        breathingRate: latestDataPoint.breathingRate,
        dailyQuestions: _latestQuestions,
      );

      // Use synced values if available, otherwise use calculation
      final recoveryPercent = recoverySync ?? calcResult.recoveryPercent;
      final healthScore = healthSync ?? calcResult.healthScore;
      final sleepNeed = calcResult.sleepNeed;

      // Calculate averages for display only (not for the main health score)
      final avgHeartRate =
          _healthData.map((e) => e.heartRate).reduce((a, b) => a + b) /
          _healthData.length;
      final avgRHR =
          _healthData.map((e) => e.rhr).reduce((a, b) => a + b) /
          _healthData.length;
      final avgHRV =
          _healthData.map((e) => e.hrv).reduce((a, b) => a + b) /
          _healthData.length;
      final avgSleep =
          _healthData.map((e) => e.sleep).reduce((a, b) => a + b) /
          _healthData.length;
      final avgRecovery =
          _healthData.map((e) => e.recovery).reduce((a, b) => a + b) /
          _healthData.length;
      final avgStress =
          _healthData.map((e) => e.stress).reduce((a, b) => a + b) /
          _healthData.length;
      final avgSPO2 =
          _healthData.map((e) => e.spo2).reduce((a, b) => a + b) /
          _healthData.length;
      final avgTemperature =
          _healthData.map((e) => e.bodyTemperature).reduce((a, b) => a + b) /
          _healthData.length;

      // Prepare all chart data with await
      final sleepData = await _prepareRealTimeSleepAnalysisData();
      final heartRateData = _prepareRealTimeHeartRateAnalysisData();
      final recoveryData = await _prepareRealTimeRecoveryAnalysisData();
      final stressData = _prepareRealTimeStressAnalysisData();
      final hrvData = _prepareRealTimeHRVAnalysisData();

      if (mounted) {
        setState(() {
          _analytics = {
            // USE THE MEDICAL-GRADE CALCULATION RESULTS (same as dashboard)
            'healthScore': healthScore,
            'recoveryPercent': recoveryPercent,
            'sleepNeed': sleepNeed,

            // Display averages for informational purposes
            'avgHeartRate': avgHeartRate.round(),
            'avgRHR': avgRHR.round(),
            'avgHRV': avgHRV.round(),
            'avgSleep': avgSleep,
            'avgRecovery': avgRecovery.round(),
            'avgStress': avgStress.round(),
            'avgSPO2': avgSPO2.round(),
            'avgTemperature': avgTemperature,
            'totalDataPoints': _healthData.length,
            'dataRange':
                '${_healthData.last.timestamp.difference(_healthData.first.timestamp).inDays} days',
            'trends': {
              'heartRate': _calculateTrend(
                avgHeartRate,
                _getPreviousAverage(_healthData, 'heartRate'),
              ),
              'rhr': _getRHRStatus(avgRHR.round()),
              'hrv': _getHRVStatus(avgHRV.round()),
              'sleep': _calculateTrend(
                avgSleep,
                _getPreviousAverage(_healthData, 'sleep'),
              ),
              'recovery': _calculateTrend(
                avgRecovery,
                _getPreviousAverage(_healthData, 'recovery'),
              ),
            },

            // UPDATED: Use real-time data for graphs with await
            'sleepData': sleepData,
            'heartRateData': heartRateData,
            'recoveryData': recoveryData,
            'stressData': stressData,
            'hrvData': hrvData,

            'vitalSigns': _calculateVitalSignsAnalysis(),
            'weeklySummary': _calculateWeeklySummary(),
            'healthRecommendations': _generateHealthRecommendations(
              healthScore,
              avgSleep,
              avgRHR,
              avgHRV,
              avgStress,
              avgSPO2,
            ),

            // LATEST REAL-TIME VALUES FOR DISPLAY
            'latestHeartRate': latestDataPoint.heartRate,
            'latestSteps': latestDataPoint.steps,
            'latestSPO2': latestDataPoint.spo2,
            'latestCalories': latestDataPoint.calories,
            'latestSleep': sleepFromForm ?? latestDataPoint.sleep,
            'latestRecovery': recoveryPercent
                .round(), // Use calculated recovery
            'latestStress': latestDataPoint.stress,
            'latestRHR': latestDataPoint.rhr,
            'latestHRV': latestDataPoint.hrv,
            'latestTemperature': latestDataPoint.bodyTemperature,
            'latestBreathingRate': latestDataPoint.breathingRate,
          };
          _isCalculatingHealth = false;
        });
      }

      // Debug logging to verify all data
      print('🔍 ANALYTICS DATA VERIFICATION:');
      print('🎯 Health Score: ${healthScore.toStringAsFixed(1)}');
      print('💓 Recovery: ${recoveryPercent.toStringAsFixed(1)}%');
      print('🛌 Sleep Need: ${sleepNeed.toStringAsFixed(1)}h');
      print('📊 Latest Sleep: ${_analytics['latestSleep']}h');
      print('📊 Latest Recovery: ${_analytics['latestRecovery']}%');
      print('📊 Sleep Data Points: ${sleepData.length}');
      print('📊 Recovery Data Points: ${recoveryData.length}');
    } catch (e) {
      print('❌ Error in comprehensive analytics: $e');
      if (mounted) {
        setState(() {
          _isCalculatingHealth = false;
        });
      }
    }
  }

  double _getPreviousAverage(List<HealthDataPoint> data, String metric) {
    if (data.length < 2) return 0;
    final previousData = data.sublist(1);
    switch (metric) {
      case 'heartRate':
        return previousData.map((e) => e.heartRate).reduce((a, b) => a + b) /
            previousData.length;
      case 'sleep':
        return previousData.map((e) => e.sleep).reduce((a, b) => a + b) /
            previousData.length;
      case 'recovery':
        return previousData.map((e) => e.recovery).reduce((a, b) => a + b) /
            previousData.length;
      default:
        return 0;
    }
  }

  String _calculateTrend(double current, double previous) {
    if (previous == 0) return 'Stable';
    final change = ((current - previous) / previous * 100);
    if (change.abs() < 2) return 'Stable';
    return '${change > 0 ? '+' : ''}${change.abs().toStringAsFixed(1)}%';
  }

  String _getRHRStatus(int rhr) {
    if (rhr < 60) return 'Low';
    if (rhr <= 100) return 'Normal';
    return 'High';
  }

  String _getHRVStatus(int hrv) {
    if (hrv >= 50) return 'Good';
    if (hrv >= 20) return 'Average';
    return 'Low';
  }

  Map<String, dynamic> _calculateVitalSignsAnalysis() {
    final latest = _healthData.isNotEmpty ? _healthData.first : null;
    if (latest == null) return {};

    return {
      'heartRate': {
        'value': latest.heartRate,
        'status': latest.heartRate <= 60
            ? 'Low'
            : latest.heartRate <= 100
            ? 'Normal'
            : 'High',
        'zone': _getHeartRateZone(latest.heartRate, _userProfile?.age ?? 25),
      },
      'spo2': {
        'value': latest.spo2,
        'status': latest.spo2 >= 95
            ? 'Excellent'
            : latest.spo2 >= 90
            ? 'Fair'
            : 'Low',
      },
      'temperature': {
        'value': latest.bodyTemperature,
        'status': latest.bodyTemperature >= 37.5
            ? 'High'
            : latest.bodyTemperature >= 36.0
            ? 'Normal'
            : 'Low',
      },
    };
  }

  String _getHeartRateZone(int heartRate, int age) {
    final maxHR = 220 - age;
    final percentage = (heartRate / maxHR) * 100;

    if (percentage < 50) return 'Rest';
    if (percentage < 60) return 'Very Light';
    if (percentage < 70) return 'Light';
    if (percentage < 80) return 'Moderate';
    if (percentage < 90) return 'Hard';
    return 'Maximum';
  }

  Map<String, dynamic> _calculateWeeklySummary() {
    final weeklyData = _healthData
        .where(
          (e) => e.timestamp.isAfter(
            DateTime.now().subtract(Duration(days: _selectedTimeRange)),
          ),
        )
        .toList();

    if (weeklyData.isEmpty) return {};

    final totalSteps = weeklyData.map((e) => e.steps).reduce((a, b) => a + b);
    final totalCalories = weeklyData
        .map((e) => e.calories)
        .reduce((a, b) => a + b);
    final avgDailyRecovery =
        weeklyData.map((e) => e.recovery).reduce((a, b) => a + b) /
        weeklyData.length;
    final avgDailyStress =
        weeklyData.map((e) => e.stress).reduce((a, b) => a + b) /
        weeklyData.length;

    return {
      'totalSteps': totalSteps,
      'totalCalories': totalCalories,
      'avgDailyRecovery': avgDailyRecovery.round(),
      'avgDailyStress': avgDailyStress.round(),
      'activeDays': weeklyData.where((e) => e.steps > 5000).length,
      'goodSleepDays': weeklyData.where((e) => e.sleep >= 7).length,
    };
  }

  List<String> _generateHealthRecommendations(
    double healthScore,
    double sleep,
    double rhr,
    double hrv,
    double stress,
    double spo2,
  ) {
    final recommendations = <String>[];

    if (sleep < 7) {
      recommendations.add('Aim for 7-9 hours of quality sleep each night');
    }

    if (rhr > 70) {
      recommendations.add(
        'Consider incorporating more cardio exercise to lower resting heart rate',
      );
    }

    if (hrv < 40) {
      recommendations.add(
        'Practice stress-reduction techniques like meditation or deep breathing',
      );
    }

    if (stress > 50) {
      recommendations.add(
        'Take regular breaks and practice mindfulness to manage stress levels',
      );
    }

    if (spo2 < 95) {
      recommendations.add(
        'Ensure proper breathing techniques and consider air quality improvements',
      );
    }

    if (healthScore < 70) {
      recommendations.add(
        'Focus on consistent sleep, exercise, and stress management for overall health improvement',
      );
    }

    return recommendations;
  }

  // UPDATED: REAL SLEEP DATA PREPARATION
  Future<List<FlSpot>> _prepareRealTimeSleepAnalysisData() async {
    if (_healthData.isEmpty) return [];

    // Get last data based on range
    final weeklyData = _healthData
        .where(
          (e) => e.timestamp.isAfter(
            DateTime.now().subtract(Duration(days: _selectedTimeRange)),
          ),
        )
        .toList();

    if (weeklyData.isEmpty) return [];

    // Group by day and get sleep from daily questions
    final dailySleep = <String, double>{};

    for (var point in weeklyData) {
      final dayKey =
          '${point.timestamp.year}-${point.timestamp.month}-${point.timestamp.day}';

      // Only process if we haven't already added this day
      if (!dailySleep.containsKey(dayKey)) {
        try {
          // Try to get sleep from daily questions first
          final questions = await _dailyQuestionsService.getQuestionsForDate(
            point.timestamp,
          );

          if (questions != null && questions.calculatedSleepDuration != null) {
            dailySleep[dayKey] = questions.calculatedSleepDuration!;
            print(
              '📊 SLEEP GRAPH: Using form data for $dayKey: ${questions.calculatedSleepDuration!}h',
            );
          } else {
            // Fallback to data point sleep if no questions data
            dailySleep[dayKey] = point.sleep;
            print(
              '📊 SLEEP GRAPH: Using device data for $dayKey: ${point.sleep}h',
            );
          }
        } catch (e) {
          print('Error getting sleep data for $dayKey: $e');
          // Fallback to data point sleep on error
          dailySleep[dayKey] = point.sleep;
        }
      }
    }

    // Sort by date and create spots
    final sortedDays = dailySleep.keys.toList()..sort();
    final spots = <FlSpot>[];

    for (int i = 0; i < sortedDays.length; i++) {
      final dayKey = sortedDays[i];
      final sleepValue = dailySleep[dayKey]!;
      spots.add(FlSpot(i.toDouble(), sleepValue));
    }

    print('📊 SLEEP GRAPH: Final data points: $spots');
    return spots;
  }

  // UPDATED: REAL RECOVERY DATA PREPARATION
  Future<List<FlSpot>> _prepareRealTimeRecoveryAnalysisData() async {
    if (_healthData.isEmpty) return [];

    final weeklyData = _healthData
        .where(
          (e) => e.timestamp.isAfter(
            DateTime.now().subtract(Duration(days: _selectedTimeRange)),
          ),
        )
        .toList();

    if (weeklyData.isEmpty) return [];

    final dailyRecovery = <String, double>{};

    for (var point in weeklyData) {
      final dayKey =
          '${point.timestamp.year}-${point.timestamp.month}-${point.timestamp.day}';

      // Only process if we haven't already added this day
      if (!dailyRecovery.containsKey(dayKey)) {
        try {
          // Use the PRE-CALCULATED smart metrics for this day
          final dayMetrics =
              _dailyCalculatedBaselines[dayKey] ?? {'rhr': 65, 'hrv': 45};
          final rhrToUse = dayMetrics['rhr'] ?? 65;
          final hrvToUse = dayMetrics['hrv'] ?? 45;

          // Get daily questions for sleep calculation
          final dailyQuestions = await _dailyQuestionsService
              .getQuestionsForDate(point.timestamp);
          double? sleepFromForm = dailyQuestions?.calculatedSleepDuration;

          // Calculate recovery for this specific data point using smart baselines
          final result = HealthCalculationsService.calculateSleepNeed(
            age: _userProfile?.age ?? 25,
            rhrBaseline: _currentBaselines?.rhrBaseline ?? 65,
            rhrToday: rhrToUse,
            hrvBaseline: _currentBaselines?.hrvBaseline ?? 45,
            hrvToday: hrvToUse,
            steps: point.steps,
            calories: point.calories,
            sleepFromForm: sleepFromForm,
            spo2: point.spo2,
            stress: point.stress,
            bodyTemperature: point.bodyTemperature,
            breathingRate: point.breathingRate,
            dailyQuestions: dailyQuestions,
          );

          // Use the calculated recovery percentage
          dailyRecovery[dayKey] = result.recoveryPercent.toDouble();
          print(
            '📊 RECOVERY GRAPH: Calculated recovery for $dayKey: ${result.recoveryPercent.toStringAsFixed(1)}%',
          );
        } catch (e) {
          print('Error calculating recovery for $dayKey: $e');
          // Fallback to device recovery data (strict, no random generation)
          dailyRecovery[dayKey] = point.recovery.toDouble();
        }
      }
    }

    final sortedDays = dailyRecovery.keys.toList()..sort();
    final spots = <FlSpot>[];

    for (int i = 0; i < sortedDays.length; i++) {
      final dayKey = sortedDays[i];
      final recoveryValue = dailyRecovery[dayKey]!;
      spots.add(FlSpot(i.toDouble(), recoveryValue));
    }

    print('📊 RECOVERY GRAPH: Final data points: $spots');
    return spots;
  }

  List<FlSpot> _prepareRealTimeHeartRateAnalysisData() {
    if (_healthData.isEmpty) return [];

    final weeklyData = _healthData
        .where(
          (e) => e.timestamp.isAfter(
            DateTime.now().subtract(Duration(days: _selectedTimeRange)),
          ),
        )
        .toList();

    if (weeklyData.isEmpty) return [];

    final dailyHR = <String, int>{};
    for (var point in weeklyData) {
      final dayKey =
          '${point.timestamp.year}-${point.timestamp.month}-${point.timestamp.day}';
      // Use the latest value for each day
      if (!dailyHR.containsKey(dayKey)) {
        dailyHR[dayKey] = point.heartRate;
      }
    }

    final sortedDays = dailyHR.keys.toList()..sort();
    final spots = <FlSpot>[];

    for (int i = 0; i < sortedDays.length; i++) {
      final dayKey = sortedDays[i];
      final hrValue = dailyHR[dayKey]!;
      spots.add(FlSpot(i.toDouble(), hrValue.toDouble()));
    }

    return spots;
  }

  List<FlSpot> _prepareRealTimeStressAnalysisData() {
    if (_healthData.isEmpty) return [];

    final weeklyData = _healthData
        .where(
          (e) => e.timestamp.isAfter(
            DateTime.now().subtract(Duration(days: _selectedTimeRange)),
          ),
        )
        .toList();

    if (weeklyData.isEmpty) return [];

    final dailyStress = <String, int>{};
    for (var point in weeklyData) {
      final dayKey =
          '${point.timestamp.year}-${point.timestamp.month}-${point.timestamp.day}';
      // Use the latest value for each day
      if (!dailyStress.containsKey(dayKey)) {
        dailyStress[dayKey] = point.stress;
      }
    }

    final sortedDays = dailyStress.keys.toList()..sort();
    final spots = <FlSpot>[];

    for (int i = 0; i < sortedDays.length; i++) {
      final dayKey = sortedDays[i];
      final stressValue = dailyStress[dayKey]!;
      spots.add(FlSpot(i.toDouble(), stressValue.toDouble()));
    }

    return spots;
  }

  List<FlSpot> _prepareRealTimeHRVAnalysisData() {
    if (_healthData.isEmpty) return [];

    final weeklyData = _healthData
        .where(
          (e) => e.timestamp.isAfter(
            DateTime.now().subtract(Duration(days: _selectedTimeRange)),
          ),
        )
        .toList();

    if (weeklyData.isEmpty) return [];

    final dailyHRV = <String, int>{};
    for (var point in weeklyData) {
      final dayKey =
          '${point.timestamp.year}-${point.timestamp.month}-${point.timestamp.day}';
      // Use the LATEST smart calculated value for each day
      if (!dailyHRV.containsKey(dayKey)) {
        final dayCalculated = _dailyCalculatedBaselines[dayKey];
        dailyHRV[dayKey] = dayCalculated?['hrv'] ?? point.hrv;
      }
    }

    final sortedDays = dailyHRV.keys.toList()..sort();
    final spots = <FlSpot>[];

    for (int i = 0; i < sortedDays.length; i++) {
      final dayKey = sortedDays[i];
      final hrvValue = dailyHRV[dayKey]!;
      spots.add(FlSpot(i.toDouble(), hrvValue.toDouble()));
    }

    return spots;
  }

  // PROFESSIONAL CHART BUILDING METHODS (SAME UI)
  Widget _buildSleepAnalysisChart() {
    final sleepData = _analytics['sleepData'] as List<FlSpot>? ?? [];
    final latestSleep = _analytics['latestSleep'] ?? 7.0;

    if (sleepData.isEmpty) {
      return _buildChartPlaceholder(
        'Sleep data not available',
        Icons.nightlight_round_rounded,
      );
    }

    final (minY, maxY) = _calculateChartYRange(
      sleepData.map((e) => e.y).toList(),
      'sleep',
    );
    final yAxisInterval = _calculateChartInterval(maxY - minY, 'sleep');

    return _buildGradientBorderCard(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18.5),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1A1A1A).withOpacity(0.8),
              const Color(0xFF0D0D0D).withOpacity(0.9),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Sleep Analysis',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFE8E8E8),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: latestSleep >= 7
                        ? Colors.green.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: latestSleep >= 7
                          ? Colors.green.withOpacity(0.3)
                          : Colors.orange.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    'Latest: ${latestSleep.toStringAsFixed(1)}h',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: latestSleep >= 7 ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  clipData: const FlClipData.all(),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    drawHorizontalLine: true,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: const Color(0xFF333333),
                        strokeWidth: 1,
                      );
                    },
                    checkToShowHorizontalLine: (value) {
                      return (value - minY) % yAxisInterval < 0.1;
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: _selectedTimeRange > 30
                            ? 30.0
                            : (_selectedTimeRange > 7 ? 5.0 : 1.0),
                        getTitlesWidget: (value, meta) {
                          final int intInterval = (_selectedTimeRange > 30
                              ? 30
                              : (_selectedTimeRange > 7 ? 5 : 1));
                          if (value.toInt() % intInterval != 0) {
                            return const SizedBox();
                          }
                          if (value >= 0 && value < sleepData.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                _getDayNameForIndex(value.toInt()),
                                style: const TextStyle(
                                  color: Color(0xFFA0A0A0),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: yAxisInterval,
                        getTitlesWidget: (value, meta) {
                          if ((value - minY) % yAxisInterval < 0.1 ||
                              value == minY ||
                              value == maxY) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Text(
                                '${value.toInt()}h',
                                style: const TextStyle(
                                  color: Color(0xFFA0A0A0),
                                  fontSize: 11,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: const Border(
                      bottom: BorderSide(color: Color(0xFF333333), width: 1),
                      left: BorderSide(color: Color(0xFF333333), width: 1),
                    ),
                  ),
                  minY: minY,
                  maxY: maxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: sleepData,
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: Colors.blue,
                      barWidth: 3,
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.blue.withOpacity(0.3),
                            Colors.blue.withOpacity(0.05),
                          ],
                        ),
                      ),
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 3,
                            color: Colors.white,
                            strokeWidth: 2,
                            strokeColor: Colors.blue,
                          );
                        },
                      ),
                    ),
                    // Optimal sleep reference line
                    LineChartBarData(
                      spots: [
                        FlSpot(0, 8),
                        FlSpot((sleepData.length - 1).toDouble(), 8),
                      ],
                      isCurved: false,
                      color: Colors.green.withOpacity(0.6),
                      barWidth: 2,
                      dashArray: [5, 5],
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem(Colors.blue, 'Actual Sleep'),
                const SizedBox(width: 20),
                _buildLegendItem(Colors.green, 'Optimal (8h)'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeartRateAnalysisChart() {
    final hrData = _analytics['heartRateData'] as List<FlSpot>? ?? [];
    final latestHR = _analytics['latestHeartRate'] ?? 72;

    if (hrData.isEmpty) {
      return _buildChartPlaceholder(
        'Heart rate data not available',
        Icons.favorite_rounded,
      );
    }

    final (minY, maxY) = _calculateChartYRange(
      hrData.map((e) => e.y).toList(),
      'heartRate',
    );
    final yAxisInterval = _calculateChartInterval(maxY - minY, 'heartRate');

    return _buildGradientBorderCard(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18.5),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1A1A1A).withOpacity(0.8),
              const Color(0xFF0D0D0D).withOpacity(0.9),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Heart Rate Trend',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFE8E8E8),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: latestHR <= 70
                        ? Colors.green.withOpacity(0.1)
                        : latestHR <= 85
                        ? Colors.orange.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: latestHR <= 70
                          ? Colors.green.withOpacity(0.3)
                          : latestHR <= 85
                          ? Colors.orange.withOpacity(0.3)
                          : Colors.red.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    'Latest: ${latestHR}BPM',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: latestHR <= 70
                          ? Colors.green
                          : latestHR <= 85
                          ? Colors.orange
                          : Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  clipData: const FlClipData.all(),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    drawHorizontalLine: true,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: const Color(0xFF333333),
                        strokeWidth: 1,
                      );
                    },
                    checkToShowHorizontalLine: (value) {
                      return (value - minY) % yAxisInterval < 0.1;
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          if (value >= 0 && value < hrData.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                _getDayNameForIndex(value.toInt()),
                                style: const TextStyle(
                                  color: Color(0xFFA0A0A0),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: yAxisInterval,
                        getTitlesWidget: (value, meta) {
                          if ((value - minY) % yAxisInterval < 0.1 ||
                              value == minY ||
                              value == maxY) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Text(
                                value.toInt().toString(),
                                style: const TextStyle(
                                  color: Color(0xFFA0A0A0),
                                  fontSize: 11,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: const Border(
                      bottom: BorderSide(color: Color(0xFF333333), width: 1),
                      left: BorderSide(color: Color(0xFF333333), width: 1),
                    ),
                  ),
                  minY: minY,
                  maxY: maxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: hrData,
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: Colors.red,
                      barWidth: 3,
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.red.withOpacity(0.3),
                            Colors.red.withOpacity(0.05),
                          ],
                        ),
                      ),
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 3,
                            color: Colors.white,
                            strokeWidth: 2,
                            strokeColor: Colors.red,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStressRecoveryChart() {
    final stressData = _analytics['stressData'] as List<FlSpot>? ?? [];
    final recoveryData = _analytics['recoveryData'] as List<FlSpot>? ?? [];
    final latestRecovery = _analytics['latestRecovery'] ?? 85;
    final latestStress = _analytics['latestStress'] ?? 30;

    if (stressData.isEmpty && recoveryData.isEmpty) {
      return _buildChartPlaceholder(
        'Stress/Recovery data not available',
        Icons.psychology_rounded,
      );
    }

    final allValues = [
      ...stressData.map((e) => e.y),
      ...recoveryData.map((e) => e.y),
    ];
    final (minY, maxY) = _calculateChartYRange(allValues, 'percentage');
    final yAxisInterval = _calculateChartInterval(maxY - minY, 'percentage');

    return _buildGradientBorderCard(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18.5),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1A1A1A).withOpacity(0.8),
              const Color(0xFF0D0D0D).withOpacity(0.9),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Stress vs Recovery',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFE8E8E8),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.purple.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    'Latest: R${latestRecovery}% S$latestStress',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.purple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  clipData: const FlClipData.all(),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    drawHorizontalLine: true,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: const Color(0xFF333333),
                        strokeWidth: 1,
                      );
                    },
                    checkToShowHorizontalLine: (value) {
                      return (value - minY) % yAxisInterval < 0.1;
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final maxLength =
                              stressData.length > recoveryData.length
                              ? stressData.length
                              : recoveryData.length;
                          if (value >= 0 && value < maxLength) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                _getDayNameForIndex(value.toInt()),
                                style: const TextStyle(
                                  color: Color(0xFFA0A0A0),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: yAxisInterval,
                        getTitlesWidget: (value, meta) {
                          if ((value - minY) % yAxisInterval < 0.1 ||
                              value == minY ||
                              value == maxY) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Text(
                                '${value.toInt()}%',
                                style: const TextStyle(
                                  color: Color(0xFFA0A0A0),
                                  fontSize: 11,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: const Border(
                      bottom: BorderSide(color: Color(0xFF333333), width: 1),
                      left: BorderSide(color: Color(0xFF333333), width: 1),
                    ),
                  ),
                  minY: minY,
                  maxY: maxY,
                  lineBarsData: [
                    if (stressData.isNotEmpty)
                      LineChartBarData(
                        spots: stressData,
                        isCurved: true,
                        curveSmoothness: 0.3,
                        color: Colors.orange,
                        barWidth: 3,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, barData, index) {
                            return FlDotCirclePainter(
                              radius: 3,
                              color: Colors.white,
                              strokeWidth: 2,
                              strokeColor: Colors.orange,
                            );
                          },
                        ),
                      ),
                    if (recoveryData.isNotEmpty)
                      LineChartBarData(
                        spots: recoveryData,
                        isCurved: true,
                        curveSmoothness: 0.3,
                        color: Colors.teal,
                        barWidth: 3,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, barData, index) {
                            return FlDotCirclePainter(
                              radius: 3,
                              color: Colors.white,
                              strokeWidth: 2,
                              strokeColor: Colors.teal,
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (stressData.isNotEmpty)
                  _buildLegendItem(Colors.orange, 'Stress Level'),
                if (stressData.isNotEmpty && recoveryData.isNotEmpty)
                  const SizedBox(width: 20),
                if (recoveryData.isNotEmpty)
                  _buildLegendItem(Colors.teal, 'Recovery Score'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // UTILITY METHODS FOR PROFESSIONAL CHARTS
  (double, double) _calculateChartYRange(
    List<double> values,
    String metricType,
  ) {
    if (values.isEmpty) return (0, 100);

    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);

    final range = maxVal - minVal;
    final padding = range * 0.15;

    double niceMin, niceMax;

    switch (metricType) {
      case 'heartRate':
        niceMin = (minVal - padding).clamp(40, double.infinity);
        niceMax = (maxVal + padding).clamp(niceMin + 10, 200);
        break;
      case 'sleep':
        niceMin = 0;
        niceMax = 12;
        break;
      case 'percentage':
        niceMin = 0;
        niceMax = 100;
        break;
      default:
        niceMin = max(0, minVal - padding);
        niceMax = maxVal + padding;
    }

    if (niceMax - niceMin < 1) {
      niceMax = niceMin + 10;
    }

    return (niceMin, niceMax);
  }

  double _calculateChartInterval(double range, String metricType) {
    if (range == 0) return 1.0;

    final double exponent = (log(range) / ln10).floorToDouble();
    final double fraction = range / pow(10, exponent);

    double niceFraction;
    if (fraction <= 1) {
      niceFraction = 1.0;
    } else if (fraction <= 2) {
      niceFraction = 2.0;
    } else if (fraction <= 5) {
      niceFraction = 5.0;
    } else {
      niceFraction = 10.0;
    }

    double interval = niceFraction * pow(10, exponent).toDouble();

    switch (metricType) {
      case 'heartRate':
        interval = interval.clamp(5, 20);
        break;
      case 'sleep':
        interval = 2;
        break;
      case 'percentage':
        interval = 20;
        break;
      default:
        interval = interval.clamp(1, 20);
    }

    return interval;
  }

  String _getDayNameForIndex(int index) {
    final now = DateTime.now();
    final targetDate = now.subtract(
      Duration(days: (_selectedTimeRange - 1) - index),
    );
    switch (targetDate.weekday) {
      case 1:
        return 'Mon';
      case 2:
        return 'Tue';
      case 3:
        return 'Wed';
      case 4:
        return 'Thu';
      case 5:
        return 'Fri';
      case 6:
        return 'Sat';
      case 7:
        return 'Sun';
      default:
        return '';
    }
  }

  Widget _buildChartPlaceholder(String message, IconData icon) {
    return _buildGradientBorderCard(
      child: Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18.5),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1A1A1A).withOpacity(0.8),
              const Color(0xFF0D0D0D).withOpacity(0.9),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFFA0A0A0), size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFFA0A0A0)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 12,
            color: const Color(0xFFE8E8E8),
          ),
        ),
      ],
    );
  }

  // Build circular rings for quick overview
  Widget _buildCircularRing({
    required double value,
    required String title,
    required String subtitle,
    required Color color,
    double size = 100,
  }) {
    return Container(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ring background
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.2), width: 6),
            ),
          ),
          // Progress ring
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: value / 100,
              strokeWidth: 6,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          // Content
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${value.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: size * 0.2,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: size * 0.1,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFE8E8E8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHealthScoreCard() {
    final healthScore = _analytics['healthScore'] ?? 85.0;
    final recoveryPercent = _analytics['recoveryPercent'] ?? 85.0;
    final sleepNeed = _analytics['sleepNeed'] ?? 0.0;

    Color scoreColor;
    String status;

    if (healthScore >= 85) {
      scoreColor = Colors.green;
      status = 'Excellent';
    } else if (healthScore >= 70) {
      scoreColor = Colors.blue;
      status = 'Good';
    } else if (healthScore >= 60) {
      scoreColor = Colors.orange;
      status = 'Fair';
    } else {
      scoreColor = Colors.red;
      status = 'Needs Attention';
    }

    return _buildGradientBorderCard(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18.5),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1A1A1A).withOpacity(0.8),
              const Color(0xFF0D0D0D).withOpacity(0.9),
            ],
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Overall Health Score',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFE8E8E8),
                  ),
                ),
                if (_isCalculatingHealth)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: scoreColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: scoreColor.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      status,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scoreColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // Circular Rings Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildCircularRing(
                  value: healthScore,
                  title: 'Health',
                  subtitle: 'Score',
                  color: scoreColor,
                  size: 120,
                ),
                _buildCircularRing(
                  value: recoveryPercent,
                  title: 'Recovery',
                  subtitle: 'Today',
                  color: Colors.teal,
                  size: 120,
                ),
              ],
            ),

            const SizedBox(height: 20),
            _buildHealthMetricsGrid(),

            // Sleep Need Information
            if (sleepNeed > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blue.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.nightlight_round_rounded,
                      color: Colors.blue,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Recommended additional sleep: +${sleepNeed.toStringAsFixed(1)} hours',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHealthMetricsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildMetricItem(
          'Resting HR',
          '${_analytics['latestRHR'] ?? _analytics['avgRHR'] ?? '--'} BPM',
          Icons.favorite_rounded,
          Colors.red,
          'Current',
          stability: 'Stable',
        ),
        _buildMetricItem(
          'HRV',
          '${_analytics['latestHRV'] ?? _analytics['avgHRV'] ?? '--'} ms',
          Icons.insights_rounded,
          Colors.purple,
          'Current',
          stability: '${(_stabilityIndices['hrv'] ?? 0).toStringAsFixed(0)}%',
        ),
        _buildMetricItem(
          'Sleep',
          '${(_analytics['latestSleep'] ?? _analytics['avgSleep'] ?? 0).toStringAsFixed(1)}h',
          Icons.nightlight_round_rounded,
          Colors.blue,
          'Optimal: 7-9h',
          stability: 'High',
        ),
        _buildMetricItem(
          'Recovery',
          '${_analytics['latestRecovery'] ?? _analytics['avgRecovery'] ?? '--'}%',
          Icons.health_and_safety_rounded,
          Colors.teal,
          'Current',
          stability: 'Good',
        ),
        _buildMetricItem(
          'Stress',
          '${_analytics['latestStress'] ?? _analytics['avgStress'] ?? '--'}',
          Icons.psychology_rounded,
          Colors.orange,
          'Lower is better',
        ),
        _buildMetricItem(
          'SpO₂',
          '${_analytics['latestSPO2'] ?? _analytics['avgSPO2'] ?? '--'}%',
          Icons.air_rounded,
          const Color.fromARGB(255, 50, 93, 173),
          'Oxygen Level',
        ),
        _buildMetricItem(
          'Temperature',
          '${(_analytics['latestTemperature'] ?? _analytics['avgTemperature'] ?? 0).toStringAsFixed(1)}°C',
          Icons.thermostat_rounded,
          Colors.amber,
          'Body Temp',
        ),
        _buildMetricItem(
          'Heart Rate',
          '${_analytics['latestHeartRate'] ?? _analytics['avgHeartRate'] ?? '--'} BPM',
          Icons.monitor_heart_rounded,
          Colors.red,
          'Current',
        ),
      ],
    );
  }

  Widget _buildMetricItem(
    String title,
    String value,
    IconData icon,
    Color color,
    String subtitle, {
    String? stability,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A1A1A).withOpacity(0.8),
            const Color(0xFF0D0D0D).withOpacity(0.9),
          ],
        ),
        border: Border.all(color: const Color(0xFF333333), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              if (stability != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.flash_on_rounded,
                        color: Colors.green,
                        size: 10,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        stability,
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF888888),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(color: color.withOpacity(0.7), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklySummaryCard() {
    final weeklySummary =
        _analytics['weeklySummary'] as Map<String, dynamic>? ?? {};
    final recommendations =
        _analytics['healthRecommendations'] as List<String>? ?? [];

    return _buildGradientBorderCard(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18.5),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1A1A1A).withOpacity(0.8),
              const Color(0xFF0D0D0D).withOpacity(0.9),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Weekly Summary',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFFE8E8E8),
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildSummaryItem(
                  'Total Steps',
                  '${weeklySummary['totalSteps'] ?? '0'}',
                  Icons.directions_walk_rounded,
                  Colors.green,
                ),
                _buildSummaryItem(
                  'Calories Burned',
                  '${weeklySummary['totalCalories'] ?? '0'}',
                  Icons.local_fire_department_rounded,
                  Colors.orange,
                ),
                _buildSummaryItem(
                  'Active Days',
                  '${weeklySummary['activeDays'] ?? '0'}/7',
                  Icons.fitness_center_rounded,
                  Colors.blue,
                ),
                _buildSummaryItem(
                  'Good Sleep Days',
                  '${weeklySummary['goodSleepDays'] ?? '0'}/7',
                  Icons.nightlight_round_rounded,
                  Colors.purple,
                ),
              ],
            ),
            if (recommendations.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Health Recommendations',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFE8E8E8),
                ),
              ),
              const SizedBox(height: 12),
              ...recommendations
                  .map(
                    (recommendation) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.green,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              recommendation,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: const Color(0xFFA0A0A0)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A1A1A).withOpacity(0.8),
            const Color(0xFF0D0D0D).withOpacity(0.9),
          ],
        ),
        border: Border.all(color: const Color(0xFF333333), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFA0A0A0),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIInsightsCard() {
    return _buildGradientBorderCard(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18.5),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1A1A1A).withOpacity(0.8),
              const Color(0xFF0D0D0D).withOpacity(0.9),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFF808080),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'AI Health Insights',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFFE8E8E8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (!_isGeneratingInsight)
                  IconButton(
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Color(0xFF808080),
                      size: 16,
                    ),
                    onPressed: _generateAIInsight,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _isGeneratingInsight
                ? Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF808080),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Generating personalized insights...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF808080),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  )
                : Text(
                    _aiInsight.isNotEmpty
                        ? _aiInsight
                        : 'Analyzing your health patterns...',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF808080),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeRangeSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [7, 14, 30, 365].map((days) {
          final isSelected = _selectedTimeRange == days;
          String label = days == 365 ? 'ALL' : '${days}D';
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedTimeRange = days;
              });
              _loadAnalyticsData();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.blue.withOpacity(0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: isSelected
                    ? Border.all(color: Colors.blue.withOpacity(0.3))
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.blue : const Color(0xFFA0A0A0),
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHealthBalanceCard() {
    final recovery = _analytics['recoveryPercent'] ?? 0.0;
    final hrvStable = _stabilityIndices['hrv'] ?? 0.0;
    final sleepAvg = (_analytics['avgSleep'] ?? 0.0) / 8.0 * 100;

    return _buildGradientBorderCard(
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.balance_rounded, color: Colors.teal, size: 24),
                const SizedBox(width: 12),
                Text(
                  'Health Balance Breakdown',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildBalanceBar(
              'Recovery Capacity',
              recovery.clamp(0.0, 100.0),
              Colors.teal,
            ),
            const SizedBox(height: 16),
            _buildBalanceBar(
              'Autonomic Stability',
              hrvStable.clamp(0.0, 100.0),
              Colors.purple,
            ),
            const SizedBox(height: 16),
            _buildBalanceBar(
              'Sleep Consistency',
              sleepAvg.clamp(0.0, 100.0),
              Colors.blue,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.auto_graph_rounded, color: Colors.blue, size: 16),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your Stability score measures how consistent your physiology remains day-to-day. Higher stability often leads to better long-term recovery.',
                      style: TextStyle(
                        color: Color(0xFF666666),
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceBar(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFA0A0A0),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${value.toStringAsFixed(0)}%',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: value / 100,
            backgroundColor: const Color(0xFF1A1A1A),
            color: color,
            minHeight: 7,
          ),
        ),
      ],
    );
  }

  Widget _buildPersonalMilestonesCard() {
    if (_milestones.isEmpty) return const SizedBox();

    return _buildGradientBorderCard(
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.stars_rounded, color: Colors.amber, size: 24),
                const SizedBox(width: 12),
                Text(
                  'Discovery & Milestones',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _buildMilestoneItem(
                  'Best Recovery',
                  '${_milestones['bestRecovery']}%',
                  Icons.bolt_rounded,
                  Colors.teal,
                ),
                const SizedBox(width: 16),
                _buildMilestoneItem(
                  'Lowest RHR',
                  '${_milestones['minRHR']} bpm',
                  Icons.favorite_rounded,
                  Colors.red,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildMilestoneItem(
                  'Highest HRV',
                  '${_milestones['maxHRV']} ms',
                  Icons.insights_rounded,
                  Colors.purple,
                ),
                const SizedBox(width: 16),
                _buildMilestoneItem(
                  'Sleep Record',
                  '${_milestones['maxSleep']}h',
                  Icons.nightlight_rounded,
                  Colors.blue,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMilestoneItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color.withOpacity(0.5), size: 14),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCorrelationSection() {
    final corr = _correlations['sleep_recovery'] ?? 0.0;
    String insight;
    if (corr > 0.7)
      insight = "Your recovery is highly dependent on sleep quality.";
    else if (corr > 0.4)
      insight = "Sleep has a moderate positive impact on your recovery.";
    else
      insight =
          "Multiple factors are currently influencing your daily recovery.";

    return _buildGradientBorderCard(
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.compare_arrows_rounded,
                  color: Colors.blue,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Impact Analysis',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Correlation: Sleep vs. Recovery Score',
              style: TextStyle(
                color: const Color(0xFFA0A0A0),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Stack(
              children: [
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: ((corr + 1) / 2).clamp(0.01, 1.0),
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: corr > 0
                            ? [Colors.blue, Colors.cyan]
                            : [Colors.red, Colors.orange],
                      ),
                      borderRadius: BorderRadius.circular(5),
                      boxShadow: [
                        BoxShadow(
                          color: (corr > 0 ? Colors.blue : Colors.red)
                              .withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Text(
                insight,
                style: const TextStyle(
                  color: Color(0xFFE8E8E8),
                  fontSize: 14,
                  height: 1.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAnalyticsData,
          backgroundColor: const Color(0xFF1A1A1A),
          color: Colors.blue,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Zyora Analytics',
                          style: TextStyle(
                            color: const Color(0xFFE8E8E8),
                            fontSize: (MediaQuery.of(context).size.width * 0.07)
                                .clamp(24.0, 28.0),
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Deep-dive into your physiological trends',
                          style: TextStyle(
                            color: const Color(0xFFA0A0A0),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    _buildTimeRangeSelector(),
                  ],
                ),
                const SizedBox(height: 28),

                if (_isLoading)
                  _buildSkeletonLoading()
                else if (_healthData.isEmpty)
                  _buildEmptyState()
                else ...[
                  // 1. Health Hero (Score & Recovery)
                  _buildHealthScoreCard(),
                  const SizedBox(height: 24),

                  // 2. AI Intelligence
                  _buildAIInsightsCard(),
                  const SizedBox(height: 24),

                  // 3. Health Balance Breakdown
                  _buildHealthBalanceCard(),
                  const SizedBox(height: 24),

                  // 4. Discovery & Milestones
                  _buildPersonalMilestonesCard(),
                  const SizedBox(height: 24),

                  // 5. Correlation Analysis
                  _buildCorrelationSection(),
                  const SizedBox(height: 24),

                  // 5. Metric Distribution Grid
                  Text(
                    'Metric Deep-Dive',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildHealthMetricsGrid(),
                  const SizedBox(height: 24),

                  // 6. Trend Overviews
                  Text(
                    'Visual Trends',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSleepAnalysisChart(),
                  const SizedBox(height: 20),
                  _buildHeartRateAnalysisChart(),
                  const SizedBox(height: 20),
                  _buildStressRecoveryChart(),
                  const SizedBox(height: 24),

                  // 7. Weekly Performance Summary
                  _buildWeeklySummaryCard(),
                  const SizedBox(height: 40),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonLoading() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 120),
          CircularProgressIndicator(
            color: Colors.blue.withOpacity(0.4),
            strokeWidth: 3,
          ),
          const SizedBox(height: 20),
          const Text(
            'Aggregating long-term trends...',
            style: TextStyle(color: Color(0xFF555555), letterSpacing: 1.2),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 120),
          Icon(
            Icons.query_stats_rounded,
            color: const Color(0xFF222222),
            size: 80,
          ),
          const SizedBox(height: 20),
          const Text(
            'Insufficient Data',
            style: TextStyle(
              color: Color(0xFFE8E8E8),
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Keep wearing your Zyora band to see deep health patterns.',
            style: TextStyle(color: Color(0xFF666666), fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
