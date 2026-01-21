import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'metric_detail_screen.dart';
import '../services/ble_service.dart';
import '../services/ai_description_service.dart';
import '../services/health_calculations_service.dart';
import '../services/daily_questions_service.dart';
import '../services/user_profile_service.dart';
import '../services/ai_cache_service.dart';
import '../services/background_ble_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

class DashboardScreen extends StatefulWidget {
  final BLEService bleService;
  final BackgroundBLEService backgroundBleService; // Added this line

  const DashboardScreen({
    super.key,
    required this.bleService,
    required this.backgroundBleService,
  }); // Modified this line

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  late AnimationController _fadeController;
  late AnimationController _slideController;

  // Enhanced color method with vibrant colors

  HealthData _currentData = HealthData(
    heartRate: 72,
    steps: 0,
    spo2: 98,
    calories: 0,
    sleep: 7.0,
    recovery: 85,
    stress: 30,
    rhr: 60,
    hrv: 60,
    bodyTemperature: 36.5,
    breathingRate: 16,
  );

  bool _isConnected = false;
  int? _cachedActivityIntensity; // NEW
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<HealthData>? _dataSubscription;

  // Services
  final AIDescriptionService _aiService = AIDescriptionService();
  final DailyQuestionsService _dailyQuestionsService = DailyQuestionsService();
  final UserProfileService _userProfileService = UserProfileService();
  final AICacheService _aiCacheService = AICacheService();

  // State variables
  Map<String, String> _metricDescriptions = {};
  final Map<String, bool> _descriptionLoading = {};
  int _phoneSteps = 0; // NEW: Phone steps state
  SleepNeedResult? _currentHealthResult;
  DailyQuestions? _latestQuestions;
  UserProfile? _userProfile;
  bool _isCalculatingHealth = false;
  bool _isLoadingCache = false;
  bool _animationsPlayedOnce = false;

  bool _aiInsightsInitialized = false;
  String _previousDataSignature = '';

  // Store weekly data for trend calculations for each metric
  Map<String, List<Map<String, dynamic>>> _weeklyDataForTrends = {};

  // In your dashboard_screen.dart, update the initState method:
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

    _isConnected =
        widget.bleService.isConnected ||
        widget.backgroundBleService.isConnected;

    _checkPermissions().then((_) {
      // Start Step Counter only after permissions are handled
      widget.backgroundBleService.startStepCounter();
      widget.backgroundBleService.getSteps().then((value) {
        if (mounted) {
          setState(() {
            _phoneSteps = value;
            _currentData = _currentData.copyWith(steps: value);
          });
        }
      });
    });

