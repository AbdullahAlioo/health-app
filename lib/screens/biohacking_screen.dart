import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import 'dart:async';
import '../services/ble_service.dart';
import '../services/daily_questions_service.dart';
import '../services/user_profile_service.dart';
import '../services/ai_description_service.dart';
import '../services/ai_cache_service.dart';
import '../services/health_calculations_service.dart';

class BiohackingScreen extends StatefulWidget {
  final BLEService bleService;
  const BiohackingScreen({super.key, required this.bleService});

  @override
  State<BiohackingScreen> createState() => _BiohackingScreenState();
}

class _BiohackingScreenState extends State<BiohackingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isLoading = true;
  HealthData? _currentData;
  DailyQuestions? _latestQuestions;
  UserProfile? _userProfile;

  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<HealthData>? _dataSubscription;
  bool _isConnected = false;

  // AI Insight related services and state
  final AIDescriptionService _aiService = AIDescriptionService();
  final AICacheService _aiCacheService = AICacheService();
  final DailyQuestionsService _dailyQuestionsService =
      DailyQuestionsService(); // Added
  final UserProfileService _userProfileService = UserProfileService(); // Added
  Map<String, String> _metricDescriptions = {};
  final Map<String, bool> _descriptionLoading = {};
  bool _aiInsightsInitialized = false;
  String _previousDataSignature = '';

  // Health Scores
  double _vo2MaxScore = 0.0;
  double _stressResilienceScore = 0.0;
  double _sleepQualityScore = 0.0;
  double _immunityDefenseScore = 0.0;
  double _metabolicHealthScore = 0.0;
  double _brainPerformanceScore = 0.0;
  double _biologicalAgeScore = 0.0;
  double _trainingReadinessScore = 0.0;
  double _hormonalBalanceScore = 0.0;
  double _inflammationLevelScore = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _setupStreamListeners();
    _loadCachedInsightsFirst();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _connectionSubscription?.cancel();
    _dataSubscription?.cancel();
    super.dispose();
  }

  void _setupStreamListeners() {
    _connectionSubscription = widget.bleService.connectionStream.listen((
      connected,
    ) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
        });

        // If disconnected, reload data from database
        if (!connected) {
          _loadInitialData(); // Changed
        }
      }
    });

    _dataSubscription = widget.bleService.dataStream.listen((data) async {
      if (!mounted) return;

      // When BLE data comes in, update current data and recalculate scores
      await _updateDataAndRecalculate(data);
    });
  }

  // FIXED: Use the same robust data loading approach as DashboardScreen
  Future<void> _loadInitialData() async {
    // New method, replaces _loadHealthDataFromDatabase
    try {
      _userProfile = await _userProfileService.getUserProfile();
      _latestQuestions = await _dailyQuestionsService.getLatestQuestions();
      double? sleepFromForm = _latestQuestions?.calculatedSleepDuration;

      final latestData = await widget.bleService.getLatestHealthData();
      if (latestData != null && mounted) {
        await _updateDataAndRecalculate(
          HealthData(
            heartRate: latestData.heartRate,
            steps: latestData.steps,
            spo2: latestData.spo2,
            calories: latestData.calories,
            sleep: sleepFromForm ?? 7.0,
            recovery: latestData.recovery,
            stress: latestData.stress,
            rhr: latestData.rhr,
            hrv: latestData.hrv,
            bodyTemperature: latestData.bodyTemperature,
            breathingRate: latestData.breathingRate,
          ),
        );
      } else if (mounted) {
        // Use default data if no data available
        await _updateDataAndRecalculate(
          HealthData(
            heartRate: 72,
            steps: 0,
            spo2: 98,
            calories: 0,
            sleep: sleepFromForm ?? 7.0,
            recovery: 85,
            stress: 30,
            rhr: 60,
            hrv: 60,
            bodyTemperature: 36.5,
            breathingRate: 16,
          ),
        );
      }

      if (!_aiInsightsInitialized) {
        _initializeDescriptions();
      }
    } catch (e) {
      debugPrint('Error loading initial data in BiohackingScreen: $e');
      // Use default data if there's an error
      await _updateDataAndRecalculate(
        HealthData(
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
        ),
      );
      if (!_aiInsightsInitialized) {
        _initializeDescriptions();
      }
    }
  }

  Future<void> _updateDataAndRecalculate(HealthData data) async {
    try {
      // Refresh latest questions and profile every time
      _latestQuestions = await _dailyQuestionsService
          .getLatestQuestions(); // Changed
      _userProfile = await _userProfileService.getUserProfile(); // Changed

      double? sleepFromForm = _latestQuestions?.calculatedSleepDuration;

      final historicalData = await widget.bleService.getAllHealthData();
      final baseline = HealthCalculationsService.calculateBaselines(
        historicalData,
      ); // Changed

      // Use real data if available, otherwise use reasonable defaults
      final bodyTemp = data.bodyTemperature > 0 ? data.bodyTemperature : 36.5;
      final breathingRate = data.breathingRate > 0 ? data.breathingRate : 16;

      final recoveryResult = HealthCalculationsService.calculateSleepNeed(
        age: _userProfile?.age ?? 25,
        rhrBaseline: baseline.rhrBaseline,
        rhrToday: data.rhr,
        hrvBaseline: baseline.hrvBaseline,
        hrvToday: data.hrv,
        steps: data.steps,
        calories: data.calories,
        sleepFromForm: sleepFromForm,
        spo2: data.spo2,
        stress: data.stress,
        bodyTemperature: bodyTemp,
        breathingRate: breathingRate,
        dailyQuestions: _latestQuestions,
      );

      if (mounted) {
        setState(() {
          _currentData = HealthData(
            heartRate: data.heartRate,
            steps: data.steps,
            spo2: data.spo2,
            calories: data.calories,
            sleep: sleepFromForm ?? 7.0, // Changed
            recovery: recoveryResult.recoveryPercent.round(),
            stress: data.stress,
            rhr: data.rhr,
            hrv: data.hrv,
            bodyTemperature: bodyTemp,
            breathingRate: breathingRate,
          );
        });

        await _calculateAllHealthScores();
        _updateDescriptionsOnDataChange();
      }
    } catch (e) {
      debugPrint('Error updating data and recalculating: $e');
      // Even if calculation fails, set default scores
      await _calculateAllHealthScores(); // Added
    }
  }

  Future<void> _loadCachedInsightsFirst() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final cachedInsights = await _aiCacheService.getCachedInsights();
      if (mounted) {
        setState(() {
          _metricDescriptions = Map<String, String>.from(cachedInsights);
        });
      }

      // Load initial data using the robust approach
      await _loadInitialData(); // Changed
      _previousDataSignature = _generateDataSignature();
    } catch (e) {
      debugPrint('Error loading cached insights in Matrix: $e');
      // Load default data if there's an error
      await _loadInitialData(); // Changed
      _previousDataSignature = _generateDataSignature();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _calculateAllHealthScores() async {
    if (_currentData == null) {
      // Set default scores if no data
      _setDefaultScores(); // Changed
      return;
    }

    // Only calculate scores if we have valid data
    if (_currentData!.rhr > 0 && _currentData!.hrv > 0) {
      try {
        // Added try-catch
        _vo2MaxScore = _calculateVO2Max();
        _stressResilienceScore = _calculateStressResilience();
        _sleepQualityScore = _calculateSleepQuality();
        _immunityDefenseScore = _calculateImmunityDefense();
        _metabolicHealthScore = _calculateMetabolicHealth();
        _brainPerformanceScore = _calculateBrainPerformance();
        _biologicalAgeScore = _calculateBiologicalAge();
        _trainingReadinessScore = _calculateTrainingReadiness();
        _hormonalBalanceScore = _calculateHormonalBalance();
        _inflammationLevelScore = _calculateInflammationLevel();
      } catch (e) {
        debugPrint('Error calculating health scores: $e');
        _setDefaultScores(); // Set default scores on error
      }
    } else {
      // Set default scores if data is invalid
      _setDefaultScores();
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _setDefaultScores() {
    // New method
    _vo2MaxScore = 65.0;
    _stressResilienceScore = 70.0;
    _sleepQualityScore = 75.0;
    _immunityDefenseScore = 68.0;
    _metabolicHealthScore = 72.0;
    _brainPerformanceScore = 69.0;
    _biologicalAgeScore = 71.0;
    _trainingReadinessScore = 66.0;
    _hormonalBalanceScore = 73.0;
    _inflammationLevelScore = 67.0;
  }

  // 1. VO2-max Calculation - IMPROVED
  double _calculateVO2Max() {
    final rhr = _currentData!.rhr;
    final steps = _currentData!.steps;
    final age = _userProfile?.age ?? 30; // Changed
    final calories = _currentData!.calories;
    final spo2 = _currentData!.spo2;

    // Prevent division by zero and handle zero values
    if (rhr == 0 || calories == 0) return 65.0; // Changed

    final hrMax = 208 - (0.7 * age);
    final vo2maxPrimary = 15.3 * (hrMax / rhr);
    final vo2maxEstimate =
        3.5 + 0.26 * (steps / max(calories, 1)) + 0.2 * spo2 - 0.1 * rhr;

    final vo2max = (vo2maxPrimary * 0.6 + vo2maxEstimate * 0.4).clamp(
      20.0,
      100.0,
    );
    return vo2max;
  }

  // 2. Stress Resilience Calculation - IMPROVED
  double _calculateStressResilience() {
    final stress = _currentData!.stress;
    final hrv = _currentData!.hrv;
    final rhr = _currentData!.rhr;
    final recovery = _currentData!.recovery;
    final feltStressed = _latestQuestions?.feltStressed ?? false;

    // Handle zero values
    if (hrv == 0) return 70.0; // Changed

    double resilience =
        50 + 0.4 * hrv - 0.3 * stress - 0.2 * (rhr - 60) + 0.2 * recovery;
    if (feltStressed) resilience -= 5;

    return resilience.clamp(0.0, 100.0);
  }

  // 3. Sleep Quality Calculation - IMPROVED
  double _calculateSleepQuality() {
    final sleep = _currentData!.sleep;
    final feltRested = _latestQuestions?.feltRested ?? false;
    final usedSleepAid = _latestQuestions?.usedSleepAid ?? false;
    final screenTimeBeforeBed =
        (_latestQuestions?.screenTimeBeforeBed as int?) ?? 0;
    final usualEnvironment = _latestQuestions?.usualEnvironment ?? false;

    final bedtime = _userProfile?.usualBedtime ?? "23:00"; // Changed
    final wakeTime = _userProfile?.usualWakeTime ?? "07:00"; // Changed

    final bedHour = int.parse(bedtime.split(":")[0]);
    final wakeHour = int.parse(wakeTime.split(":")[0]);
    double sleepDuration = wakeHour >= bedHour
        ? (wakeHour - bedHour).toDouble()
        : (24 - bedHour + wakeHour).toDouble();

    double sleepQuality =
        0.5 * ((sleepDuration / 8) * 100) +
        0.3 * sleep * 10 +
        (feltRested ? 10 : 0) -
        screenTimeBeforeBed * 5 -
        (usedSleepAid ? 5 : 0) +
        (usualEnvironment ? 5 : 0);

    return sleepQuality.clamp(0.0, 100.0);
  }

  // 4. Immunity Defense Calculation - IMPROVED
  double _calculateImmunityDefense() {
    final hrv = _currentData!.hrv;
    final rhr = _currentData!.rhr;
    final stress = _currentData!.stress;
    final sleep = _currentData!.sleep;
    final recovery = _currentData!.recovery;

    // Handle zero values
    if (hrv == 0) return 68.0; // Changed

    final immunity =
        0.4 * hrv +
        0.3 * recovery +
        0.2 * sleep * 10 -
        0.3 * stress -
        0.2 * (rhr - 60);

    return immunity.clamp(0.0, 100.0);
  }

  // 5. Metabolic Health Calculation - IMPROVED
  double _calculateMetabolicHealth() {
    final steps = _currentData!.steps;
    final calories = _currentData!.calories;
    final rhr = _currentData!.rhr;
    final sleep = _currentData!.sleep;

    final metabolic =
        0.5 * ((steps / 10000) * 100) +
        0.2 * ((2000 - max(calories, 1)) / 20) -
        0.2 * (rhr - 60) +
        0.1 * sleep * 10;

    return metabolic.clamp(0.0, 100.0);
  }

  // 6. Brain Performance Calculation - IMPROVED
  double _calculateBrainPerformance() {
    final stress = _currentData!.stress;
    final spo2 = _currentData!.spo2;
    final feltRested = _latestQuestions?.feltRested ?? false;
    final screenTimeBeforeBed =
        (_latestQuestions?.screenTimeBeforeBed as int?) ?? 0;

    final sleepQuality = _sleepQualityScore;

    final brain =
        0.4 * sleepQuality +
        0.2 * spo2 -
        0.3 * stress +
        (feltRested ? 10 : 0) -
        screenTimeBeforeBed * 5;

    return brain.clamp(0.0, 100.0);
  }

  // 7. Biological Age Calculation - IMPROVED
  double _calculateBiologicalAge() {
    final vo2max = _vo2MaxScore;
    final hrv = _currentData!.hrv;
    final rhr = _currentData!.rhr;
    final sleep = _currentData!.sleep;
    final stress = _currentData!.stress;
    final chronologicalAge = _userProfile?.age ?? 30; // Changed

    // Handle zero values
    if (hrv == 0) return 71.0; // Changed

    double bioAge =
        chronologicalAge -
        (vo2max - 35) * 0.5 +
        (rhr - 60) * 0.3 -
        hrv * 0.2 +
        stress * 0.2 -
        sleep * 0.1;

    final ageDifference = chronologicalAge - bioAge;
    final score = 50 + (ageDifference * 3);

    return score.clamp(0.0, 100.0);
  }

  // 8. Training Readiness Calculation - IMPROVED
  double _calculateTrainingReadiness() {
    final recovery = _currentData!.recovery;
    final sleep = _currentData!.sleep;
    final stress = _currentData!.stress;
    final rhr = _currentData!.rhr;

    final readiness =
        0.4 * recovery + 0.3 * sleep * 10 - 0.2 * stress - 0.1 * (rhr - 60);

    return readiness.clamp(0.0, 100.0);
  }

  // 9. Hormonal Balance Calculation - IMPROVED
  double _calculateHormonalBalance() {
    final stress = _currentData!.stress;
    final sleep = _currentData!.sleep;
    final hrv = _currentData!.hrv;
    final feltStressed = _latestQuestions?.feltStressed ?? false;
    final napped = _latestQuestions?.napped ?? false;

    // Handle zero values
    if (hrv == 0) return 73.0; // Changed

    double hormonal =
        50 +
        0.3 * hrv -
        0.4 * stress +
        0.2 * sleep * 10 +
        (napped ? 5 : 0) -
        (feltStressed ? 5 : 0);

    return hormonal.clamp(0.0, 100.0);
  }

  // 10. Inflammation Level Calculation - IMPROVED
  double _calculateInflammationLevel() {
    final rhr = _currentData!.rhr;
    final hrv = _currentData!.hrv;
    final stress = _currentData!.stress;
    final sleep = _currentData!.sleep;

    // Handle zero values
    if (hrv == 0) return 67.0; // Changed

    final inflammation =
        50 + 0.4 * (rhr - 60) - 0.3 * hrv + 0.2 * stress - 0.1 * sleep * 10;

    return (100 - inflammation).clamp(0.0, 100.0);
  }

  // AI Insight Management Methods
  String _generateDataSignature() {
    if (_currentData == null) return '';

    return '${_currentData!.heartRate}_${_currentData!.steps}_${_currentData!.spo2}_'
        '${_currentData!.calories}_${_currentData!.sleep}_${_currentData!.recovery}_'
        '${_currentData!.stress}_${_currentData!.rhr}_${_currentData!.hrv}_'
        '${_currentData!.bodyTemperature}_${_currentData!.breathingRate}_'
        '${_vo2MaxScore.toStringAsFixed(0)}_${_stressResilienceScore.toStringAsFixed(0)}_'
        '${_sleepQualityScore.toStringAsFixed(0)}_${_immunityDefenseScore.toStringAsFixed(0)}_'
        '${_metabolicHealthScore.toStringAsFixed(0)}_${_brainPerformanceScore.toStringAsFixed(0)}_'
        '${_biologicalAgeScore.toStringAsFixed(0)}_${_trainingReadinessScore.toStringAsFixed(0)}_'
        '${_hormonalBalanceScore.toStringAsFixed(0)}_${_inflammationLevelScore.toStringAsFixed(0)}';
  }

  bool _hasDataChangedSignificantly() {
    final newSignature = _generateDataSignature();
    final hasChanged = newSignature != _previousDataSignature;
    if (hasChanged) {
      _previousDataSignature = newSignature;
    }
    return hasChanged;
  }

  void _initializeDescriptions() {
    final metrics = [
      'VO₂-max',
      'Stress Resilience',
      'Sleep Quality',
      'Immunity Defense',
      'Metabolic Health',
      'Brain Performance',
      'Biological Age',
      'Training Readiness',
      'Hormonal Balance',
      'Inflammation Level',
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
      debugPrint('Data changed significantly, updating AI insights...');
      _updateDescriptions();
    } else {
      debugPrint('Data unchanged, keeping existing AI insights');
    }
  }

  void _updateDescriptions() {
    _updateDescriptionForMetric(
      'VO₂-max',
      _vo2MaxScore.toStringAsFixed(0),
      'Score',
    );
    _updateDescriptionForMetric(
      'Stress Resilience',
      _stressResilienceScore.toStringAsFixed(0),
      'Score',
    );
    _updateDescriptionForMetric(
      'Sleep Quality',
      _sleepQualityScore.toStringAsFixed(0),
      'Score',
    );
    _updateDescriptionForMetric(
      'Immunity Defense',
      _immunityDefenseScore.toStringAsFixed(0),
      'Score',
    );
    _updateDescriptionForMetric(
      'Metabolic Health',
      _metabolicHealthScore.toStringAsFixed(0),
      'Score',
    );
    _updateDescriptionForMetric(
      'Brain Performance',
      _brainPerformanceScore.toStringAsFixed(0),
      'Score',
    );
    _updateDescriptionForMetric(
      'Biological Age',
      _biologicalAgeScore.toStringAsFixed(0),
      'Score',
    );
    _updateDescriptionForMetric(
      'Training Readiness',
      _trainingReadinessScore.toStringAsFixed(0),
      'Score',
    );
    _updateDescriptionForMetric(
      'Hormonal Balance',
      _hormonalBalanceScore.toStringAsFixed(0),
      'Score',
    );
    _updateDescriptionForMetric(
      'Inflammation Level',
      _inflammationLevelScore.toStringAsFixed(0),
      'Score',
    );
  }

  void _updateDescriptionForMetric(
    String metricName,
    String value,
    String unit,
  ) {
    if (_currentData == null) return;

    if (_aiService.hasCachedDescription(_currentData!, metricName)) {
      final cachedDescription = _aiService.getCachedDescription(
        _currentData!,
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
          currentData: _currentData!,
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
          debugPrint('Error getting description for $metricName: $error');
          if (mounted) {
            setState(() {
              _descriptionLoading[metricName] = false;
            });
          }
        });
  }

  void _refreshDescription(String metricName) {
    String value = '';
    String unit = 'Score';

    switch (metricName) {
      case 'VO₂-max':
        value = _vo2MaxScore.toStringAsFixed(0);
        break;
      case 'Stress Resilience':
        value = _stressResilienceScore.toStringAsFixed(0);
        break;
      case 'Sleep Quality':
        value = _sleepQualityScore.toStringAsFixed(0);
        break;
      case 'Immunity Defense':
        value = _immunityDefenseScore.toStringAsFixed(0);
        break;
      case 'Metabolic Health':
        value = _metabolicHealthScore.toStringAsFixed(0);
        break;
      case 'Brain Performance':
        value = _brainPerformanceScore.toStringAsFixed(0);
        break;
      case 'Biological Age':
        value = _biologicalAgeScore.toStringAsFixed(0);
        break;
      case 'Training Readiness':
        value = _trainingReadinessScore.toStringAsFixed(0);
        break;
      case 'Hormonal Balance':
        value = _hormonalBalanceScore.toStringAsFixed(0);
        break;
      case 'Inflammation Level':
        value = _inflammationLevelScore.toStringAsFixed(0);
        break;
    }

    setState(() {
      _descriptionLoading[metricName] = true;
    });

    _aiService
        .updateMetricDescriptionManual(metricName, value, unit, _currentData!)
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
          debugPrint('Error refreshing description for $metricName: $error');
          if (mounted) {
            setState(() {
              _descriptionLoading[metricName] = false;
            });
          }
        });
  }

  Color _getScoreColor(double score) {
    if (score >= 80) return const Color(0xFF4CAF50);
    if (score >= 60) return const Color(0xFF2196F3);
    if (score >= 40) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  String _getScoreStatus(double score) {
    if (score >= 80) return 'Excellent';
    if (score >= 60) return 'Good';
    if (score >= 40) return 'Fair';
    return 'Needs Attention';
  }

  String _getScoreAnalysis(double score, String metricName) {
    if (score >= 80)
      return 'Your $metricName is in optimal range. Keep up the great work!';
    if (score >= 60)
      return 'Your $metricName is good. Small improvements can help.';
    if (score >= 40)
      return 'Your $metricName needs attention. Focus on recovery.';
    return 'Your $metricName requires immediate attention. Prioritize rest.';
  }

  Widget _buildGradientBorderCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF000000),
            const Color(0xFF0A0A0A),
            const Color(0xFF7E7E7E).withOpacity(0.2),
            const Color(0xFF0A0A0A),
            const Color(0xFF000000),
          ],
          stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18.5),
            color: const Color(0xFF0D0D0D).withOpacity(0.95),
          ),
          child: child,
        ),
      ),
    );
  }

  // Build Circular Progress Ring
  Widget _buildCircularProgress(
    double value,
    Color color, {
    double size = 120,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: value / 100,
              strokeWidth: 8,
              backgroundColor: const Color(0xFF1A1A1A),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${value.toStringAsFixed(0)}',
                style: TextStyle(
                  color: color,
                  fontSize: size * 0.22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Score',
                style: TextStyle(
                  color: const Color(0xFFA0A0A0),
                  fontSize: size * 0.1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Build Line Chart
  Widget _buildLineChart(double value, Color color) {
    final spots = List.generate(
      7,
      (index) => FlSpot(
        index.toDouble(),
        (value - 10 + Random().nextDouble() * 20).clamp(0, 100),
      ),
    );

    return SizedBox(
      height: 100,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: false),
          titlesData: FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          minY: 0,
          maxY: 100,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: color,
              barWidth: 3,
              dotData: FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [color.withOpacity(0.3), color.withOpacity(0.05)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build Bar Chart
  Widget _buildBarChart(double value, Color color) {
    return SizedBox(
      height: 100,
      child: BarChart(
        BarChartData(
          gridData: FlGridData(show: false),
          titlesData: FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(
            5,
            (index) => BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: (value - 10 + Random().nextDouble() * 20).clamp(10, 100),
                  color: color,
                  width: 20,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Build Gauge Chart
  Widget _buildGaugeChart(double value, Color color) {
    return SizedBox(
      height: 120,
      width: 120,
      child: CustomPaint(painter: _GaugePainter(value, color)),
    );
  }

  // 1. VO2-max Card - Neon Blue Circular Gauge
  Widget _buildVO2MaxCard() {
    return Column(
      children: [
        _buildGradientBorderCard(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18.5),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1A1F3A).withOpacity(0.8),
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF2196F3).withOpacity(0.3),
                                const Color(0xFF0D47A1).withOpacity(0.1),
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.directions_run_rounded,
                            color: Color(0xFF2196F3),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'VO₂-max',
                              style: TextStyle(
                                color: Color(0xFFE8E8E8),
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Aerobic Fitness',
                              style: TextStyle(
                                color: const Color(0xFFA0A0A0).withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getScoreColor(_vo2MaxScore).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getScoreColor(_vo2MaxScore).withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        _getScoreStatus(_vo2MaxScore),
                        style: TextStyle(
                          color: _getScoreColor(_vo2MaxScore),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _buildGaugeChart(_vo2MaxScore, const Color(0xFF2196F3)),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getScoreAnalysis(_vo2MaxScore, 'cardio fitness'),
                            style: const TextStyle(
                              color: Color(0xFFE8E8E8),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildMetricRow(
                            'RHR',
                            '${_currentData?.rhr ?? 0} bpm',
                            const Color(0xFF2196F3),
                          ),
                          const SizedBox(height: 6),
                          _buildMetricRow(
                            'Steps',
                            '${_currentData?.steps ?? 0}',
                            const Color(0xFF2196F3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        _buildAiInsightSection('VO₂-max'),
      ],
    );
  }

  // 2. Stress Resilience Card - Blue-Lavender Gradient
  Widget _buildStressResilienceCard() {
    return Column(
      children: [
        _buildGradientBorderCard(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18.5),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1A1A3A).withOpacity(0.8),
                  const Color(0xFF2A1A3A).withOpacity(0.6),
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF9C27B0).withOpacity(0.3),
                                const Color(0xFF673AB7).withOpacity(0.1),
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.favorite_rounded,
                            color: Color(0xFF9C27B0),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Stress Resilience',
                              style: TextStyle(
                                color: Color(0xFFE8E8E8),
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Recovery Capacity',
                              style: TextStyle(
                                color: const Color(0xFFA0A0A0).withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getScoreColor(
                          _stressResilienceScore,
                        ).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getScoreColor(
                            _stressResilienceScore,
                          ).withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        _getScoreStatus(_stressResilienceScore),
                        style: TextStyle(
                          color: _getScoreColor(_stressResilienceScore),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _buildCircularProgress(
                      _stressResilienceScore,
                      const Color(0xFF9C27B0),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getScoreAnalysis(
                              _stressResilienceScore,
                              'stress resilience',
                            ),
                            style: const TextStyle(
                              color: Color(0xFFE8E8E8),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildMetricRow(
                            'HRV',
                            '${_currentData?.hrv ?? 0} ms',
                            const Color(0xFF9C27B0),
                          ),
                          const SizedBox(height: 6),
                          _buildMetricRow(
                            'Stress',
                            '${_currentData?.stress ?? 0}%',
                            const Color(0xFF9C27B0),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildLineChart(
                  _stressResilienceScore,
                  const Color(0xFF9C27B0),
                ),
              ],
            ),
          ),
        ),
        _buildAiInsightSection('Stress Resilience'),
      ],
    );
  }

  // 3. Sleep Quality Card - Purple Gradient
  Widget _buildSleepQualityCard() {
    return Column(
      children: [
        _buildGradientBorderCard(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18.5),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1A1A2E).withOpacity(0.8),
                  const Color(0xFF2D1B4E).withOpacity(0.6),
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF673AB7).withOpacity(0.3),
                                const Color(0xFF512DA8).withOpacity(0.1),
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.nightlight_round_rounded,
                            color: Color(0xFF673AB7),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Sleep Quality',
                              style: TextStyle(
                                color: Color(0xFFE8E8E8),
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Overnight Recovery',
                              style: TextStyle(
                                color: const Color(0xFFA0A0A0).withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getScoreColor(
                          _sleepQualityScore,
                        ).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getScoreColor(
                            _sleepQualityScore,
                          ).withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        _getScoreStatus(_sleepQualityScore),
                        style: TextStyle(
                          color: _getScoreColor(_sleepQualityScore),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _buildCircularProgress(
                      _sleepQualityScore,
                      const Color(0xFF673AB7),
                      size: 120,
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getScoreAnalysis(
                              _sleepQualityScore,
                              'sleep quality',
                            ),
                            style: const TextStyle(
                              color: Color(0xFFE8E8E8),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildMetricRow(
                            'Duration',
                            '${_currentData?.sleep ?? 0}h',
                            const Color(0xFF673AB7),
                          ),
                          const SizedBox(height: 6),
                          _buildMetricRow(
                            'Felt Rested',
                            '${_latestQuestions?.feltRested ?? false ? "Yes" : "No"}',
                            const Color(0xFF673AB7),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        _buildAiInsightSection('Sleep Quality'),
      ],
    );
  }

  // 4. Immunity Defense Card - Green Gradient
  Widget _buildImmunityDefenseCard() {
    return Column(
      children: [
        _buildGradientBorderCard(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18.5),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1A2E1A).withOpacity(0.8),
                  const Color(0xFF0D4D0D).withOpacity(0.6),
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF4CAF50).withOpacity(0.3),
                                const Color(0xFF388E3C).withOpacity(0.1),
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.health_and_safety_rounded,
                            color: Color(0xFF4CAF50),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Immunity Defense',
                              style: TextStyle(
                                color: Color(0xFFE8E8E8),
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Infection Risk',
                              style: TextStyle(
                                color: const Color(0xFFA0A0A0).withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getScoreColor(
                          _immunityDefenseScore,
                        ).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getScoreColor(
                            _immunityDefenseScore,
                          ).withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        _getScoreStatus(_immunityDefenseScore),
                        style: TextStyle(
                          color: _getScoreColor(_immunityDefenseScore),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _buildCircularProgress(
                      _immunityDefenseScore,
                      const Color(0xFF4CAF50),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getScoreAnalysis(
                              _immunityDefenseScore,
                              'immunity',
                            ),
                            style: const TextStyle(
                              color: Color(0xFFE8E8E8),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildMetricRow(
                            'Recovery',
                            '${_currentData?.recovery ?? 0}%',
                            const Color(0xFF4CAF50),
                          ),
                          const SizedBox(height: 6),
                          _buildMetricRow(
                            'HRV',
                            '${_currentData?.hrv ?? 0} ms',
                            const Color(0xFF4CAF50),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildBarChart(_immunityDefenseScore, const Color(0xFF4CAF50)),
              ],
            ),
          ),
        ),
        _buildAiInsightSection('Immunity Defense'),
      ],
    );
  }

  // 5. Metabolic Health Card - Orange Gradient
  Widget _buildMetabolicHealthCard() {
    return Column(
      children: [
        _buildGradientBorderCard(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18.5),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF2E1A0D).withOpacity(0.8),
                  const Color(0xFF4D2D0D).withOpacity(0.6),
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFFFF9800).withOpacity(0.3),
                                const Color(0xFFF57C00).withOpacity(0.1),
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.local_fire_department_rounded,
                            color: Color(0xFFFF9800),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Metabolic Health',
                              style: TextStyle(
                                color: Color(0xFFE8E8E8),
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Energy Efficiency',
                              style: TextStyle(
                                color: const Color(0xFFA0A0A0).withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getScoreColor(
                          _metabolicHealthScore,
                        ).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getScoreColor(
                            _metabolicHealthScore,
                          ).withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        _getScoreStatus(_metabolicHealthScore),
                        style: TextStyle(
                          color: _getScoreColor(_metabolicHealthScore),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _buildGaugeChart(
                      _metabolicHealthScore,
                      const Color(0xFFFF9800),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getScoreAnalysis(
                              _metabolicHealthScore,
                              'metabolic health',
                            ),
                            style: const TextStyle(
                              color: Color(0xFFE8E8E8),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildMetricRow(
                            'Steps',
                            '${_currentData?.steps ?? 0}',
                            const Color(0xFFFF9800),
                          ),
                          const SizedBox(height: 6),
                          _buildMetricRow(
                            'Calories',
                            '${_currentData?.calories ?? 0}',
                            const Color(0xFFFF9800),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        _buildAiInsightSection('Metabolic Health'),
      ],
    );
  }

  // 6. Brain Performance Card - Cyan Gradient
  Widget _buildBrainPerformanceCard() {
    return Column(
      children: [
        _buildGradientBorderCard(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18.5),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF0D2E3A).withOpacity(0.8),
                  const Color(0xFF0D3D4D).withOpacity(0.6),
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF00BCD4).withOpacity(0.3),
                                const Color(0xFF0097A7).withOpacity(0.1),
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.psychology_rounded,
                            color: Color(0xFF00BCD4),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Brain Performance',
                              style: TextStyle(
                                color: Color(0xFFE8E8E8),
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Cognitive Function',
                              style: TextStyle(
                                color: const Color(0xFFA0A0A0).withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getScoreColor(
                          _brainPerformanceScore,
                        ).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getScoreColor(
                            _brainPerformanceScore,
                          ).withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        _getScoreStatus(_brainPerformanceScore),
                        style: TextStyle(
                          color: _getScoreColor(_brainPerformanceScore),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _buildCircularProgress(
                      _brainPerformanceScore,
                      const Color(0xFF00BCD4),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getScoreAnalysis(
                              _brainPerformanceScore,
                              'brain performance',
                            ),
                            style: const TextStyle(
                              color: Color(0xFFE8E8E8),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildMetricRow(
                            'SpO₂',
                            '${_currentData?.spo2 ?? 0}%',
                            const Color(0xFF00BCD4),
                          ),
                          const SizedBox(height: 6),
                          _buildMetricRow(
                            'Stress',
                            '${_currentData?.stress ?? 0}%',
                            const Color(0xFF00BCD4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildLineChart(
                  _brainPerformanceScore,
                  const Color(0xFF00BCD4),
                ),
              ],
            ),
          ),
        ),
        _buildAiInsightSection('Brain Performance'),
      ],
    );
  }

  // 7. Biological Age Card - Dark Blue Gradient
  Widget _buildBiologicalAgeCard() {
    return Column(
      children: [
        _buildGradientBorderCard(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18.5),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF0D1A2E).withOpacity(0.8),
                  const Color(0xFF1A2D4D).withOpacity(0.6),
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF3F51B5).withOpacity(0.3),
                                const Color(0xFF303F9F).withOpacity(0.1),
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.access_time_rounded,
                            color: Color(0xFF3F51B5),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Biological Age',
                              style: TextStyle(
                                color: Color(0xFFE8E8E8),
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'vs Chronological',
                              style: TextStyle(
                                color: const Color(0xFFA0A0A0).withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getScoreColor(
                          _biologicalAgeScore,
                        ).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getScoreColor(
                            _biologicalAgeScore,
                          ).withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        _getScoreStatus(_biologicalAgeScore),
                        style: TextStyle(
                          color: _getScoreColor(_biologicalAgeScore),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _buildGaugeChart(
                      _biologicalAgeScore,
                      const Color(0xFF3F51B5),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getScoreAnalysis(
                              _biologicalAgeScore,
                              'biological age',
                            ),
                            style: const TextStyle(
                              color: Color(0xFFE8E8E8),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildMetricRow(
                            'Age',
                            '${_userProfile?.age ?? 0} years',
                            const Color(0xFF3F51B5),
                          ),
                          const SizedBox(height: 6),
                          _buildMetricRow(
                            'VO₂-max',
                            '${_vo2MaxScore.toStringAsFixed(0)}',
                            const Color(0xFF3F51B5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        _buildAiInsightSection('Biological Age'),
      ],
    );
  }

  // 8. Training Readiness Card - Yellow-Green Gradient
  Widget _buildTrainingReadinessCard() {
    return Column(
      children: [
        _buildGradientBorderCard(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18.5),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF2E2E0D).withOpacity(0.8),
                  const Color(0xFF3D4D0D).withOpacity(0.6),
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF8BC34A).withOpacity(0.3),
                                const Color(0xFF689F38).withOpacity(0.1),
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.fitness_center_rounded,
                            color: Color(0xFF8BC34A),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Training Readiness',
                              style: TextStyle(
                                color: Color(0xFFE8E8E8),
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Workout Capacity',
                              style: TextStyle(
                                color: const Color(0xFFA0A0A0).withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getScoreColor(
                          _trainingReadinessScore,
                        ).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getScoreColor(
                            _trainingReadinessScore,
                          ).withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        _getScoreStatus(_trainingReadinessScore),
                        style: TextStyle(
                          color: _getScoreColor(_trainingReadinessScore),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _buildCircularProgress(
                      _trainingReadinessScore,
                      const Color(0xFF8BC34A),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getScoreAnalysis(
                              _trainingReadinessScore,
                              'training readiness',
                            ),
                            style: const TextStyle(
                              color: Color(0xFFE8E8E8),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildMetricRow(
                            'Recovery',
                            '${_currentData?.recovery ?? 0}%',
                            const Color(0xFF8BC34A),
                          ),
                          const SizedBox(height: 6),
                          _buildMetricRow(
                            'Sleep',
                            '${_currentData?.sleep ?? 0}h',
                            const Color(0xFF8BC34A),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildBarChart(
                  _trainingReadinessScore,
                  const Color(0xFF8BC34A),
                ),
              ],
            ),
          ),
        ),
        _buildAiInsightSection('Training Readiness'),
      ],
    );
  }

  // 9. Hormonal Balance Card - Pink-Orange Gradient
  Widget _buildHormonalBalanceCard() {
    return Column(
      children: [
        _buildGradientBorderCard(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18.5),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF2E1A1A).withOpacity(0.8),
                  const Color(0xFF4D2D1A).withOpacity(0.6),
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFFE91E63).withOpacity(0.3),
                                const Color(0xFFC2185B).withOpacity(0.1),
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.balance_rounded,
                            color: Color(0xFFE91E63),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Hormonal Balance',
                              style: TextStyle(
                                color: Color(0xFFE8E8E8),
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Endocrine Health',
                              style: TextStyle(
                                color: const Color(0xFFA0A0A0).withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getScoreColor(
                          _hormonalBalanceScore,
                        ).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getScoreColor(
                            _hormonalBalanceScore,
                          ).withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        _getScoreStatus(_hormonalBalanceScore),
                        style: TextStyle(
                          color: _getScoreColor(_hormonalBalanceScore),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _buildCircularProgress(
                      _hormonalBalanceScore,
                      const Color(0xFFE91E63),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getScoreAnalysis(
                              _hormonalBalanceScore,
                              'hormonal balance',
                            ),
                            style: const TextStyle(
                              color: Color(0xFFE8E8E8),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildMetricRow(
                            'HRV',
                            '${_currentData?.hrv ?? 0} ms',
                            const Color(0xFFE91E63),
                          ),
                          const SizedBox(height: 6),
                          _buildMetricRow(
                            'Stress',
                            '${_currentData?.stress ?? 0}%',
                            const Color(0xFFE91E63),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildLineChart(_hormonalBalanceScore, const Color(0xFFE91E63)),
              ],
            ),
          ),
        ),
        _buildAiInsightSection('Hormonal Balance'),
      ],
    );
  }

  // 10. Inflammation Level Card - Red-Yellow Gradient
  Widget _buildInflammationLevelCard() {
    return Column(
      children: [
        _buildGradientBorderCard(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18.5),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF2E0D0D).withOpacity(0.8),
                  const Color(0xFF4D1A0D).withOpacity(0.6),
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFFFF5722).withOpacity(0.3),
                                const Color(0xFFE64A19).withOpacity(0.1),
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.warning_rounded,
                            color: Color(0xFFFF5722),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Inflammation Level',
                              style: TextStyle(
                                color: Color(0xFFE8E8E8),
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Body Inflammation',
                              style: TextStyle(
                                color: const Color(0xFFA0A0A0).withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getScoreColor(
                          _inflammationLevelScore,
                        ).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getScoreColor(
                            _inflammationLevelScore,
                          ).withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        _getScoreStatus(_inflammationLevelScore),
                        style: TextStyle(
                          color: _getScoreColor(_inflammationLevelScore),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _buildGaugeChart(
                      _inflammationLevelScore,
                      const Color(0xFFFF5722),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getScoreAnalysis(
                              _inflammationLevelScore,
                              'inflammation',
                            ),
                            style: const TextStyle(
                              color: Color(0xFFE8E8E8),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildMetricRow(
                            'RHR',
                            '${_currentData?.rhr ?? 0} bpm',
                            const Color(0xFFFF5722),
                          ),
                          const SizedBox(height: 6),
                          _buildMetricRow(
                            'Temp',
                            '${_currentData?.bodyTemperature.toStringAsFixed(1) ?? 0}°C',
                            const Color(0xFFFF5722),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        _buildAiInsightSection('Inflammation Level'),
      ],
    );
  }

  Widget _buildMetricRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: const Color(0xFFA0A0A0).withOpacity(0.8),
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // Reusable AI Insight Section Widget
  Widget _buildAiInsightSection(String metricName) {
    final isLoading = _descriptionLoading[metricName] ?? false;
    final description = _metricDescriptions[metricName] ?? '';

    if (description.isEmpty && !isLoading) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A).withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF333333), width: 1),
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
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                    onPressed: () => _refreshDescription(metricName),
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
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF808080),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  )
                : Text(
                    description,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF808080),
                      fontSize: 13,
                      height: 1.4,
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
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF4A7BDB)),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Your Vitality Insights',
                      style: TextStyle(
                        color: Color(0xFFE8E8E8),
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Personalized scores and analysis for your health metrics.',
                      style: TextStyle(
                        color: const Color(0xFFA0A0A0).withOpacity(0.8),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          _isConnected
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth_disabled,
                          color: _isConnected ? Colors.green : Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isConnected ? 'Connected' : 'Disconnected',
                          style: TextStyle(
                            color: _isConnected ? Colors.green : Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    _buildVO2MaxCard(),
                    const SizedBox(height: 20),
                    _buildStressResilienceCard(),
                    const SizedBox(height: 20),
                    _buildSleepQualityCard(),
                    const SizedBox(height: 20),
                    _buildImmunityDefenseCard(),
                    const SizedBox(height: 20),
                    _buildMetabolicHealthCard(),
                    const SizedBox(height: 20),
                    _buildBrainPerformanceCard(),
                    const SizedBox(height: 20),
                    _buildBiologicalAgeCard(),
                    const SizedBox(height: 20),
                    _buildTrainingReadinessCard(),
                    const SizedBox(height: 20),
                    _buildHormonalBalanceCard(),
                    const SizedBox(height: 20),
                    _buildInflammationLevelCard(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color color;

  _GaugePainter(this.value, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    const strokeWidth = 8.0;

    // Background arc
    final backgroundPaint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi * 0.75,
      pi * 1.5,
      false,
      backgroundPaint,
    );

    // Value arc
    final valuePaint = Paint()
      ..shader = LinearGradient(
        colors: [color.withOpacity(0.6), color],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = (value / 100) * (pi * 1.5);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi * 0.75,
      sweepAngle,
      false,
      valuePaint,
    );

    // Text for value
    final textSpan = TextSpan(
      text: '${value.toStringAsFixed(0)}',
      style: TextStyle(
        color: color,
        fontSize: radius * 0.4,
        fontWeight: FontWeight.w700,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(minWidth: 0, maxWidth: size.width);
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2 - radius * 0.1,
      ),
    );

    // Text for 'Score'
    final scoreTextSpan = TextSpan(
      text: 'Score',
      style: TextStyle(color: const Color(0xFFA0A0A0), fontSize: radius * 0.18),
    );
    final scoreTextPainter = TextPainter(
      text: scoreTextSpan,
      textDirection: TextDirection.ltr,
    );
    scoreTextPainter.layout(minWidth: 0, maxWidth: size.width);
    scoreTextPainter.paint(
      canvas,
      Offset(center.dx - scoreTextPainter.width / 2, center.dy + radius * 0.1),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is _GaugePainter) {
      return oldDelegate.value != value || oldDelegate.color != color;
    }
    return true;
  }
}