    _loadCachedInsightsFirst();
    _setupStreamListeners();
    _setupBackgroundListeners();
  }

  Future<void> _checkPermissions() async {
    try {
      if (await Permission.activityRecognition.isDenied) {
        await Permission.activityRecognition.request();
      }
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } catch (e) {
      print('❌ Error requesting permissions: $e');
    }
  }

  void _setupBackgroundListeners() {
    // Listen for background service data
    widget.backgroundBleService.onDataReceived = (healthData) {
      if (mounted) {
        setState(() {
          _currentData = _currentData.copyWith(
            heartRate: healthData.heartRate,
            steps: healthData.steps,
            spo2: healthData.spo2,
            calories: healthData.calories,
            stress: healthData.stress,
            bodyTemperature: healthData.bodyTemperature,
            breathingRate: healthData.breathingRate,
            activityIntensity: healthData.activityIntensity,
            // recovery, rhr, hrv are calculated locally once a day
          );
        });
        // Removed _calculateHealthScore() call to keep it once-a-day
        _updateDescriptionsOnDataChange();
        _loadWeeklyDataForTrends();
      }
    };

    // Listen for background service connection status
    widget.backgroundBleService.onConnectionStatusChanged = (connected) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
        });
      }
    };

    // Listen to phone step updates
    widget.backgroundBleService.stepStream.listen((steps) {
      if (mounted) {
        setState(() {
          _phoneSteps = steps;
          _currentData = _currentData.copyWith(steps: steps);
        });
      }
    });
  }

  Future<void> _loadCachedInsightsFirst() async {
    setState(() {
      _isLoadingCache = true;
    });

    try {
      final cachedInsights = await _aiCacheService.getCachedInsights();

      if (mounted) {
        setState(() {
          _metricDescriptions = Map<String, String>.from(cachedInsights);
          _isLoadingCache = false;
        });
      }

      await _loadInitialData();
      await _loadWeeklyDataForTrends();
      _previousDataSignature = _generateDataSignature();
    } catch (e) {
      print('Error loading cached insights: $e');
      await _loadInitialData();
      await _loadWeeklyDataForTrends();
      _previousDataSignature = _generateDataSignature();
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCache = false;
        });
        if (!_animationsPlayedOnce) {
          _fadeController.forward();
          _slideController.forward();
          _animationsPlayedOnce = true;
        }
      }
    }
  }

  void _setupStreamListeners() {
    _connectionSubscription = widget.bleService.connectionStream.listen((
      connected,
    ) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
        });
      }
    });

    _dataSubscription = widget.bleService.dataStream.listen((data) {
      if (mounted) {
        setState(() {
          _currentData = _currentData.copyWith(
            heartRate: data.heartRate,
            steps: data.steps,
            spo2: data.spo2,
            calories: data.calories,
            stress: data.stress,
            bodyTemperature: data.bodyTemperature,
            breathingRate: data.breathingRate,
            activityIntensity: data.activityIntensity,
            // Keep recovery, rhr, and hrv as they are calculated locally
          );
        });
        // Removed _calculateHealthScore() call to keep it once-a-day
        _updateDescriptionsOnDataChange();
        _loadWeeklyDataForTrends();
      }
    });
  }

  String _generateDataSignature() {
    return '${_currentData.heartRate}_${_currentData.steps}_${_currentData.spo2}_'
        '${_currentData.calories}_${_currentData.sleep}_${_currentData.recovery}_'
        '${_currentData.stress}_${_currentData.rhr}_${_currentData.hrv}_'
        '${_currentData.bodyTemperature}_${_currentData.breathingRate}';
  }

  bool _hasDataChangedSignificantly() {
    final newSignature = _generateDataSignature();
    final hasChanged = newSignature != _previousDataSignature;
    if (hasChanged) {
      _previousDataSignature = newSignature;
    }
    return hasChanged;
  }

  Future<void> _loadInitialData() async {
    try {
      _userProfile = await _userProfileService.getUserProfile();
      _latestQuestions = await _dailyQuestionsService.getLatestQuestions();
      double? sleepFromForm = _latestQuestions?.calculatedSleepDuration;

      final latestData = await widget.bleService.getLatestHealthData();

      // NEW: Load persisted daily metrics
      final prefs = await SharedPreferences.getInstance();
      final lastScoreDate = prefs.getString('last_score_date');
      final todayStr = DateTime.now().toIso8601String().split('T')[0];

      int? persistedRecovery;
      int? persistedRHR;
      int? persistedHRV;
      int? persistedHealthScore;

      if (lastScoreDate == todayStr) {
        persistedRecovery = (prefs.getInt('daily_recovery_score') ?? 0) > 0
            ? prefs.getInt('daily_recovery_score')
            : null;
        persistedRHR = (prefs.getInt('daily_calculated_rhr') ?? 0) > 0
            ? prefs.getInt('daily_calculated_rhr')
            : null;
        persistedHRV = (prefs.getInt('daily_calculated_hrv') ?? 0) > 0
            ? prefs.getInt('daily_calculated_hrv')
            : null;
        persistedHealthScore = (prefs.getInt('daily_health_score') ?? 0) > 0
            ? prefs.getInt('daily_health_score')
            : null;

        print(
          '📦 Loaded persisted daily metrics: Recovery=$persistedRecovery, Health=$persistedHealthScore, RHR=$persistedRHR, HRV=$persistedHRV',
        );

        if (persistedHealthScore != null && persistedRecovery != null) {
          _currentHealthResult = SleepNeedResult(
            sleepNeed: 0,
            recoveryPercent: persistedRecovery.toDouble(),
            baseSleepRequired: 8,
            healthScore: persistedHealthScore.toDouble(),
            hrvStatus: 'Good',
            rhrStatus: 'Good',
          );
        }
      }

      if (latestData != null && mounted) {
        setState(() {
          _currentData = HealthData(
            heartRate: latestData.heartRate,
            steps: latestData.steps,
            spo2: latestData.spo2,
            calories: latestData.calories,
            sleep: sleepFromForm ?? 7.0,
            recovery:
                persistedRecovery ??
                (latestData.recovery > 0 ? latestData.recovery : 85),
            stress: latestData.stress,
            rhr: persistedRHR ?? (latestData.rhr > 0 ? latestData.rhr : 60),
            hrv: persistedHRV ?? (latestData.hrv > 0 ? latestData.hrv : 45),
            bodyTemperature: latestData.bodyTemperature,
            breathingRate: latestData.breathingRate,
          );
        });
      } else if (mounted) {
        setState(() {
          _currentData = HealthData(
            heartRate: _currentData.heartRate,
            steps: _currentData.steps,
            spo2: _currentData.spo2,
            calories: _currentData.calories,
            sleep: sleepFromForm ?? 7.0,
            recovery: persistedRecovery ?? _currentData.recovery,
            stress: _currentData.stress,
            rhr: persistedRHR ?? _currentData.rhr,
            hrv: persistedHRV ?? _currentData.hrv,
            bodyTemperature: _currentData.bodyTemperature,
            breathingRate: _currentData.breathingRate,
          );
        });
      }

      // Only calculate if we haven't today OR if we just got a new form
      if (lastScoreDate != todayStr && _latestQuestions != null) {
        _calculateHealthScore();
      }

      if (!_aiInsightsInitialized) {
        _initializeDescriptions();
      }
    } catch (e) {
      print('Error loading initial data: $e');
      if (!_aiInsightsInitialized) {
        _initializeDescriptions();
      }
    }
  }

  Future<int?> _getTodayActivityIntensity() async {
    try {
      // Try to get from local storage first
      final todayActivity = await widget.bleService
          .getActivityIntensityForToday();
      if (todayActivity != null) {
        return todayActivity;
      }

      // Fallback to latest daily questions
      final questions = await _dailyQuestionsService.getLatestQuestions();
      return questions?.activityIntensity;
    } catch (e) {
      print('Error getting activity intensity: $e');
      return null;
    }
  }

  Future<void> _loadActivityIntensity() async {
    final val = await _getTodayActivityIntensity();
    if (mounted) {
      setState(() {
        _cachedActivityIntensity = val;
      });
    }
  }

  Future<double> _getDailyMetricValue(
    List<HealthData> dayDataPoints,
    DateTime date,
    String metricName,
  ) async {
    if (dayDataPoints.isEmpty) return 0.0;

    switch (metricName) {
      case 'Heart Rate':
        return dayDataPoints.last.heartRate.toDouble();
      case 'Activity Intensity':
        final questions = await _dailyQuestionsService.getQuestionsForDate(
          date,
        );
        return (questions?.activityIntensity ?? 50).toDouble();
      case 'Sleep':
        try {
          final questions = await _dailyQuestionsService.getQuestionsForDate(
            date,
          );
          if (questions != null && questions.calculatedSleepDuration != null) {
            return questions.calculatedSleepDuration!;
          }
          return dayDataPoints
              .map((e) => e.sleep)
              .reduce((a, b) => a > b ? a : b);
        } catch (e) {
          print('Error getting sleep data for trend: $e');
          return dayDataPoints
              .map((e) => e.sleep)
              .reduce((a, b) => a > b ? a : b);
        }
      case 'Calories':
        return dayDataPoints
            .map((e) => e.calories)
            .reduce((a, b) => a > b ? a : b)
            .toDouble();
      case 'SpO₂':
        return dayDataPoints.last.spo2.toDouble();
      case 'Recovery':
        try {
          final historicalData = await widget.bleService.getAllHealthData();
          final allQuestions = await _dailyQuestionsService.getAllQuestions();
          final baselineData = HealthCalculationsService.calculateBaselines(
            historicalData,
            allQuestions,
          );
          final questions = await _dailyQuestionsService.getQuestionsForDate(
            date,
          );
          double? sleepFromForm = questions?.calculatedSleepDuration;

          HealthData? bestDataPoint;
          double bestRecoveryPotential = -double.infinity;

          for (var dataPoint in dayDataPoints) {
            double recoveryPotential =
                dataPoint.hrv.toDouble() - (dataPoint.rhr / 2.0);
            if (recoveryPotential > bestRecoveryPotential) {
              bestRecoveryPotential = recoveryPotential;
              bestDataPoint = dataPoint;
            }
          }

          final dataToUse =
              bestDataPoint ??
              (dayDataPoints.isNotEmpty ? dayDataPoints.last : null);

          if (dataToUse != null) {
            // Recalculate RHR for the trend date as well to be consistent
            final dayHistoricalData = await widget.bleService
                .getAllHealthData();
            final dayAllQuestions = await _dailyQuestionsService
                .getAllQuestions();
            final dayDailyRHRs = HealthCalculationsService.calculateDailyRHRs(
              dayHistoricalData,
              dayAllQuestions,
            );
            final dayDailyHRVs = HealthCalculationsService.calculateDailyHRVs(
              dayHistoricalData,
              dayAllQuestions,
            );
            final dayDateStr = date.toIso8601String().split('T')[0];
            final dayRHR = dayDailyRHRs[dayDateStr] ?? 65;
            final dayHRV = dayDailyHRVs[dayDateStr] ?? 45;

            final result = HealthCalculationsService.calculateSleepNeed(
              age: _userProfile?.age ?? 25,
              rhrBaseline: baselineData.rhrBaseline,
              rhrToday:
                  dayRHR, // Use recalculated RHR for historical trend points
              hrvBaseline: baselineData.hrvBaseline,
              hrvToday:
                  dayHRV, // Use recalculated HRV for historical trend points
              steps: dataToUse.steps,
              calories: dataToUse.calories,
              sleepFromForm: sleepFromForm,
              spo2: dataToUse.spo2,
              stress: dataToUse.stress,
              bodyTemperature: dataToUse.bodyTemperature,
              breathingRate: dataToUse.breathingRate,
              dailyQuestions: questions,
            );
            return result.recoveryPercent;
          }
          return dayDataPoints
              .map((e) => e.recovery)
              .reduce((a, b) => a > b ? a : b)
              .toDouble();
        } catch (e) {
          print('Error calculating recovery for trend: $e');
          return dayDataPoints
              .map((e) => e.recovery)
              .reduce((a, b) => a > b ? a : b)
              .toDouble();
        }
      case 'Stress Level':
        return dayDataPoints.last.stress.toDouble();
      default:
        return 0.0;
    }
  }

  Future<void> _loadWeeklyDataForTrends() async {
    try {
      final now = DateTime.now();
      final allHealthData = await widget.bleService.getAllHealthData();
      final allQuestions = await _dailyQuestionsService.getAllQuestions();
      await HealthCalculationsService.calculateBaselines(
        allHealthData,
        allQuestions,
      );

      final Map<String, List<HealthData>> dailyGroups = {};
      for (var dataPoint in allHealthData) {
        final dayKey = _getDayKey(dataPoint.timestamp);
        final healthData = HealthData(
          heartRate: dataPoint.heartRate,
          steps: dataPoint.steps,
          spo2: dataPoint.spo2,
          calories: dataPoint.calories,
          sleep: dataPoint.sleep,
          recovery: dataPoint.recovery,
          stress: dataPoint.stress,
          rhr: dataPoint.rhr,
          hrv: dataPoint.hrv,
          bodyTemperature: dataPoint.bodyTemperature,
          breathingRate: dataPoint.breathingRate,
        );
        dailyGroups.putIfAbsent(dayKey, () => []).add(healthData);
      }

      final List<String> metricsToTrack = [
        'Heart Rate',
        'Activity Intensity', // NEW: Replace 'Steps'
        'Sleep',
        'Calories',
        'SpO₂',
        'Recovery',
        'Stress Level',
      ];

      Map<String, List<Map<String, dynamic>>> newWeeklyDataForTrends = {};

      for (String metricName in metricsToTrack) {
        final List<Map<String, dynamic>> weeklyData = [];
        for (int i = 6; i >= 0; i--) {
          final date = now.subtract(Duration(days: i));
          final dayKey = _getDayKey(date);
          final dayDataPoints = dailyGroups[dayKey] ?? [];

          double dailyValue = await _getDailyMetricValue(
            dayDataPoints,
            date,
            metricName,
          );

          weeklyData.add({
            'day': _getDayName(date.weekday),
            'date': date,
            'value': dailyValue,
            'fullDate': '${date.month}/${date.day}',
            'isToday': i == 0,
            'rawDataPoints': dayDataPoints,
          });
        }
        newWeeklyDataForTrends[metricName] = weeklyData;
      }

      if (mounted) {
        setState(() {
          _weeklyDataForTrends = newWeeklyDataForTrends;
        });
      }
    } catch (e) {
      print('Error loading weekly data for trends: $e');
    }
  }

  String _getDayKey(DateTime date) {
    return '${date.year}-${date.month}-${date.day}';
  }

  String _getDayName(int weekday) {
    switch (weekday) {
      case 1:
        return 'M';
      case 2:
        return 'T';
      case 3:
        return 'W';
      case 4:
        return 'T';
      case 5:
        return 'F';
      case 6:
        return 'S';
      case 7:
        return 'S';
      default:
        return '';
    }
  }

  String? _calculateRealTrend(String metricName, double currentValue) {
    final weeklyData = _weeklyDataForTrends[metricName];
    if (weeklyData == null || weeklyData.length < 2) return null;

    final percentageChange =
        HealthCalculationsService.calculateTrendFromWeeklyData(weeklyData);

    double sensitivityThreshold;
    switch (metricName) {
      case 'Heart Rate':
        sensitivityThreshold = 2.0;
        break;
      case 'Activity Intensity':
        sensitivityThreshold = 5.0;
        break;
      case 'Sleep':
        sensitivityThreshold = 5.0;
        break;
      case 'Recovery':
        sensitivityThreshold = 3.0;
        break;
      case 'Stress Level':
        sensitivityThreshold = 5.0;
        break;
      default:
        sensitivityThreshold = 2.0;
    }

    if (percentageChange.abs() < sensitivityThreshold) return null;

    final trendIcon = percentageChange > 0 ? '+' : '';
    final trendValue = percentageChange.abs().toStringAsFixed(0);
    return '$trendIcon${trendValue}%';
  }

  Future<void> _calculateHealthScore() async {
    if (_isCalculatingHealth) return;

    setState(() {
      _isCalculatingHealth = true;
    });

    try {
      _latestQuestions = await _dailyQuestionsService.getTodaysQuestions();

      // If no questions today, we can't do the "Calculated RHR" logic properly
      // We might want to use the latest available questions or prompt the user
      if (_latestQuestions == null) {
        print('⚠️ No daily questions for today. Calculation skipped.');
        return;
      }

      double? sleepFromForm = _latestQuestions?.calculatedSleepDuration;

      // --- NEW RHR & HRV CALCULATION LOGIC ---
      // Defaults if no data found
      int calculatedRHR = _currentData.rhr > 0 ? _currentData.rhr : 65;
      int calculatedHRV = _currentData.hrv > 0 ? _currentData.hrv : 45;

      if (_latestQuestions?.bedtime != null &&
          _latestQuestions?.wakeTime != null) {
        final window = HealthCalculationsService.getSleepWindow(
          DateTime.now(),
          _latestQuestions!.bedtime!,
          _latestQuestions!.wakeTime!,
        );

        if (window != null) {
          List<int> rawHRs = await widget.bleService.getHRDataForRange(
            window['start']!,
            window['end']!,
          );

          // FALLBACK: If sleep window is empty, try to get last 50 points from last 24h
          if (rawHRs.isEmpty) {
            print('📊 Sleep window empty, attempting 24h fallback...');
            final now = DateTime.now();
            final last24h = await widget.bleService.getHRDataForRange(
              now.subtract(const Duration(days: 1)),
              now,
            );
            if (last24h.length > 50) {
              rawHRs = last24h.sublist(last24h.length - 50);
            } else {
              rawHRs = last24h;
            }
          }

          if (rawHRs.isNotEmpty) {
            calculatedRHR = HealthCalculationsService.calculateRHRFromList(
              rawHRs,
            );
            if (rawHRs.length >= 2) {
              calculatedHRV = HealthCalculationsService.calculateHRVFromList(
                rawHRs,
              );
            }
            print(
              '🎯 LOCAL RHR CALCULATED: $calculatedRHR bpm, HRV: $calculatedHRV ms (from ${rawHRs.length} samples)',
            );
          } else {
            print('❌ No heart rate data available for calculation');
          }
        }
      }

      final historicalDataPoints = await widget.bleService.getAllHealthData();
      final allQuestions = await _dailyQuestionsService.getAllQuestions();

      // Calculate historical RHRs & HRVs using our smart logic (NO BAND DATA USED)
      final dailyRHRs = HealthCalculationsService.calculateDailyRHRs(
        historicalDataPoints,
        allQuestions,
      );
      HealthCalculationsService.calculateDailyHRVs(
        historicalDataPoints,
        allQuestions,
      );

      // Average the calculated RHRs for the baseline
      int totalRHRSum = 0;
      int rhrCount = 0;
      dailyRHRs.values.forEach((v) {
        if (v > 0) {
          totalRHRSum += v;
          rhrCount++;
        }
      });
      int rhrBaseline = rhrCount > 0 ? (totalRHRSum / rhrCount).round() : 65;

      final baselines = HealthCalculationsService.calculateBaselines(
        historicalDataPoints,
        allQuestions,
      );

      final result = HealthCalculationsService.calculateSleepNeed(
        age: _userProfile?.age ?? 25,
        rhrBaseline: rhrBaseline, // Use our smart baseline
        rhrToday: calculatedRHR, // Use today's smart calculation
        hrvBaseline: baselines.hrvBaseline,
        hrvToday: calculatedHRV, // Use today's smart calculation
        steps: _currentData.steps,
        calories: _currentData.calories,
        sleepFromForm: sleepFromForm,
        spo2: _currentData.spo2,
        stress: _currentData.stress,
        bodyTemperature: _currentData.bodyTemperature,
        breathingRate: _currentData.breathingRate,
        dailyQuestions: _latestQuestions,
        activityIntensity: _latestQuestions?.activityIntensity,
      );

      if (mounted) {
        setState(() {
          _currentHealthResult = result;
          _currentData = _currentData.copyWith(
            sleep: sleepFromForm ?? _currentData.sleep,
            recovery: result.recoveryPercent.round(),
            rhr: calculatedRHR,
            hrv: calculatedHRV,
          );
        });

        // Persist today's score if needed
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
          'daily_recovery_score',
          result.recoveryPercent.round(),
        );
        await prefs.setInt('daily_health_score', result.healthScore.round());
        await prefs.setInt('daily_calculated_rhr', calculatedRHR);
        await prefs.setInt('daily_calculated_hrv', calculatedHRV);
        await prefs.setString(
          'last_score_date',
          DateTime.now().toIso8601String().split('T')[0],
        );

        // Also save to database so history screen can see it
        await widget.bleService.saveCalculatedDailyBaselines(
          DateTime.now(),
          calculatedRHR,
          calculatedHRV,
          result.recoveryPercent.round(),
        );
      }

      print(
        '✅ CALCULATION SUCCESS: Recovery=${result.recoveryPercent.toStringAsFixed(1)}%, Health=${result.healthScore.toStringAsFixed(1)}/100, RHR=$calculatedRHR, HRV=$calculatedHRV',
      );
    } catch (e) {
      print('❌ Error calculating health score: $e');
      print('Stack trace: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isCalculatingHealth = false;
        });
      }
    }
  }

  void _initializeDescriptions() {
    final metrics = [
      'Heart Rate',
      'Steps',
      'Sleep',
      'Calories',
      'SpO₂',
      'Recovery',
      'Stress Level',
    ];

    for (var metric in metrics) {
      _descriptionLoading[metric] = false;
      if (!_metricDescriptions.containsKey(metric)) {
        _metricDescriptions[metric] = '';
      }
    }

    final hasExistingDescriptions = _metricDescriptions.values.any(
      (desc) => desc.isNotEmpty,
    );

    if (!hasExistingDescriptions || _hasDataChangedSignificantly()) {
      _updateDescriptions();
    }

    _aiInsightsInitialized = true;
  }

  void _updateDescriptionsOnDataChange() {
    if (_hasDataChangedSignificantly()) {
      print('Data changed significantly, updating AI insights...');
      _updateDescriptions();
    } else {
      print('Data unchanged, keeping existing AI insights');
    }
  }

  // In dashboard_screen.dart, add to quick actions or settings

  void _showThemeSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select Theme',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFFE8E8E8),
                ),
              ),
              const SizedBox(height: 20),
              _buildThemeOption(
                'Dark Theme',
                Icons.dark_mode_rounded,
                ThemeMode.dark,
              ),
              const SizedBox(height: 12),
              _buildThemeOption(
                'Light Theme',
                Icons.light_mode_rounded,
                ThemeMode.light,
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildThemeOption(String title, IconData icon, ThemeMode mode) {
    return _buildGradientBorderCard(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // Implement theme change logic
            Navigator.pop(context);
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFFE8E8E8)),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFFE8E8E8),
                  ),
                ),
                const Spacer(),
                if (Theme.of(context).brightness ==
                    (mode == ThemeMode.dark
                        ? Brightness.dark
                        : Brightness.light))
                  const Icon(Icons.check_rounded, color: Colors.green),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _updateDescriptions() {
    _updateDescriptionForMetric(
      'Heart Rate',
      _currentData.heartRate.toString(),
      'BPM',
    );
    _updateDescriptionForMetric(
      'Steps',
      _currentData.steps.toString(),
      'Today',
    );
    _updateDescriptionForMetric(
      'Sleep',
      _currentData.sleep.toStringAsFixed(1),
      'Hours',
    );
    _updateDescriptionForMetric(
      'Calories',
      _currentData.calories.toString(),
      'kcal',
    );
    _updateDescriptionForMetric('SpO₂', _currentData.spo2.toString(), '%');
    _updateDescriptionForMetric(
      'Recovery',
      (_currentHealthResult?.recoveryPercent.round() ?? _currentData.recovery)
          .toString(),
      'Score',
    );
    _updateDescriptionForMetric(
      'Health Score',
      (_currentHealthResult?.healthScore.round() ?? 85).toString(),
      '/100',
    );
    _updateDescriptionForMetric(
      'Stress Level',
      _currentData.stress.toString(),
      _currentData.getStressLevelText(),
    );
  }

  void _updateDescriptionForMetric(
    String metricName,
    String value,
    String unit,
  ) {
    if (_aiService.hasCachedDescription(_currentData, metricName)) {
      final cachedDescription = _aiService.getCachedDescription(
        _currentData,
        metricName,
      );
      if (cachedDescription != null && mounted) {
        setState(() {
          _metricDescriptions[metricName] = cachedDescription;
        });
        return;
      }
    }

    if (_descriptionLoading[metricName] == true) return;

    setState(() {
      _descriptionLoading[metricName] = true;
    });

    _aiService
        .getMetricDescription(
          metricName: metricName,
          currentValue: value,
          unit: unit,
          currentData: _currentData,
        )
        .then((description) async {
          if (mounted) {
            setState(() {
              _metricDescriptions[metricName] = description;
              _descriptionLoading[metricName] = false;
            });
            await _aiCacheService.saveInsights(_metricDescriptions);
          }
        })
        .catchError((error) {
          print('Error getting description for $metricName: $error');
          if (mounted) {
            setState(() {
              _descriptionLoading[metricName] = false;
            });
          }
        });
  }

  void _refreshDescription(String metricName) {
    String value = '';
    String unit = '';

    switch (metricName) {
      case 'Heart Rate':
        value = _currentData.heartRate.toString();
        unit = 'BPM';
        break;
      case 'Steps':
        value = _currentData.steps.toString();
        unit = 'Today';
        break;
      case 'Sleep':
        value = _currentData.sleep.toStringAsFixed(1);
        unit = 'Hours';
        break;
      case 'Calories':
        value = _currentData.calories.toString();
        unit = 'kcal';
        break;
      case 'SpO₂':
        value = _currentData.spo2.toString();
        unit = '%';
        break;
      case 'Recovery':
        value = _currentData.recovery.toString();
        unit = 'Score';
        break;
      case 'Stress Level':
        value = _currentData.stress.toString();
        unit = _currentData.getStressLevelText();
        break;
    }

    setState(() {
      _descriptionLoading[metricName] = true;
    });

    _aiService
        .updateMetricDescriptionManual(metricName, value, unit, _currentData)
        .then((description) async {
          if (mounted) {
            setState(() {
              _metricDescriptions[metricName] = description;
              _descriptionLoading[metricName] = false;
            });
            await _aiCacheService.saveInsights(_metricDescriptions);
          }
        })
        .catchError((error) {
          print('Error refreshing description for $metricName: $error');
          if (mounted) {
            setState(() {
              _descriptionLoading[metricName] = false;
            });
          }
        });
  }

  void _refreshHealthData() {
    _calculateHealthScore();
    _updateDescriptions();
    _updateDescriptions();
    _loadWeeklyDataForTrends();
    _loadActivityIntensity(); // NEW
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _connectionSubscription?.cancel();
    _dataSubscription?.cancel();
    super.dispose();
  }

  // DARK GRADIENT BORDER - MORE BLACK, LESS WHITE
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

  // NEW: Build circular progress ring
  Widget _buildCircularRing({
    required double value,
    required String title,
    required String subtitle,
    required Color color,
    double size = 120,
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
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: size * 0.08,
                  color: const Color(0xFFA0A0A0),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    String unit,
    IconData icon,
    Color color,
    String? trend,
    int index,
  ) {
    if (title == 'Steps') return const SizedBox.shrink();

    final isPositive = trend?.contains('+') ?? false;
    final isLoading = _descriptionLoading[title] ?? false;
    final description = _metricDescriptions[title] ?? '';

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: _slideController,
              curve: Interval(0.1 * index, 1.0, curve: Curves.easeOut),
            ),
          ),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _fadeController,
          curve: Interval(0.1 * index, 1.0, curve: Curves.easeIn),
        ),
        child: Column(
          children: [
            _buildGradientBorderCard(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18.5),
                  onTap: () => _navigateToDetailScreen(
                    metricName: title,
                    currentValue: value,
                    unit: unit,
                    icon: icon,
                    color: color,
                  ),
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
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    const Color(0xFF404040).withOpacity(0.4),
                                    const Color(0xFF202020).withOpacity(0.2),
                                  ],
                                ),
                                border: Border.all(
                                  color: const Color(
                                    0xFF606060,
                                  ).withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Icon(icon, color: color, size: 20),
                            ),
                            if (trend != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isPositive
                                      ? Colors.green.withOpacity(0.1)
                                      : Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isPositive
                                        ? Colors.green.withOpacity(0.3)
                                        : Colors.red.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isPositive
                                          ? Icons.trending_up_rounded
                                          : Icons.trending_down_rounded,
                                      color: isPositive
                                          ? Colors.green
                                          : Colors.red,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      trend,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: isPositive
                                                ? Colors.green
                                                : Colors.red,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          value,
                          style: Theme.of(context).textTheme.displayMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          title,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFE8E8E8),
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          unit,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFFA0A0A0)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // AI Description Section
            if (description.isNotEmpty || isLoading)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A).withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF333333),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            color: const Color(0xFF808080),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'AI Insights',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: const Color(0xFF808080),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const Spacer(),
                          if (!isLoading)
                            IconButton(
                              icon: Icon(
                                Icons.refresh_rounded,
                                color: const Color(0xFF808080),
                                size: 16,
                              ),
                              onPressed: () => _refreshDescription(title),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      isLoading
                          ? Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      const Color(0xFF808080),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Generating personalized insights...',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: const Color(0xFF808080),
                                        fontStyle: FontStyle.italic,
                                      ),
                                ),
                              ],
                            )
                          : Text(
                              description,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: const Color(0xFF808080),
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                            ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _navigateToDetailScreen({
    required String metricName,
    required String currentValue,
    required String unit,
    required IconData icon,
    required Color color,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MetricDetailScreen(
          metricName: metricName,
          currentValue: currentValue,
          unit: unit,
          icon: icon,
          color: color,
          bleService: widget.bleService,
        ),
      ),
    );
  }

  Widget _buildActivityChart() {
    final weeklyActivityData = _weeklyDataForTrends['Activity Intensity'] ?? [];
    final currentIntensity =
        _cachedActivityIntensity ?? _latestQuestions?.activityIntensity ?? 50;
    final realTrend = _calculateRealTrend(
      'Activity Intensity',
      currentIntensity.toDouble(),
    );

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
                  'Exercise Intensity This Week', // Renamed
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFE8E8E8),
                  ),
                ),
                if (realTrend != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: realTrend.contains('+')
                          ? Colors.green.withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: realTrend.contains('+')
                            ? Colors.green.withOpacity(0.3)
                            : Colors.red.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      realTrend,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: realTrend.contains('+')
                            ? Colors.green
                            : Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            _buildActivitySummary(),
            const SizedBox(height: 16),

            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 100, // Max 100%
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      tooltipBgColor: Colors.black.withOpacity(0.9),
                      tooltipRoundedRadius: 8,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final dayData =
                            weeklyActivityData.isNotEmpty &&
                                groupIndex < weeklyActivityData.length
                            ? weeklyActivityData[groupIndex]
                            : null;

                        final dayName = dayData != null
                            ? dayData['day'] as String
                            : ['M', 'T', 'W', 'T', 'F', 'S', 'Sun'][groupIndex];

                        final intensity = dayData != null
                            ? (dayData['value'] as num).toInt()
                            : (groupIndex == 6 ? currentIntensity : 0);

                        final activityLevel = _getActivityLevel(intensity);

                        return BarTooltipItem(
                          '$dayName\n'
                          'Intensity: $intensity%\n'
                          'Level: $activityLevel',
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final days = weeklyActivityData.isNotEmpty
                              ? weeklyActivityData
                                    .map((d) => d['day'] as String)
                                    .toList()
                              : ['M', 'T', 'W', 'T', 'F', 'S', 'Sun'];

                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              value.toInt() < days.length
                                  ? days[value.toInt()]
                                  : '',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: const Color.fromARGB(
                                      255,
                                      224,
                                      224,
                                      224,
                                    ),
                                  ),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value % 25 == 0) {
                            return Text(
                              '${value.toInt()}%',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: const Color(0xFFA0A0A0)),
                            );
                          }
                          return const SizedBox();
                        },
                        reservedSize: 40,
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 25,
                    getDrawingHorizontalLine: (value) =>
                        FlLine(color: const Color(0xFF1A1A1A), strokeWidth: 1),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(
                      color: const Color(0xFF333333),
                      width: 1,
                    ),
                  ),
                  barGroups: _buildRealBarGroups(weeklyActivityData),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<BarChartGroupData> _buildRealBarGroups(
    List<Map<String, dynamic>> weeklyActivityData,
  ) {
    final currentIntensity =
        _cachedActivityIntensity ?? _latestQuestions?.activityIntensity ?? 50;

    return List.generate(7, (index) {
      double intensity = 0;

      if (weeklyActivityData.isNotEmpty && index < weeklyActivityData.length) {
        intensity = (weeklyActivityData[index]['value'] as num).toDouble();
      } else if (index == 6) {
        // Last position is today
        intensity = currentIntensity.toDouble();
      }

      // Calculate bar height
      double barHeight = intensity;
      if (barHeight < 5 && intensity > 0) barHeight = 5;

      // Get color based on intensity
      final Color barColor = _getActivityColor(intensity);

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: barHeight,
            gradient: LinearGradient(
              colors: [barColor, barColor.withOpacity(0.7)],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
            width: 20,
            borderRadius: BorderRadius.circular(6),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: 100,
              color: const Color(0xFF1A1A1A),
            ),
          ),
        ],
      );
    });
  }

  Color _getActivityColor(double intensity) {
    if (intensity <= 25) return Colors.green;
    if (intensity <= 50) return Colors.orange;
    if (intensity <= 75) return Colors.deepOrange;
    return Colors.red;
  }

  Widget _buildActivitySummary() {
    final intensity =
        _cachedActivityIntensity ?? _latestQuestions?.activityIntensity ?? 50;
    final activityLevel = _getActivityLevel(intensity);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A).withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem(
            'Today',
            '$intensity%',
            'Intensity',
            Icons.fitness_center,
            _getActivityColor(intensity.toDouble()),
          ),
          _buildSummaryItem(
            'Level',
            activityLevel,
            'Activity',
            Icons.trending_up,
            _getActivityColor(intensity.toDouble()),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color iconColor,
  ) {
    return Column(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: const Color(0xFFE8E8E8),
          ),
        ),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: const Color(0xFFA0A0A0)),
        ),
      ],
    );
  }

  String _getActivityLevel(int intensity) {
    if (intensity <= 25) return 'Light';
    if (intensity <= 50) return 'Moderate';
    if (intensity <= 75) return 'High';
    return 'Very High';
  }

  Widget _buildHealthScore() {
    final healthScore = _currentHealthResult?.healthScore ?? 85.0;
    final recoveryPercent = _currentHealthResult?.recoveryPercent ?? 85.0;

    Color scoreColor;
    if (healthScore >= 80) {
      scoreColor = Colors.green;
    } else if (healthScore >= 60) {
      scoreColor = Colors.orange;
    } else {
      scoreColor = Colors.red;
    }

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
                  'Health Overview',
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
                      '${healthScore.toStringAsFixed(0)}/100',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scoreColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 120,
                            height: 120,
                            child: CircularProgressIndicator(
                              value: healthScore / 100,
                              strokeWidth: 8,
                              backgroundColor: const Color(0xFF1A1A1A),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                scoreColor,
                              ),
                            ),
                          ),
                          Column(
                            children: [
                              Text(
                                healthScore.toStringAsFixed(0),
                                style: Theme.of(context).textTheme.displayLarge
                                    ?.copyWith(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFFE8E8E8),
                                    ),
                              ),
                              Text(
                                '/100',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: const Color(0xFFA0A0A0)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Health Score',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFE8E8E8),
                        ),
                      ),
                      if (_currentHealthResult?.sleepNeed != null &&
                          _currentHealthResult!.sleepNeed > 0)
                        Text(
                          '+${_currentHealthResult!.sleepNeed.toStringAsFixed(1)}h sleep needed',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: const Color(0xFFA0A0A0),
                                fontSize: 10,
                              ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    children: [
                      _buildMiniMetric(
                        'Sleep',
                        '${_currentData.sleep.toStringAsFixed(1)}h',
                        Icons.nightlight_round_rounded,
                        Colors.purple,
                      ),
                      const SizedBox(height: 16),
                      _buildMiniMetric(
                        'Activity',
                        '${_getActivityLevel(_currentData.steps)}',
                        Icons.directions_walk_rounded,
                        Colors.green,
                      ),
                      const SizedBox(height: 16),
                      _buildMiniMetric(
                        'Recovery',
                        '${recoveryPercent.toStringAsFixed(0)}%',
                        Icons.health_and_safety_rounded,
                        Colors.teal,
                      ),
                      const SizedBox(height: 16),
                      _buildMiniMetric(
                        'SpO₂',
                        '${_currentData.spo2}%',
                        Icons.air_rounded,
                        const Color.fromARGB(255, 50, 93, 173),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getStressColor(int stressValue) {
    if (stressValue <= 33) return Colors.green;
    if (stressValue <= 66) return Colors.orange;
    return Colors.red;
  }

  IconData _getStressIcon(int stressValue) {
    if (stressValue <= 33) return Icons.sentiment_satisfied_alt_rounded;
    if (stressValue <= 66) return Icons.sentiment_neutral_rounded;
    return Icons.sentiment_very_dissatisfied_rounded;
  }

  Widget _buildMiniMetric(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          String currentValue = value.replaceAll(RegExp(r'[^0-9.]'), '');
          String unit = value.replaceAll(RegExp(r'[0-9.]'), '');
          _navigateToDetailScreen(
            metricName: title,
            currentValue: currentValue,
            unit: unit,
            icon: icon,
            color: color,
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF404040).withOpacity(0.4),
                      const Color(0xFF202020).withOpacity(0.2),
                    ],
                  ),
                  border: Border.all(
                    color: const Color(0xFF606060).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFE8E8E8),
                  ),
                ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAction(
    String title,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return _buildGradientBorderCard(
      borderRadius: 16,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
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
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF404040).withOpacity(0.4),
                        const Color(0xFF202020).withOpacity(0.2),
                      ],
                    ),
                    border: Border.all(
                      color: const Color(0xFF606060).withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFE8E8E8),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStressLevelCard() {
    final stressLevel = _currentData.stress;
    final stressText = _currentData.getStressLevelText();

    Color stressColor = _getStressColor(stressLevel);
    IconData stressIcon = _getStressIcon(stressLevel);

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: _slideController,
              curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
            ),
          ),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _fadeController,
          curve: const Interval(0.6, 1.0, curve: Curves.easeIn),
        ),
        child: Column(
          children: [
            _buildGradientBorderCard(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18.5),
                  onTap: () => _navigateToDetailScreen(
                    metricName: 'Stress Level',
                    currentValue: stressLevel.toString(),
                    unit: stressText,
                    icon: stressIcon,
                    color: stressColor,
                  ),
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
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    const Color(0xFF404040).withOpacity(0.4),
                                    const Color(0xFF202020).withOpacity(0.2),
                                  ],
                                ),
                                border: Border.all(
                                  color: const Color(
                                    0xFF606060,
                                  ).withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Icon(
                                stressIcon,
                                color: stressColor,
                                size: 20,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: stressColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: stressColor.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                stressText,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: stressColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Stack(
                            children: [
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  return Container(
                                    width:
                                        constraints.maxWidth *
                                        (stressLevel / 100),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          stressColor,
                                          stressColor.withOpacity(0.8),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          stressLevel.toString(),
                          style: Theme.of(context).textTheme.displayMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: stressColor,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Stress Level',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFE8E8E8),
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Current Status',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFFA0A0A0)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_metricDescriptions['Stress Level']?.isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A).withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF333333),
                      width: 1,
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
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'AI Insights',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: const Color(0xFF808080),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const Spacer(),
                          if (!(_descriptionLoading['Stress Level'] ?? false))
                            IconButton(
                              icon: const Icon(
                                Icons.refresh_rounded,
                                color: Color(0xFF808080),
                                size: 16,
                              ),
                              onPressed: () =>
                                  _refreshDescription('Stress Level'),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      (_descriptionLoading['Stress Level'] ?? false)
                          ? Row(
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF808080),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Generating personalized insights...',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: const Color(0xFF808080),
                                        fontStyle: FontStyle.italic,
                                      ),
                                ),
                              ],
                            )
                          : Text(
                              _metricDescriptions['Stress Level'] ?? '',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: const Color(0xFF808080),
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                            ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const SizedBox(height: 16),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildTestMetricButton() {
    return _buildGradientBorderCard(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18.5),
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF1A1A1A),
                title: const Text(
                  'Diagnostic View',
                  style: TextStyle(color: Colors.white),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RHR: ${_currentData.rhr} bpm',
                      style: const TextStyle(color: Colors.green, fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'HRV: ${_currentData.hrv} ms',
                      style: const TextStyle(color: Colors.blue, fontSize: 18),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'These values are calculated locally based on your heart rate during its sleeping window.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
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
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.bug_report,
                    color: Colors.blue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Debug: Current RHR & HRV',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoadingCache) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Loading AI Insights...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    final healthScore = _currentHealthResult?.healthScore ?? 85.0;
    final recoveryPercent = _currentHealthResult?.recoveryPercent ?? 85.0;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Good Morning!',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFA0A0A0),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Health Overview',
                        style: Theme.of(context).textTheme.displayMedium
                            ?.copyWith(color: const Color(0xFFE8E8E8)),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      if (_isCalculatingHealth)
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              const Color.fromARGB(255, 50, 93, 173),
                            ),
                          ),
                        )
                      else
                        IconButton(
                          icon: const Icon(
                            Icons.refresh_rounded,
                            color: Color(0xFFE8E8E8),
                          ),
                          onPressed: _refreshHealthData,
                          tooltip: 'Refresh Health Data',
                        ),
                      const SizedBox(width: 8),
                      Icon(
                        _isConnected
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth_disabled,
                        color: _isConnected ? Colors.green : Colors.grey,
                        size: 24,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Circular Rings for Recovery and Health Score
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: const Color(0xFF0D0D0D).withOpacity(0.8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildCircularRing(
                      value: recoveryPercent,
                      title: 'Recovery',
                      subtitle: 'Today',
                      color: Colors.teal,
                      size: 130,
                    ),
                    _buildCircularRing(
                      value: healthScore,
                      title: 'Health',
                      subtitle: 'Score',
                      color: healthScore >= 80
                          ? Colors.green
                          : healthScore >= 60
                          ? Colors.orange
                          : Colors.red,
                      size: 130,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // NEW: Phone Step Counter Card
              _buildPhoneStepsCard(),
              const SizedBox(height: 24),

              // Metrics Grid with calculated data
              Column(
                children: [
                  _buildMetricCard(
                    'Heart Rate',
                    _currentData.heartRate.toString(),
                    'BPM',
                    Icons.favorite_rounded,
                    Colors.red,
                    _calculateRealTrend(
                      'Heart Rate',
                      _currentData.heartRate.toDouble(),
                    ),
                    0,
                  ),

                  const SizedBox(height: 16),
                  _buildMetricCard(
                    'Sleep',
                    _currentData.sleep.toStringAsFixed(1),
                    'Hours',
                    Icons.nightlight_round_rounded,
                    Colors.purple,
                    _calculateRealTrend('Sleep', _currentData.sleep),
                    2,
                  ),
                  const SizedBox(height: 16),
                  _buildMetricCard(
                    'Calories',
                    _currentData.calories.toString(),
                    'kcal',
                    Icons.local_fire_department_rounded,
                    Colors.orange,
                    _calculateRealTrend(
                      'Calories',
                      _currentData.calories.toDouble(),
                    ),
                    3,
                  ),
                  const SizedBox(height: 16),
                  _buildMetricCard(
                    'SpO₂',
                    _currentData.spo2.toString(),
                    '%',
                    Icons.air_rounded,
                    const Color.fromARGB(255, 50, 93, 173),
                    _calculateRealTrend('SpO₂', _currentData.spo2.toDouble()),
                    4,
                  ),
                  const SizedBox(height: 16),
                  _buildMetricCard(
                    'Recovery',
                    (_currentHealthResult?.recoveryPercent.round() ??
                            _currentData.recovery)
                        .toString(),
                    'Score',
                    Icons.health_and_safety_rounded,
                    Colors.teal,
                    _calculateRealTrend(
                      'Recovery',
                      (_currentHealthResult?.recoveryPercent ??
                          _currentData.recovery.toDouble()),
                    ),
                    5,
                  ),
                  const SizedBox(height: 16),
                  _buildStressLevelCard(),
                ],
              ),
              const SizedBox(height: 32),

              _buildActivityChart(),
              const SizedBox(height: 24),

              _buildHealthScore(),
              const SizedBox(height: 24),

              Text(
                'Quick Actions',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFE8E8E8),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildQuickAction(
                      'Start Workout',
                      Icons.fitness_center_rounded,
                      Colors.teal,
                      onTap: () {},
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildQuickAction(
                      'Meditate',
                      Icons.self_improvement_rounded,
                      const Color.fromARGB(255, 164, 202, 98),
                      onTap: () {},
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildQuickAction(
                      'Check SpO₂',
                      Icons.air_rounded,
                      const Color.fromARGB(255, 50, 93, 173),
                      onTap: () {
                        _navigateToDetailScreen(
                          metricName: 'SpO₂',
                          currentValue: _currentData.spo2.toString(),
                          unit: '%',
                          icon: Icons.air_rounded,
                          color: const Color.fromARGB(255, 50, 93, 173),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildTestMetricButton(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneStepsCard() {
    final distance = (_phoneSteps * 0.000762).toStringAsFixed(2);
    final calories = (_phoneSteps * 0.04).toStringAsFixed(1);
    const stepColor = Colors.cyan; // More theme-friendly cyan

    return _buildGradientBorderCard(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _navigateToDetailScreen(
            metricName: 'Steps',
            currentValue: '$_phoneSteps',
            unit: 'steps',
            icon: Icons.directions_walk_rounded,
            color: stepColor,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Daily Activity',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: const Color(0xFFA0A0A0),
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Phone Steps',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: const Color(0xFFE8E8E8),
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: stepColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.directions_walk_rounded,
                        color: stepColor,
                        size: 24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 160,
                      height: 160,
                      child: CircularProgressIndicator(
                        value: (_phoneSteps / 10000).clamp(0.0, 1.0),
                        strokeWidth: 12,
                        backgroundColor: const Color(0xFF1A1A1A),
                        valueColor: AlwaysStoppedAnimation<Color>(stepColor),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$_phoneSteps',
                          style: Theme.of(context).textTheme.displayMedium
                              ?.copyWith(
                                color: const Color(0xFFE8E8E8),
                                fontWeight: FontWeight.w800,
                                fontSize: 36,
                              ),
                        ),
                        Text(
                          'OF 10,000',
                          style: TextStyle(
                            color: const Color(0xFFA0A0A0),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildPhoneStatItem(
                      'Distance',
                      '$distance',
                      'km',
                      Icons.map_outlined,
                    ),
                    _buildPhoneStatItem(
                      'Calories',
                      '$calories',
                      'kcal',
                      Icons.local_fire_department_outlined,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneStatItem(
    String label,
    String value,
    String unit,
    IconData icon,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.cyan, size: 16),
            const SizedBox(width: 8),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              unit,
              style: const TextStyle(
                color: Color(0xFF808080),
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF808080), fontSize: 12),
        ),
      ],
    );
  }
}
