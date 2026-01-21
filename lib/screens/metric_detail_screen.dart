import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:zyora_final/local_storage_service.dart';
import 'dart:async';
import 'package:zyora_final/services/ai_description_service.dart';
import 'package:zyora_final/services/ble_service.dart';
import 'package:zyora_final/services/health_calculations_service.dart';
import 'package:zyora_final/services/daily_questions_service.dart';

class MetricDetailScreen extends StatefulWidget {
  final String metricName;
  final String currentValue;
  final String unit;
  final IconData icon;
  final Color color;
  final BLEService bleService;

  const MetricDetailScreen({
    super.key,
    required this.metricName,
    required this.currentValue,
    required this.unit,
    required this.icon,
    required this.color,
    required this.bleService,
  });

  @override
  State<MetricDetailScreen> createState() => _MetricDetailScreenState();
}

class _MetricDetailScreenState extends State<MetricDetailScreen> {
  final AIDescriptionService _aiService = AIDescriptionService();
  final DailyQuestionsService _dailyQuestionsService = DailyQuestionsService();
  Timer? _dataUpdateTimer;

  // Data for both bar and line charts
  List<Map<String, dynamic>> _weeklyBarData = [];
  List<Map<String, dynamic>> _weeklyLineData = [];
  bool _isLoading = true;
  String _aiInsight = '';
  bool _isGeneratingInsight = false;
  HealthData? _currentHealthData;
  int _selectedChartType = 0; // 0 for bar, 1 for line

  @override
  void initState() {
    super.initState();
    _loadWeeklyData();
    _loadCurrentHealthData();
    _startDataUpdates();
  }

  @override
  void dispose() {
    _dataUpdateTimer?.cancel();
    super.dispose();
  }

  void _startDataUpdates() {
    _dataUpdateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _loadWeeklyData();
    });
  }

  Future<void> _loadCurrentHealthData() async {
    try {
      final latestData = await widget.bleService.getLatestHealthData();
      final allData = await widget.bleService.getAllHealthData();
      final allQuestions = await _dailyQuestionsService.getAllQuestions();
      final dailyBaselines = HealthCalculationsService.calculateDailyBaselines(
        allData,
        allQuestions,
      );
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      final todayBaselines = dailyBaselines[todayStr] ?? {'rhr': 65, 'hrv': 45};
      final currentRHR = todayBaselines['rhr'] ?? 65;
      final currentHRV = todayBaselines['hrv'] ?? 45;

      if (latestData != null) {
        setState(() {
          _currentHealthData = HealthData(
            heartRate: latestData.heartRate,
            steps: latestData.steps,
            spo2: latestData.spo2,
            calories: latestData.calories,
            sleep: latestData.sleep,
            recovery: latestData.recovery,
            stress: latestData.stress,
            rhr: currentRHR, // Use calculated RHR
            hrv: currentHRV, // Use calculated HRV
            bodyTemperature: latestData.bodyTemperature,
            breathingRate: latestData.breathingRate,
          );
        });
        _generateAIInsight();
      }
    } catch (e) {
      print('Error loading current health data: $e');
    }
  }

  Future<void> _loadWeeklyData() async {
    try {
      final now = DateTime.now();

      // Get all raw health data
      final allHealthData = await widget.bleService.getAllHealthData();

      // Process data for daily values
      final Map<String, List<HealthData>> dailyGroups = {};

      for (var dataPoint in allHealthData) {
        final dayKey = _getDayKey(dataPoint.timestamp);
        dailyGroups
            .putIfAbsent(dayKey, () => [])
            .add(
              HealthData(
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
              ),
            );
      }

      // Pre-calculate Daily Baselines for the whole week to use in calculations
      final dailyBaselines = HealthCalculationsService.calculateDailyBaselines(
        allHealthData,
        await _dailyQuestionsService.getAllQuestions(),
      );

      // Create weekly data structure for bar chart
      final List<Map<String, dynamic>> weeklyBarData = [];

      // PRE-CALCULATE OVERALL BASELINES ONCE for consistent recovery/health calculations
      final globalBaselineData = HealthCalculationsService.calculateBaselines(
        allHealthData,
      );

      // Generate last 7 days
      for (int i = 6; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        final dayKey = _getDayKey(date);
        final dayDataPoints = dailyGroups[dayKey] ?? [];

        // Calculate daily value for the specific metric - FIXED LOGIC
        double dailyValue = await _calculateDailyValue(
          dayDataPoints: dayDataPoints,
          date: date,
          dailyBaselines: dailyBaselines,
          globalBaseline: globalBaselineData,
        );

        weeklyBarData.add({
          'day': _getDayName(date.weekday),
          'date': date,
          'value': dailyValue,
          'fullDate': _formatDate(date),
          'isToday': i == 0,
          'rawDataPoints': dayDataPoints,
        });
      }

      // Process data for line chart
      final List<Map<String, dynamic>> weeklyLineData = [];

      for (int i = 6; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        final dayKey = _getDayKey(date);
        final dayDataPoints = dailyGroups[dayKey] ?? [];

        double dailyValue = await _calculateDailyValue(
          dayDataPoints: dayDataPoints,
          date: date,
          dailyBaselines: dailyBaselines,
          globalBaseline: globalBaselineData,
        );
        double sleepNeeded = _calculateSleepNeeded(date);

        weeklyLineData.add({
          'day': _getDayName(date.weekday),
          'date': date,
          'value': dailyValue,
          'sleepNeeded': sleepNeeded,
          'fullDate': _formatDate(date),
          'isToday': i == 0,
          'rawDataPoints': dayDataPoints,
        });
      }

      if (mounted) {
        setState(() {
          _weeklyBarData = weeklyBarData;
          _weeklyLineData = weeklyLineData;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading weekly data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // FIXED: Calculate daily values with proper logic for each metric
  Future<double> _calculateDailyValue({
    required List<HealthData> dayDataPoints,
    required DateTime date,
    required Map<String, Map<String, int>> dailyBaselines,
    BaselineData? globalBaseline,
  }) async {
    if (dayDataPoints.isEmpty && widget.metricName != 'RHR') return 0.0;

    final dateStr = date.toIso8601String().split('T')[0];

    switch (widget.metricName) {
      case 'Heart Rate':
        return dayDataPoints.isNotEmpty
            ? dayDataPoints.last.heartRate.toDouble()
            : 0.0;

      case 'Steps':
        return dayDataPoints.isNotEmpty
            ? dayDataPoints
                  .map((e) => e.steps)
                  .reduce((a, b) => a > b ? a : b)
                  .toDouble()
            : 0.0;

      case 'Sleep':
        try {
          final questions = await _dailyQuestionsService.getQuestionsForDate(
            date,
          );
          if (questions != null && questions.calculatedSleepDuration != null) {
            return questions.calculatedSleepDuration!;
          }
          return dayDataPoints.isNotEmpty
              ? dayDataPoints
                    .map((e) => e.sleep)
                    .reduce((a, b) => a > b ? a : b)
              : 0.0;
        } catch (e) {
          return 0.0;
        }

      case 'Calories':
        return dayDataPoints.isNotEmpty
            ? dayDataPoints
                  .map((e) => e.calories)
                  .reduce((a, b) => a > b ? a : b)
                  .toDouble()
            : 0.0;

      case 'SpO₂':
        return dayDataPoints.isNotEmpty
            ? dayDataPoints.last.spo2.toDouble()
            : 0.0;

      case 'Recovery':
        try {
          final questions = await _dailyQuestionsService.getQuestionsForDate(
            date,
          );
          double? sleepFromForm = questions?.calculatedSleepDuration;
          final dayMetrics = dailyBaselines[dateStr] ?? {'rhr': 65, 'hrv': 45};
          final dayRHR = dayMetrics['rhr'] ?? 65;
          final dayHRV = dayMetrics['hrv'] ?? 45;

          HealthData? bestDataPoint;
          double bestRecoveryScore = 0.0;

          for (var dataPoint in dayDataPoints) {
            double recoveryPotential = dayHRV.toDouble() - (dayRHR / 2.0);

            if (recoveryPotential > bestRecoveryScore) {
              bestRecoveryScore = recoveryPotential;
              bestDataPoint = dataPoint;
            }
          }

          final dataToUse =
              bestDataPoint ??
              (dayDataPoints.isNotEmpty ? dayDataPoints.last : null);

          if (dataToUse != null) {
            final result = HealthCalculationsService.calculateSleepNeed(
              age: 25,
              rhrBaseline: globalBaseline?.rhrBaseline ?? 65,
              rhrToday: dayRHR,
              hrvBaseline: globalBaseline?.hrvBaseline ?? 45,
              hrvToday: dayHRV,
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
          return 0.0;
        } catch (e) {
          return 0.0;
        }

      case 'Health Score':
        try {
          final questions = await _dailyQuestionsService.getQuestionsForDate(
            date,
          );
          double? sleepFromForm = questions?.calculatedSleepDuration;
          final dayMetrics = dailyBaselines[dateStr] ?? {'rhr': 60, 'hrv': 45};
          final dayRHR = dayMetrics['rhr'] ?? 60;
          final dayHRV = dayMetrics['hrv'] ?? 45;

          final dataToUse = dayDataPoints.isNotEmpty
              ? dayDataPoints.last
              : null;

          if (dataToUse != null) {
            final result = HealthCalculationsService.calculateSleepNeed(
              age: 25,
              rhrBaseline: globalBaseline?.rhrBaseline ?? 60,
              rhrToday: dayRHR,
              hrvBaseline: globalBaseline?.hrvBaseline ?? 45,
              hrvToday: dayHRV,
              steps: dataToUse.steps,
              calories: dataToUse.calories,
              sleepFromForm: sleepFromForm,
              spo2: dataToUse.spo2,
              stress: dataToUse.stress,
              bodyTemperature: dataToUse.bodyTemperature,
              breathingRate: dataToUse.breathingRate,
              dailyQuestions: questions,
            );
            return result.healthScore;
          }
          return 0.0;
        } catch (e) {
          return 0.0;
        }

      case 'Stress':
      case 'Stress Level':
        return dayDataPoints.isNotEmpty
            ? dayDataPoints.last.stress.toDouble()
            : 0.0;

      case 'RHR':
        return (dailyBaselines[dateStr]?['rhr'] ?? 65).toDouble();

      case 'HRV':
        return (dailyBaselines[dateStr]?['hrv'] ?? 45).toDouble();

      case 'Body Temperature':
        // For body temperature: Use LATEST reading
        return dayDataPoints.last.bodyTemperature;

      case 'Breathing Rate':
        // For breathing rate: Use LATEST reading
        return dayDataPoints.last.breathingRate.toDouble();

      default:
        return dayDataPoints.isNotEmpty
            ? dayDataPoints.last.heartRate.toDouble()
            : 0.0;
    }
  }

  double _calculateSleepNeeded(DateTime date) {
    // Calculate sleep needed based on day of week
    if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
      return 8.5; // More sleep on weekends
    } else {
      return 7.5; // Standard sleep on weekdays
    }
  }

  String _getDayKey(DateTime date) {
    return '${date.year}-${date.month}-${date.day}';
  }

  String _getDayName(int weekday) {
    switch (weekday) {
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

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}';
  }

  Future<void> _generateAIInsight() async {
    if (_currentHealthData == null) return;

    setState(() {
      _isGeneratingInsight = true;
    });

    try {
      // CHANGE: Remove forceRefresh: true to use cached insights
      final insight = await _aiService.getMetricDescription(
        metricName: widget.metricName,
        currentValue: widget.currentValue,
        unit: widget.unit,
        currentData: _currentHealthData!,
        // REMOVED: forceRefresh: true,
      );

      if (mounted) {
        setState(() {
          _aiInsight = insight;
          _isGeneratingInsight = false;
        });
      }
    } catch (e) {
      print('Error generating AI insight: $e');
      if (mounted) {
        setState(() {
          _isGeneratingInsight = false;
          _aiInsight =
              'Analyzing your ${widget.metricName.toLowerCase()} patterns to provide personalized insights...';
        });
      }
    }
  }

  // Premium Day Detail Bottom Sheet
  void _showDayDetailBottomSheet(Map<String, dynamic> dayData) {
    final date = dayData['date'] as DateTime;
    final dayName = dayData['day'] as String;
    final fullDate = dayData['fullDate'] as String;
    final value = dayData['value'] as double;
    final rawDataPoints = dayData['rawDataPoints'] as List<HealthData>;
    final isToday = dayData['isToday'] as bool;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0D0D0D),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Premium Drag Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF444444),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header Section
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            widget.color.withOpacity(0.3),
                            widget.color.withOpacity(0.1),
                          ],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(widget.icon, color: widget.color, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$dayName, $fullDate',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: const Color(0xFFE8E8E8),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (isToday)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: widget.color.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Today',
                                    style: TextStyle(
                                      color: widget.color,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              Text(
                                '${rawDataPoints.length} data points recorded',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: const Color(0xFF888888)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF222222),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Color(0xFFAAAAAA),
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Main Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    // Primary Metric Card
                    _buildDayPrimaryMetricCard(value),

                    const SizedBox(height: 24),

                    // Recovery & Statistics Row
                    _buildDayStatsRow(rawDataPoints),

                    const SizedBox(height: 32),

                    // All Data Points Section
                    _buildDayDataPointsSection(rawDataPoints, date),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayPrimaryMetricCard(double value) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            widget.color.withOpacity(0.15),
            widget.color.withOpacity(0.05),
          ],
        ),
        border: Border.all(color: widget.color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(
            'Daily ${widget.metricName}',
            style: const TextStyle(
              color: Color(0xFFAAAAAA),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _getValueDisplay(value),
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w700,
                  color: widget.color,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.unit,
                style: const TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayStatsRow(List<HealthData> dataPoints) {
    if (dataPoints.isEmpty) {
      return const SizedBox();
    }

    // Calculate stats based on metric type
    double average = 0;
    double minVal = 0;
    double maxVal = 0;

    switch (widget.metricName) {
      case 'Heart Rate':
        final values = dataPoints.map((e) => e.heartRate.toDouble()).toList();
        average = values.reduce((a, b) => a + b) / values.length;
        minVal = values.reduce((a, b) => a < b ? a : b);
        maxVal = values.reduce((a, b) => a > b ? a : b);
        break;
      case 'Stress':
      case 'Stress Level':
        final values = dataPoints.map((e) => e.stress.toDouble()).toList();
        average = values.reduce((a, b) => a + b) / values.length;
        minVal = values.reduce((a, b) => a < b ? a : b);
        maxVal = values.reduce((a, b) => a > b ? a : b);
        break;
      case 'SpO₂':
        final values = dataPoints.map((e) => e.spo2.toDouble()).toList();
        average = values.reduce((a, b) => a + b) / values.length;
        minVal = values.reduce((a, b) => a < b ? a : b);
        maxVal = values.reduce((a, b) => a > b ? a : b);
        break;
      default:
        return const SizedBox();
    }

    // Get recovery from last data point if available
    final lastRecovery = dataPoints.isNotEmpty ? dataPoints.last.recovery : 0;

    return Row(
      children: [
        Expanded(
          child: _buildDayStatCard(
            'Recovery',
            '${lastRecovery.toStringAsFixed(0)}%',
            Icons.battery_charging_full_rounded,
            lastRecovery >= 70
                ? Colors.green
                : lastRecovery >= 40
                ? Colors.orange
                : Colors.red,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildDayStatCard(
            'Average',
            _getValueDisplay(average),
            Icons.analytics_outlined,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildDayStatCard(
            'Range',
            '${minVal.toInt()}-${maxVal.toInt()}',
            Icons.swap_vert_rounded,
            Colors.purple,
          ),
        ),
      ],
    );
  }

  Widget _buildDayStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF1A1A1A),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF777777),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayDataPointsSection(
    List<HealthData> dataPoints,
    DateTime date,
  ) {
    if (dataPoints.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFF1A1A1A),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Column(
          children: [
            Icon(Icons.inbox_rounded, color: const Color(0xFF555555), size: 48),
            const SizedBox(height: 16),
            const Text(
              'No data points recorded',
              style: TextStyle(
                color: Color(0xFF888888),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // Get values based on metric type
    List<double> values = [];
    switch (widget.metricName) {
      case 'Heart Rate':
        values = dataPoints.map((e) => e.heartRate.toDouble()).toList();
        break;
      case 'Stress':
      case 'Stress Level':
        values = dataPoints.map((e) => e.stress.toDouble()).toList();
        break;
      case 'SpO₂':
        values = dataPoints.map((e) => e.spo2.toDouble()).toList();
        break;
      default:
        values = dataPoints.map((e) => e.heartRate.toDouble()).toList();
    }

    // Calculate statistics
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final avgVal = values.reduce((a, b) => a + b) / values.length;

    // Calculate Y-axis range for the chart
    final range = maxVal - minVal;
    final displayRange = max(20.0, range * 1.5);
    final center = (maxVal + minVal) / 2;
    double chartMin = (center - displayRange / 2).clamp(0, double.infinity);
    double chartMax = center + displayRange / 2;

    // Round to nice numbers
    chartMin = (chartMin / 10).floor() * 10.0;
    chartMax = (chartMax / 10).ceil() * 10.0;

    // Create spots for the line chart
    final List<FlSpot> spots = values.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value);
    }).toList();

    // Calculate zones for Heart Rate
    int lowCount = 0;
    int normalCount = 0;
    int highCount = 0;

    if (widget.metricName == 'Heart Rate') {
      lowCount = values.where((v) => v < 60).length;
      normalCount = values.where((v) => v >= 60 && v <= 100).length;
      highCount = values.where((v) => v > 100).length;
    } else if (widget.metricName == 'Stress' ||
        widget.metricName == 'Stress Level') {
      lowCount = values.where((v) => v <= 33).length;
      normalCount = values.where((v) => v > 33 && v <= 66).length;
      highCount = values.where((v) => v > 66).length;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${widget.metricName} Throughout Day',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFFE8E8E8),
                fontWeight: FontWeight.w600,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: widget.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${dataPoints.length} readings',
                style: TextStyle(
                  color: widget.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Main Chart Container
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: const Color(0xFF141414),
            border: Border.all(color: const Color(0xFF252525)),
          ),
          child: Column(
            children: [
              // The Line Chart
              SizedBox(
                height: 200,
                child: LineChart(
                  LineChartData(
                    clipData: const FlClipData.all(),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      drawHorizontalLine: true,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: const Color(0xFF2A2A2A),
                        strokeWidth: 1,
                      ),
                      horizontalInterval: (chartMax - chartMin) / 4,
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          getTitlesWidget: (value, meta) {
                            // Show labels at start, middle, end
                            if (value == 0 ||
                                value == spots.length - 1 ||
                                value == (spots.length - 1) / 2) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  value == 0
                                      ? 'Start'
                                      : value == spots.length - 1
                                      ? 'End'
                                      : 'Mid',
                                  style: const TextStyle(
                                    color: Color(0xFF666666),
                                    fontSize: 10,
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
                          interval: (chartMax - chartMin) / 4,
                          getTitlesWidget: (value, meta) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Text(
                                '${value.toInt()}',
                                style: const TextStyle(
                                  color: Color(0xFF666666),
                                  fontSize: 10,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            );
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
                    borderData: FlBorderData(show: false),
                    minY: chartMin,
                    maxY: chartMax,
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        curveSmoothness: 0.2,
                        color: widget.color,
                        barWidth: 2.5,
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              widget.color.withOpacity(0.3),
                              widget.color.withOpacity(0.05),
                            ],
                          ),
                        ),
                        dotData: FlDotData(
                          show: spots.length <= 30,
                          getDotPainter: (spot, percent, barData, index) {
                            return FlDotCirclePainter(
                              radius: 2,
                              color: Colors.white,
                              strokeWidth: 1.5,
                              strokeColor: widget.color,
                            );
                          },
                        ),
                        shadow: Shadow(
                          color: widget.color.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      enabled: true,
                      touchTooltipData: LineTouchTooltipData(
                        tooltipBgColor: const Color(0xFF1A1A1A),
                        tooltipRoundedRadius: 8,
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((spot) {
                            return LineTooltipItem(
                              '${_getValueDisplay(spot.y)}',
                              TextStyle(
                                color: widget.color,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            );
                          }).toList();
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Quick Stats Row
        Row(
          children: [
            Expanded(
              child: _buildMiniStatCard(
                'Minimum',
                _getValueDisplay(minVal),
                Colors.blue,
                Icons.arrow_downward_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMiniStatCard(
                'Average',
                _getValueDisplay(avgVal),
                Colors.purple,
                Icons.analytics_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMiniStatCard(
                'Maximum',
                _getValueDisplay(maxVal),
                Colors.orange,
                Icons.arrow_upward_rounded,
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Zone Distribution
        _buildZoneDistribution(lowCount, normalCount, highCount, values.length),
      ],
    );
  }

  Widget _buildMiniStatCard(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFF1A1A1A),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF777777),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoneDistribution(int low, int normal, int high, int total) {
    if (total == 0) return const SizedBox();

    final lowPercent = (low / total * 100).round();
    final normalPercent = (normal / total * 100).round();
    final highPercent = (high / total * 100).round();

    String lowLabel, normalLabel, highLabel;
    Color lowColor, normalColor, highColor;

    if (widget.metricName == 'Heart Rate') {
      lowLabel = 'Resting (<60)';
      normalLabel = 'Normal (60-100)';
      highLabel = 'Elevated (>100)';
      lowColor = Colors.blue;
      normalColor = Colors.green;
      highColor = Colors.red;
    } else {
      lowLabel = 'Low (0-33%)';
      normalLabel = 'Medium (34-66%)';
      highLabel = 'High (67-100%)';
      lowColor = Colors.green;
      normalColor = Colors.orange;
      highColor = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF1A1A1A),
        border: Border.all(color: const Color(0xFF252525)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Zone Distribution',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: const Color(0xFFE8E8E8),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  if (lowPercent > 0)
                    Flexible(
                      flex: lowPercent,
                      child: Container(color: lowColor),
                    ),
                  if (normalPercent > 0)
                    Flexible(
                      flex: normalPercent,
                      child: Container(color: normalColor),
                    ),
                  if (highPercent > 0)
                    Flexible(
                      flex: highPercent,
                      child: Container(color: highColor),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildZoneLegendItem(lowColor, lowLabel, '$lowPercent%'),
              _buildZoneLegendItem(normalColor, normalLabel, '$normalPercent%'),
              _buildZoneLegendItem(highColor, highLabel, '$highPercent%'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildZoneLegendItem(Color color, String label, String value) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF666666), fontSize: 9),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // Enhanced Bar Chart
  Widget _buildBarChart(BuildContext context) {
    if (_isLoading || _weeklyBarData.isEmpty) {
      return _buildChartPlaceholder();
    }

    final values = _weeklyBarData.map((e) => e['value'] as double).toList();
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final minValue = values.reduce((a, b) => a < b ? a : b);

    final double range = (maxValue - minValue) * 1.2;
    final double interval = _calculateNiceInterval(range);
    final double chartMax =
        ((maxValue / interval).ceil() * interval) + interval;
    final double chartMin = max(
      0,
      ((minValue / interval).floor() * interval) - interval,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _buildCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Weekly ${widget.metricName} Trend',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '7 Days',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 250,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceBetween,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchCallback: (FlTouchEvent event, barTouchResponse) {
                    // Only open detail sheet for Heart Rate, Stress, and SpO2
                    final supportedMetrics = [
                      'Heart Rate',
                      'Stress',
                      'Stress Level',
                      'SpO₂',
                    ];
                    if (supportedMetrics.contains(widget.metricName) &&
                        event is FlTapUpEvent &&
                        barTouchResponse?.spot != null) {
                      final groupIndex =
                          barTouchResponse!.spot!.touchedBarGroupIndex;
                      if (groupIndex >= 0 &&
                          groupIndex < _weeklyBarData.length) {
                        _showDayDetailBottomSheet(_weeklyBarData[groupIndex]);
                      }
                    }
                  },
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: const Color(0xFF1A1A1A),
                    tooltipRoundedRadius: 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final data = _weeklyBarData[groupIndex];
                      final rawDataPoints =
                          data['rawDataPoints'] as List<HealthData>;
                      final dataPointCount = rawDataPoints.length;

                      // Only show "Tap for details" for supported metrics
                      final supportedMetrics = [
                        'Heart Rate',
                        'Stress',
                        'Stress Level',
                        'SpO₂',
                      ];
                      final tapText =
                          supportedMetrics.contains(widget.metricName)
                          ? 'Tap for details • $dataPointCount readings'
                          : 'Based on $dataPointCount readings';

                      return BarTooltipItem(
                        '${data['day']} (${data['fullDate']})\n'
                        '${_getValueDisplay(rod.toY)}\n'
                        '$tapText',
                        const TextStyle(
                          color: Color(0xFFE8E8E8),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index >= 0 && index < _weeklyBarData.length) {
                          final data = _weeklyBarData[index];
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Text(
                                  data['day'],
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: data['isToday']
                                        ? widget.color
                                        : const Color(0xFFA0A0A0),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  data['fullDate'],
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF666666),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return const SizedBox();
                      },
                      reservedSize: 42,
                      interval: 1,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if ((value - chartMin) % interval < 0.1 ||
                            value == chartMin ||
                            value == chartMax) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Text(
                              _getValueDisplay(value),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFA0A0A0),
                              ),
                              textAlign: TextAlign.right,
                            ),
                          );
                        }
                        return const SizedBox();
                      },
                      reservedSize: 50,
                      interval: interval,
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  drawHorizontalLine: true,
                  getDrawingHorizontalLine: (value) {
                    return const FlLine(
                      color: Color(0xFF333333),
                      strokeWidth: 1,
                    );
                  },
                  checkToShowHorizontalLine: (value) {
                    return (value - chartMin) % interval < 0.1;
                  },
                ),
                borderData: FlBorderData(show: false),
                barGroups: _weeklyBarData.asMap().entries.map((entry) {
                  final index = entry.key;
                  final data = entry.value;
                  final isToday = data['isToday'];

                  return BarChartGroupData(
                    x: index,
                    groupVertically: true,
                    barRods: [
                      BarChartRodData(
                        toY: data['value'] as double,
                        width: 20,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(6),
                          topRight: Radius.circular(6),
                        ),
                        color: isToday
                            ? widget.color
                            : widget.color.withOpacity(0.7),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: chartMax,
                          color: const Color(0xFF333333).withOpacity(0.1),
                        ),
                      ),
                    ],
                  );
                }).toList(),
                minY: chartMin,
                maxY: chartMax,
                groupsSpace: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Line Chart
  Widget _buildLineChart(BuildContext context) {
    if (_isLoading || _weeklyLineData.isEmpty) {
      return _buildChartPlaceholder();
    }

    final sleepTakenValues = _weeklyLineData
        .map((e) => e['value'] as double)
        .toList();
    final sleepNeededValues = _weeklyLineData
        .map((e) => e['sleepNeeded'] as double)
        .toList();

    final allValues = [...sleepTakenValues, ...sleepNeededValues];

    final (minY, maxY) = _calculateLineChartYRange(allValues);
    final yAxisInterval = _calculateLineChartInterval(maxY - minY);

    final sleepTakenSpots = _weeklyLineData.asMap().entries.map((entry) {
      final index = entry.key;
      final data = entry.value;
      final value = data['value'] as double;
      return FlSpot(index.toDouble(), value.clamp(minY, maxY));
    }).toList();

    final sleepNeededSpots = _weeklyLineData.asMap().entries.map((entry) {
      final index = entry.key;
      final data = entry.value;
      final sleepNeeded = data['sleepNeeded'] as double;
      return FlSpot(index.toDouble(), sleepNeeded.clamp(minY, maxY));
    }).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _buildCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.metricName == 'Sleep'
                    ? 'Sleep Analysis: Taken vs Needed'
                    : '7-Day Trend Analysis',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                  color: widget.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.color.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  'Weekly View',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: widget.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 250,
            child: LineChart(
              LineChartData(
                clipData: const FlClipData.all(),
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchCallback: (FlTouchEvent event, lineTouchResponse) {
                    // Only open detail sheet for Heart Rate, Stress, and SpO2
                    final supportedMetrics = [
                      'Heart Rate',
                      'Stress',
                      'Stress Level',
                      'SpO₂',
                    ];
                    if (supportedMetrics.contains(widget.metricName) &&
                        event is FlTapUpEvent &&
                        lineTouchResponse?.lineBarSpots != null &&
                        lineTouchResponse!.lineBarSpots!.isNotEmpty) {
                      final spotIndex =
                          lineTouchResponse.lineBarSpots!.first.spotIndex;
                      if (spotIndex >= 0 &&
                          spotIndex < _weeklyLineData.length) {
                        _showDayDetailBottomSheet(_weeklyLineData[spotIndex]);
                      }
                    }
                  },
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: const Color(0xFF1A1A1A),
                    tooltipRoundedRadius: 8,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final data = _weeklyLineData[spot.spotIndex];
                        final rawDataPoints =
                            data['rawDataPoints'] as List<HealthData>;

                        // Only show "Tap for details" for supported metrics
                        final supportedMetrics = [
                          'Heart Rate',
                          'Stress',
                          'Stress Level',
                          'SpO₂',
                        ];
                        final tapText =
                            supportedMetrics.contains(widget.metricName)
                            ? 'Tap for details • ${rawDataPoints.length} readings'
                            : 'Based on ${rawDataPoints.length} readings';

                        return LineTooltipItem(
                          '${data['day']} (${data['fullDate']})\n${_getValueDisplay(spot.y)}\n$tapText',
                          const TextStyle(
                            color: Color(0xFFE8E8E8),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  drawHorizontalLine: true,
                  getDrawingHorizontalLine: (value) {
                    return const FlLine(
                      color: Color(0xFF333333),
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
                        if (value >= 0 && value < _weeklyLineData.length) {
                          final data = _weeklyLineData[value.toInt()];
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              data['day'],
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
                              _getValueDisplay(value),
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
                    spots: sleepTakenSpots,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: widget.color,
                    barWidth: 3,
                    belowBarData: BarAreaData(
                      show: widget.metricName == 'Sleep',
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          widget.color.withOpacity(0.3),
                          widget.color.withOpacity(0.05),
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
                          strokeColor: widget.color,
                        );
                      },
                    ),
                  ),
                  if (widget.metricName == 'Sleep')
                    LineChartBarData(
                      spots: sleepNeededSpots,
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: Colors.orange,
                      barWidth: 2,
                      dashArray: [4, 4],
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 2,
                            color: Colors.orange,
                            strokeWidth: 1,
                            strokeColor: Colors.orange,
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (widget.metricName == 'Sleep')
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem(widget.color, 'Sleep Taken'),
                const SizedBox(width: 20),
                _buildLegendItem(Colors.orange, 'Sleep Needed'),
              ],
            )
          else
            Center(
              child: Text(
                _getYAxisTitle(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFA0A0A0),
                ),
              ),
            ),
        ],
      ),
    );
  }

  (double, double) _calculateLineChartYRange(List<double> values) {
    if (values.isEmpty) return (0, 100);

    final minVal = values.reduce(min);
    final maxVal = values.reduce(max);

    final range = maxVal - minVal;
    final padding = range * 0.15;

    double niceMin, niceMax;

    switch (widget.metricName.toLowerCase()) {
      case 'heart rate':
        niceMin = (minVal - padding).clamp(40, double.infinity);
        niceMax = (maxVal + padding).clamp(niceMin + 10, 200);
        break;
      case 'sleep':
        niceMin = 0;
        niceMax = 16;
        break;
      case 'steps':
        niceMin = 0;
        niceMax = ((maxVal + padding) / 1000).ceil() * 1000;
        break;
      case 'calories':
        niceMin = 0;
        niceMax = ((maxVal + padding) / 100).ceil() * 100;
        break;
      case 'spo2':
      case 'spo₂':
      case 'oxygen':
        niceMin = 85;
        niceMax = 100;
        break;
      case 'recovery':
      case 'stress':
      case 'stress level':
        niceMin = 0;
        niceMax = 100;
        break;
      case 'resting heart rate':
      case 'rhr':
        niceMin = 40;
        niceMax = 90;
        break;
      case 'hrv':
        niceMin = 0;
        niceMax = 100;
        break;
      case 'body temperature':
        niceMin = 35;
        niceMax = 39;
        break;
      case 'breathing rate':
        niceMin = 8;
        niceMax = 25;
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

  double _calculateLineChartInterval(double range) {
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

    switch (widget.metricName) {
      case 'Heart Rate':
        interval = interval.clamp(5, 20);
        break;
      case 'Steps':
        if (range > 5000) {
          interval = 1000;
        } else if (range > 1000) {
          interval = 500;
        } else {
          interval = 200;
        }
        break;
      case 'Sleep':
        interval = 2;
        break;
      case 'Calories':
        if (range > 1000) {
          interval = 200;
        } else {
          interval = 100;
        }
        break;
      case 'SpO₂':
        interval = 2;
        break;
      case 'Recovery':
      case 'Stress':
      case 'Stress Level':
        interval = 10;
        break;
      default:
        interval = interval.clamp(1, 20);
    }

    return interval;
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(color: Color(0xFFA0A0A0), fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildChartPlaceholder() {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(20),
      decoration: _buildCardDecoration(),
      child: Center(
        child: _isLoading
            ? CircularProgressIndicator(color: widget.color)
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bar_chart_rounded,
                    color: const Color(0xFFA0A0A0),
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No data available',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFA0A0A0),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // Current Value Card - Shows LATEST data from BLE
  Widget _buildCurrentValueCard() {
    // Use the current value passed from dashboard (which is latest from BLE)
    final displayValue = widget.currentValue;

    // Calculate trend indicator
    final trend = _calculateTrend();
    final trendIcon = trend > 0
        ? Icons.trending_up_rounded
        : trend < 0
        ? Icons.trending_down_rounded
        : Icons.trending_flat_rounded;
    final trendColor = trend > 0
        ? Colors.green
        : trend < 0
        ? Colors.red
        : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _buildCardDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.color.withOpacity(0.3),
                      widget.color.withOpacity(0.1),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, color: widget.color, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.metricName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFFE8E8E8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Latest Reading • ${_getTimeOfDay()}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFA0A0A0),
                      ),
                    ),
                  ],
                ),
              ),
              // In _buildCurrentValueCard(), update the trend container:
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: trendColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: trendColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(trendIcon, color: trendColor, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${trend.abs().toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: trendColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                displayValue,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontSize: 48,
                  fontWeight: FontWeight.w700,
                  color: widget.color,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.unit,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFFA0A0A0),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildAdditionalInfo(),
        ],
      ),
    );
  }

  Widget _buildAdditionalInfo() {
    if (_weeklyBarData.length < 2) return const SizedBox();

    final todayData = _weeklyBarData.last;
    final rawDataPoints = todayData['rawDataPoints'] as List<HealthData>;
    final dataPointCount = rawDataPoints.length;

    return Column(
      children: [
        Text(
          'Based on $dataPointCount readings today',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xFFA0A0A0),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        if (_weeklyBarData.length >= 2)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _calculateTrend() >= 0
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                color: _calculateTrend() >= 0 ? Colors.green : Colors.red,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                '${_calculateTrend().abs().toStringAsFixed(1)}% from last week',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFA0A0A0),
                  fontSize: 12,
                ),
              ),
            ],
          ),
      ],
    );
  }

  double _calculateTrend() {
    if (_weeklyBarData.length < 2) return 0.0;
    return HealthCalculationsService.calculateTrendFromWeeklyData(
      _weeklyBarData,
    );
  }

  String _getTimeOfDay() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Morning';
    if (hour < 17) return 'Afternoon';
    if (hour < 21) return 'Evening';
    return 'Night';
  }

  // AI Insights Card
  Widget _buildAIInsightsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _buildCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.purple,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'AI Health Insights',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFE8E8E8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!_isGeneratingInsight)
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF333333),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.refresh_rounded,
                      color: Color(0xFF808080),
                      size: 16,
                    ),
                  ),
                  onPressed: _generateAIInsight,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _isGeneratingInsight
              ? _buildLoadingInsight()
              : _buildInsightContent(),
        ],
      ),
    );
  }

  Widget _buildLoadingInsight() {
    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(widget.color),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Analyzing your health data...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF808080),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(widget.color),
          backgroundColor: const Color(0xFF333333),
        ),
      ],
    );
  }

  Widget _buildInsightContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF333333)),
          ),
          child: Text(
            _aiInsight,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFE8E8E8),
              height: 1.6,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildRecommendationTips(),
      ],
    );
  }

  Widget _buildRecommendationTips() {
    if (_currentHealthData == null) return const SizedBox();

    List<Widget> tips = [];

    switch (widget.metricName) {
      case 'Sleep':
        final sleepHours = _currentHealthData!.sleep;
        if (sleepHours < 7) {
          tips.add(
            _buildTipItem(
              '💤',
              'Aim for 7-9 hours of sleep for optimal recovery',
            ),
          );
          tips.add(_buildTipItem('🌙', 'Maintain consistent sleep schedule'));
        }
        if (sleepHours > 9) {
          tips.add(
            _buildTipItem('⏰', 'Consider reducing sleep duration to 7-9 hours'),
          );
        }
        break;
      case 'Heart Rate':
        final hr = _currentHealthData!.heartRate;
        if (hr > 80) {
          tips.add(_buildTipItem('🧘', 'Practice deep breathing exercises'));
          tips.add(_buildTipItem('💧', 'Stay hydrated throughout the day'));
        }
        break;
      case 'Steps':
        final steps = _currentHealthData!.steps;
        if (steps < 8000) {
          tips.add(_buildTipItem('🚶', 'Take short walking breaks every hour'));
          tips.add(_buildTipItem('🏃', 'Aim for 10,000 steps daily'));
        }
        break;
      case 'Recovery':
        final recovery = _currentHealthData!.recovery;
        if (recovery < 70) {
          tips.add(
            _buildTipItem('🛌', 'Get adequate sleep for better recovery'),
          );
          tips.add(_buildTipItem('💧', 'Stay hydrated and maintain nutrition'));
        }
        break;
    }

    if (tips.isEmpty) {
      tips.add(_buildTipItem('✅', 'Keep maintaining your healthy habits!'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Tips',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: const Color(0xFFE8E8E8),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: tips),
      ],
    );
  }

  Widget _buildTipItem(String emoji, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(color: Color(0xFFA0A0A0), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // Statistics Section
  Widget _buildStatisticsSection() {
    if (_isLoading || _weeklyBarData.isEmpty) return const SizedBox();

    final values = _weeklyBarData.map((e) => e['value'] as double).toList();
    final average = values.reduce((a, b) => a + b) / values.length;
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final consistency = _calculateConsistency(values);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _buildCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weekly Performance Analytics',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFFE8E8E8),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.4,
            children: [
              _buildStatCard(
                'Latest',
                widget.currentValue,
                'Current reading',
                Icons.fiber_manual_record_rounded,
                widget.color,
              ),
              _buildStatCard(
                'Weekly Avg',
                _getValueDisplay(average),
                '7-day average',
                Icons.timeline_rounded,
                Colors.blue,
              ),
              _buildStatCard(
                'Weekly High',
                _getValueDisplay(maxVal),
                'Best performance',
                Icons.arrow_upward_rounded,
                Colors.green,
              ),
              _buildStatCard(
                'Weekly Low',
                _getValueDisplay(minVal),
                'Room for improvement',
                Icons.arrow_downward_rounded,
                Colors.orange,
              ),
              _buildStatCard(
                'Consistency',
                '${consistency.toStringAsFixed(0)}%',
                'Weekly stability',
                Icons.auto_graph_rounded,
                Colors.purple,
              ),
              _buildStatCard(
                'Trend',
                _calculateTrend() >= 0 ? 'Improving' : 'Declining',
                'Weekly direction',
                Icons.trending_up_rounded,
                _calculateTrend() >= 0 ? Colors.green : Colors.red,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
        ),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFA0A0A0),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF666666), fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _calculateConsistency(List<double> values) {
    if (values.length < 2) return 100.0;

    final average = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => pow(v - average, 2)).reduce((a, b) => a + b) /
        values.length;
    final stdDev = sqrt(variance);

    final maxExpectedVariance = average * 0.5;
    final consistency =
        (1 - (stdDev / maxExpectedVariance)).clamp(0.0, 1.0) * 100;

    return consistency;
  }

  // Chart Type Selector
  Widget _buildChartSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildChartTypeButton('Bar', Icons.bar_chart_rounded, 0),
          const SizedBox(width: 4),
          _buildChartTypeButton('Line', Icons.show_chart_rounded, 1),
        ],
      ),
    );
  }

  Widget _buildChartTypeButton(String text, IconData icon, int index) {
    final isSelected = _selectedChartType == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedChartType = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? widget.color : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : const Color(0xFFA0A0A0),
            ),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFFA0A0A0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Utility methods
  String _getValueDisplay(double value) {
    switch (widget.metricName) {
      case 'Steps':
        return value >= 1000
            ? '${(value / 1000).toStringAsFixed(1)}k'
            : value.toInt().toString();
      case 'Calories':
        return value.toInt().toString();
      case 'Sleep':
        final hours = value.floor();
        final minutes = ((value - hours) * 60).round();
        return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
      case 'SpO₂':
        return '${value.toStringAsFixed(1)}%';
      case 'Recovery':
      case 'Stress':
      case 'Stress Level':
        return '${value.toInt()}%';
      case 'Body Temperature':
        return '${value.toStringAsFixed(1)}°C';
      default:
        return value.toInt().toString();
    }
  }

  String _getYAxisTitle() {
    switch (widget.metricName.toLowerCase()) {
      case 'heart rate':
      case 'resting heart rate':
      case 'rhr':
      case 'breathing rate':
        return 'BPM';
      case 'sleep':
        return 'Hours';
      case 'steps':
        return 'Steps';
      case 'calories':
        return 'Calories';
      case 'spo2':
      case 'spo₂':
      case 'oxygen':
        return '%';
      case 'recovery':
      case 'stress':
      case 'stress level':
        return '%';
      case 'hrv':
        return 'ms';
      case 'body temperature':
        return '°C';
      default:
        return widget.unit;
    }
  }

  double _calculateNiceInterval(double range) {
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

    final double interval = niceFraction * pow(10, exponent).toDouble();

    switch (widget.metricName) {
      case 'Heart Rate':
        return interval / 4;
      case 'Steps':
        return interval / 2;
      case 'Sleep':
        return interval / 3;
      case 'SpO₂':
        return interval / 5;
      case 'Recovery':
        return interval / 4;
      default:
        return interval / 4;
    }
  }

  BoxDecoration _buildCardDecoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF1A1A1A).withOpacity(0.8),
          const Color(0xFF0D0D0D).withOpacity(0.9),
        ],
      ),
      border: Border.all(color: const Color(0xFF333333)),
    );
  }

  // Placeholder for Sleep Quality Gauge
  Widget _buildSleepQualityGauge() {
    // Implement your sleep quality gauge here
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _buildCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sleep Quality Score',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFFE8E8E8),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '85/100', // Example score
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Excellent Sleep Quality',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFFA0A0A0)),
            ),
          ),
        ],
      ),
    );
  }

  // Add this method to build enhanced sleep analysis
  Widget _buildEnhancedSleepAnalysis() {
    if (widget.metricName != 'Sleep') return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _buildCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sleep Quality Analysis',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                  'AI Analyzed',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.purple,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Sleep Stages Simulation (based on real HRV data)
          _buildSleepStages(),
          const SizedBox(height: 20),

          // Sleep Debt Calculator
          _buildSleepDebtCalculator(),
          const SizedBox(height: 20),

          // Sleep Efficiency
          _buildSleepEfficiency(),
          const SizedBox(height: 20),

          // Sleep Regularity Score
          _buildSleepRegularity(),
        ],
      ),
    );
  }

  Widget _buildSleepStages() {
    // Simulate sleep stages based on real HRV data
    final sleepHours = double.tryParse(widget.currentValue) ?? 7.0;
    final hrvData = _weeklyLineData.map((e) => e['value'] as double).toList();

    // Calculate simulated stages based on HRV patterns
    double deepSleep = 0;
    double lightSleep = 0;
    double remSleep = 0;

    if (hrvData.isNotEmpty) {
      final avgHRV = hrvData.reduce((a, b) => a + b) / hrvData.length;
      deepSleep =
          sleepHours * 0.25 * (avgHRV / 50); // More HRV = more deep sleep
      remSleep = sleepHours * 0.23 * (1 + (avgHRV - 50) / 100);
      lightSleep = sleepHours - deepSleep - remSleep;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sleep Stages (HRV-Based)',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: const Color(0xFFE8E8E8),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildStageIndicator(
              'Deep',
              deepSleep,
              Colors.blue,
              Icons.nightlight_round,
            ),
            const SizedBox(width: 12),
            _buildStageIndicator(
              'Light',
              lightSleep,
              Colors.green,
              Icons.brightness_3,
            ),
            const SizedBox(width: 12),
            _buildStageIndicator(
              'REM',
              remSleep,
              Colors.purple,
              Icons.psychology,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStageIndicator(
    String stage,
    double hours,
    Color color,
    IconData icon,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
          ),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              '${hours.toStringAsFixed(1)}h',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            Text(
              stage,
              style: TextStyle(color: color.withOpacity(0.8), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSleepDebtCalculator() {
    // Calculate sleep debt over 14 days
    final sleepDebt = _calculateSleepDebt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sleep Debt Analysis',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: const Color(0xFFE8E8E8),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        if (sleepDebt > 0) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [
                  Colors.red.withOpacity(0.1),
                  Colors.red.withOpacity(0.05),
                ],
              ),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_rounded, color: Colors.red, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sleep Debt: ${sleepDebt.toStringAsFixed(1)} hours',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'You need ${(sleepDebt * 0.5).toStringAsFixed(1)} extra hours tonight',
                        style: TextStyle(
                          color: Colors.red.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [
                  Colors.green.withOpacity(0.1),
                  Colors.green.withOpacity(0.05),
                ],
              ),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.green,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'No Sleep Debt!',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Keep maintaining your sleep schedule',
                        style: TextStyle(
                          color: Colors.green.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  double _calculateSleepDebt() {
    // Calculate based on last 14 days of sleep data
    if (_weeklyLineData.isEmpty) return 0;

    double totalDebt = 0;
    final optimalSleep = 8.0; // Assume 8 hours optimal

    for (var day in _weeklyLineData) {
      final actualSleep = day['value'] as double;
      if (actualSleep < optimalSleep) {
        totalDebt += (optimalSleep - actualSleep);
      }
    }

    // Project to 14 days
    return totalDebt * (14 / _weeklyLineData.length);
  }

  Widget _buildSleepEfficiency() {
    // Calculate sleep efficiency based on time in bed vs actual sleep
    final efficiency = _calculateSleepEfficiency();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sleep Efficiency',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: const Color(0xFFE8E8E8),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 60,
                        height: 60,
                        child: CircularProgressIndicator(
                          value: efficiency / 100,
                          strokeWidth: 6,
                          backgroundColor: const Color(0xFF1A1A1A),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            efficiency >= 85 ? Colors.green : Colors.orange,
                          ),
                        ),
                      ),
                      Text(
                        '${efficiency.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    efficiency >= 85 ? 'Excellent' : 'Good',
                    style: TextStyle(
                      color: efficiency >= 85 ? Colors.green : Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildEfficiencyItem('Sleep Onset', '15 min', Colors.blue),
                  const SizedBox(height: 8),
                  _buildEfficiencyItem(
                    'Wake Episodes',
                    '2 times',
                    Colors.orange,
                  ),
                  const SizedBox(height: 8),
                  _buildEfficiencyItem(
                    'Total Sleep',
                    '${widget.currentValue}h',
                    Colors.green,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  double _calculateSleepEfficiency() {
    // Based on HRV patterns and sleep duration
    final sleepHours = double.tryParse(widget.currentValue) ?? 7.0;
    final hrvData = _weeklyLineData.map((e) => e['value'] as double).toList();

    if (hrvData.isEmpty) return 75; // Default

    final avgHRV = hrvData.reduce((a, b) => a + b) / hrvData.length;

    double efficiency = 70; // Base

    // HRV impact on efficiency
    if (avgHRV > 55)
      efficiency += 15;
    else if (avgHRV > 45)
      efficiency += 10;
    else if (avgHRV > 35)
      efficiency += 5;

    // Sleep duration impact
    if (sleepHours >= 7.5 && sleepHours <= 9)
      efficiency += 10;
    else if (sleepHours >= 7)
      efficiency += 5;

    return efficiency.clamp(60, 95);
  }

  Widget _buildEfficiencyItem(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildSleepRegularity() {
    final regularityScore = _calculateSleepRegularity();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sleep Regularity',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: const Color(0xFFE8E8E8),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: regularityScore / 100,
                backgroundColor: const Color(0xFF1A1A1A),
                valueColor: AlwaysStoppedAnimation<Color>(
                  regularityScore >= 80
                      ? Colors.green
                      : regularityScore >= 60
                      ? Colors.orange
                      : Colors.red,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${regularityScore.toStringAsFixed(0)}%',
              style: TextStyle(
                color: regularityScore >= 80
                    ? Colors.green
                    : regularityScore >= 60
                    ? Colors.orange
                    : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _getRegularityText(regularityScore),
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
        ),
      ],
    );
  }

  double _calculateSleepRegularity() {
    // Calculate consistency of sleep schedule
    if (_weeklyLineData.length < 3) return 50; // Need more data

    final sleepTimes = <double>[];
    final wakeTimes = <double>[];

    // Extract sleep patterns from data
    for (var day in _weeklyLineData) {
      final sleepHours = day['value'] as double;
      sleepTimes.add(sleepHours);
      // Assume wake time based on sleep duration (simplified)
      wakeTimes.add(7.0); // Default wake time
    }

    double variance = 0;
    final avgSleep = sleepTimes.reduce((a, b) => a + b) / sleepTimes.length;

    for (var sleep in sleepTimes) {
      variance += pow(sleep - avgSleep, 2);
    }

    variance = variance / sleepTimes.length;
    double stdDev = sqrt(variance);

    // Convert to score (lower variance = higher score)
    double score = 100 - (stdDev * 20);
    return score.clamp(0, 100);
  }

  String _getRegularityText(double score) {
    if (score >= 80) return 'Excellent consistency! Keep it up.';
    if (score >= 60)
      return 'Good regularity. Try to maintain consistent bedtimes.';
    if (score >= 40)
      return 'Fair consistency. Work on a regular sleep schedule.';
    return 'Poor regularity. Establish a consistent bedtime routine.';
  }

  Widget _buildAllTimeSharpChart() {
    return FutureBuilder<List<HealthDataPoint>>(
      future: widget.bleService.getAllHealthData(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) {
          return _buildEmptyChart('Heart Rate History');
        }

        final allData = snap.data!;

        // Filter for TODAY'S data only (Resets every day in the morning/midnight)
        final now = DateTime.now();
        final todayData = allData.where((d) {
          return d.timestamp.year == now.year &&
              d.timestamp.month == now.month &&
              d.timestamp.day == now.day;
        }).toList();

        // Use newest points for today to keep it performant
        final newestData = todayData.length > 300
            ? todayData.sublist(0, 300)
            : todayData;

        // Reverse them so they are in chronological order for the chart (past to present)
        final displayData = newestData.reversed.toList();

        final List<FlSpot> spots = displayData.asMap().entries.map((entry) {
          return FlSpot(entry.key.toDouble(), entry.value.heartRate.toDouble());
        }).toList();

        // Calculate Y-axis range based on the data being displayed
        final (minY, maxY) = _calculateHeartRateYRange(displayData);
        final yInterval = 20.0;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: _buildCardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Today\'s Heart Rate',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Text(
                      '${displayData.length} samples',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 250,
                child: LineChart(
                  LineChartData(
                    clipData: const FlClipData.all(),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      drawHorizontalLine: true,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: const Color(0xFF1A1A1A),
                        strokeWidth: 1,
                      ),
                      checkToShowHorizontalLine: (value) {
                        return (value - minY) % yInterval < 0.1;
                      },
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          getTitlesWidget: (value, meta) {
                            // Show time labels for first, middle, last points
                            if (value == 0 ||
                                value == spots.length - 1 ||
                                value == (spots.length - 1) / 2) {
                              final index = value.toInt();
                              if (index >= 0 && index < displayData.length) {
                                final timestamp = displayData[index].timestamp;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    _formatTime(timestamp),
                                    style: const TextStyle(
                                      color: Color(0xFFA0A0A0),
                                      fontSize: 10,
                                    ),
                                  ),
                                );
                              }
                            }
                            return const SizedBox();
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          interval: yInterval,
                          getTitlesWidget: (value, meta) {
                            if ((value - minY) % yInterval < 0.1) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: Text(
                                  '${value.toInt()}',
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
                      border: Border.all(
                        color: const Color(0xFF333333),
                        width: 1,
                      ),
                    ),
                    minY: minY,
                    maxY: maxY,
                    extraLinesData: ExtraLinesData(
                      horizontalLines: [
                        HorizontalLine(
                          y:
                              minY +
                              (maxY - minY) * 0.25, // mid of bottom and mid
                          color: const Color(0xFF333333).withOpacity(0.5),
                          strokeWidth: 1,
                          dashArray: [4, 4],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            style: const TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 8,
                            ),
                            labelResolver: (_) => 'Lower',
                          ),
                        ),
                        HorizontalLine(
                          y: minY + (maxY - minY) * 0.50, // mid
                          color: const Color(0xFF333333),
                          strokeWidth: 1.5,
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            style: const TextStyle(
                              color: Color(0xFF808080),
                              fontSize: 8,
                            ),
                            labelResolver: (_) => 'Mid',
                          ),
                        ),
                        HorizontalLine(
                          y: minY + (maxY - minY) * 0.75, // mid of mid and top
                          color: const Color(0xFF333333).withOpacity(0.5),
                          strokeWidth: 1,
                          dashArray: [4, 4],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            style: const TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 8,
                            ),
                            labelResolver: (_) => 'Upper',
                          ),
                        ),
                      ],
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        curveSmoothness: 0.2,
                        color: Colors.red,
                        barWidth: 2,
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
                          show: false, // Clean look without dots
                        ),
                        shadow: Shadow(
                          color: Colors.red.withOpacity(0.5),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildHeartRateStats(todayData),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAllTimeStressChart() {
    return FutureBuilder<List<HealthDataPoint>>(
      future: widget.bleService.getAllHealthData(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) {
          return _buildEmptyChart('Stress History');
        }

        final allData = snap.data!;

        // Filter for TODAY'S data only
        final now = DateTime.now();
        final todayData = allData.where((d) {
          return d.timestamp.year == now.year &&
              d.timestamp.month == now.month &&
              d.timestamp.day == now.day;
        }).toList();

        final newestData = todayData.length > 200
            ? todayData.sublist(0, 200)
            : todayData;
        final displayData = newestData.reversed.toList();

        final List<FlSpot> spots = displayData.asMap().entries.map((entry) {
          return FlSpot(entry.key.toDouble(), entry.value.stress.toDouble());
        }).toList();

        final (minY, maxY) = _calculateStressYRange(displayData);
        final yInterval = 25.0; // Fixed interval for stress (0-100 scale)

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: _buildCardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Today\'s Stress Levels',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Text(
                      '${displayData.length} samples',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 250,
                child: LineChart(
                  LineChartData(
                    clipData: const FlClipData.all(),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      drawHorizontalLine: true,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: const Color(0xFF1A1A1A),
                        strokeWidth: 1,
                      ),
                      checkToShowHorizontalLine: (value) {
                        return value % yInterval < 0.1;
                      },
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          getTitlesWidget: (value, meta) {
                            if (value == 0 ||
                                value == spots.length - 1 ||
                                value == (spots.length - 1) / 2) {
                              final index = value.toInt();
                              if (index >= 0 && index < displayData.length) {
                                final timestamp = displayData[index].timestamp;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    _formatTime(timestamp),
                                    style: const TextStyle(
                                      color: Color(0xFFA0A0A0),
                                      fontSize: 10,
                                    ),
                                  ),
                                );
                              }
                            }
                            return const SizedBox();
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          interval: yInterval,
                          getTitlesWidget: (value, meta) {
                            if (value % yInterval < 0.1) {
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
                      border: Border.all(
                        color: const Color(0xFF333333),
                        width: 1,
                      ),
                    ),
                    minY: minY,
                    maxY: maxY,
                    extraLinesData: ExtraLinesData(
                      horizontalLines: [
                        HorizontalLine(
                          y: minY + (maxY - minY) * 0.25,
                          color: const Color(0xFF333333).withOpacity(0.5),
                          strokeWidth: 1,
                          dashArray: [4, 4],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            style: const TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 8,
                            ),
                            labelResolver: (_) => 'Low',
                          ),
                        ),
                        HorizontalLine(
                          y: minY + (maxY - minY) * 0.50,
                          color: const Color(0xFF333333),
                          strokeWidth: 1.5,
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            style: const TextStyle(
                              color: Color(0xFF808080),
                              fontSize: 8,
                            ),
                            labelResolver: (_) => 'Med',
                          ),
                        ),
                        HorizontalLine(
                          y: minY + (maxY - minY) * 0.75,
                          color: const Color(0xFF333333).withOpacity(0.5),
                          strokeWidth: 1,
                          dashArray: [4, 4],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            style: const TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 8,
                            ),
                            labelResolver: (_) => 'High',
                          ),
                        ),
                      ],
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        curveSmoothness: 0.2,
                        color: Colors.orange,
                        barWidth: 2,
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.orange.withOpacity(0.3),
                              Colors.orange.withOpacity(0.05),
                            ],
                          ),
                        ),
                        dotData: const FlDotData(show: false),
                        shadow: Shadow(
                          color: Colors.orange.withOpacity(0.5),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildStressStats(todayData),
            ],
          ),
        );
      },
    );
  }

  (double, double) _calculateHeartRateYRange(List<HealthDataPoint> data) {
    if (data.isEmpty) return (40, 120);

    final values = data.map((e) => e.heartRate.toDouble()).toList();
    final minVal = values.reduce(min);
    final maxVal = values.reduce(max);

    // Increase range to "unzoom" the graph and make data look less exaggerated
    final range = maxVal - minVal;

    // Ensure the range is at least 60 BPM wide to minimize visible fluctuations
    // and provide enough padding so the line isn't at the very bottom
    final displayRange = max(60.0, range * 2.0);
    final center = (maxVal + minVal) / 2;

    double niceMin = (center - displayRange / 2).clamp(40, double.infinity);
    double niceMax = (center + displayRange / 2).clamp(niceMin + 60, 220);

    // Round to nice numbers (multiples of 20) for cleaner labeling
    niceMin = (niceMin / 20).floor() * 20;
    niceMax = (niceMax / 20).ceil() * 20;

    return (niceMin, niceMax);
  }

  (double, double) _calculateStressYRange(List<HealthDataPoint> data) {
    if (data.isEmpty) return (0, 100);

    final values = data.map((e) => e.stress.toDouble()).toList();
    final minVal = values.reduce(min);

    // Increase range to "unzoom" the graph
    // For stress, we usually want 0-100, but if the data is very stable
    // around 20%, showing 0-100 keeps it "unzoomed".
    // However, if the data is all at 90-100, we might want to see some context.

    // Default to a wide fixed range for consistency and "unzoomed" look
    double niceMin = 0;
    double niceMax = 100;

    // If all data is very high, move the window slightly but keep it wide
    if (minVal > 60) {
      niceMin = 40;
      niceMax = 110; // Extra room at top
    }

    return (niceMin, niceMax);
  }

  Widget _buildHeartRateStats(List<HealthDataPoint> data) {
    if (data.isEmpty) return const SizedBox();

    final values = data.map((e) => e.heartRate).toList();
    final avg = values.reduce((a, b) => a + b) / values.length;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);

    // Calculate time in different zones
    final restingZone = values.where((hr) => hr <= 60).length;
    final moderateZone = values.where((hr) => hr > 60 && hr <= 100).length;
    final highZone = values.where((hr) => hr > 100).length;

    final total = values.length.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Heart Rate Distribution',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: const Color(0xFFE8E8E8),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildZoneIndicator(
              'Resting',
              restingZone / total,
              Colors.green,
              Icons.favorite_border,
            ),
            const SizedBox(width: 12),
            _buildZoneIndicator(
              'Moderate',
              moderateZone / total,
              Colors.orange,
              Icons.favorite,
            ),
            const SizedBox(width: 12),
            _buildZoneIndicator(
              'High',
              highZone / total,
              Colors.red,
              Icons.favorite,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _buildStatChip('Avg: ${avg.round()} BPM', Colors.blue),
            _buildStatChip('Min: $min BPM', Colors.green),
            _buildStatChip('Max: $max BPM', Colors.red),
            _buildStatChip('Readings: ${data.length}', const Color(0xFFA0A0A0)),
          ],
        ),
      ],
    );
  }

  Widget _buildStressStats(List<HealthDataPoint> data) {
    if (data.isEmpty) return const SizedBox();

    final values = data.map((e) => e.stress).toList();
    final avg = values.reduce((a, b) => a + b) / values.length;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);

    // Calculate stress zones
    final lowStress = values.where((s) => s <= 33).length;
    final mediumStress = values.where((s) => s > 33 && s <= 66).length;
    final highStress = values.where((s) => s > 66).length;

    final total = values.length.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Stress Level Analysis',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: const Color(0xFFE8E8E8),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildZoneIndicator(
              'Low',
              lowStress / total,
              Colors.green,
              Icons.sentiment_satisfied,
            ),
            const SizedBox(width: 12),
            _buildZoneIndicator(
              'Medium',
              mediumStress / total,
              Colors.orange,
              Icons.sentiment_neutral,
            ),
            const SizedBox(width: 12),
            _buildZoneIndicator(
              'High',
              highStress / total,
              Colors.red,
              Icons.sentiment_very_dissatisfied,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _buildStatChip('Avg: ${avg.round()}%', Colors.blue),
            _buildStatChip('Min: $min%', Colors.green),
            _buildStatChip('Max: $max%', Colors.red),
            _buildStatChip(
              'Peak Stress: ${_calculatePeakStressDuration(values)}min',
              Colors.orange,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildZoneIndicator(
    String label,
    double percentage,
    Color color,
    IconData icon,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
          ),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              '${(percentage * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            Text(
              label,
              style: TextStyle(color: color.withOpacity(0.8), fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildEmptyChart(String title) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _buildCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFFE8E8E8),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 250,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xFF1A1A1A),
              border: Border.all(color: const Color(0xFF333333)),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.auto_graph_rounded,
                    color: const Color(0xFFA0A0A0),
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No data available yet',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFA0A0A0),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Data will appear as you collect more readings',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF666666),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  int _calculatePeakStressDuration(List<int> stressValues) {
    // Calculate consecutive high stress periods (stress > 66)
    int peakDuration = 0;
    int currentDuration = 0;

    for (final stress in stressValues) {
      if (stress > 66) {
        currentDuration++;
        peakDuration = peakDuration > currentDuration
            ? peakDuration
            : currentDuration;
      } else {
        currentDuration = 0;
      }
    }

    return peakDuration; // Each reading is roughly 1 minute in this context
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_rounded,
            color: Color(0xFFE8E8E8),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '${widget.metricName} - Detailed Analysis',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: const Color(0xFFE8E8E8),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFFE8E8E8)),
            onPressed: _loadWeeklyData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCurrentValueCard(),
            const SizedBox(height: 24),

            // Chart Selector and Chart
            // In metric_detail_screen.dart, replace the chart selector section:
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Data Visualization',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFE8E8E8),
                  ),
                ),
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.5,
                  ),
                  child: _buildChartSelector(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Selected Chart
            _selectedChartType == 0
                ? _buildBarChart(context)
                : _buildLineChart(context),
            const SizedBox(height: 24),

            if (widget.metricName == 'Heart Rate') ...[
              _buildAllTimeSharpChart(),
              const SizedBox(height: 24),
            ],
            if (widget.metricName == 'Stress' ||
                widget.metricName == 'Stress Level') ...[
              _buildAllTimeStressChart(),
              const SizedBox(height: 24),
            ],

            // Add Steps Detailed View
            if (widget.metricName == 'Steps') ...[
              _buildStepsDetailedView(),
              const SizedBox(height: 24),
            ],

            // Statistics Section
            _buildStatisticsSection(),
            const SizedBox(height: 24),

            // Add Enhanced Sleep Analysis for Sleep metric
            if (widget.metricName == 'Sleep') ...[
              _buildSleepQualityGauge(),
              const SizedBox(height: 24),
              _buildEnhancedSleepAnalysis(),
              const SizedBox(height: 24),
            ],

            // AI Insights
            _buildAIInsightsCard(),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStepsDetailedView() {
    return Column(
      children: [
        _buildStepMetricBarChart(
          title: 'Total Steps',
          metricKey: 'steps',
          color: Colors.cyan,
          unit: 'steps',
        ),
        const SizedBox(height: 24),
        _buildStepMetricBarChart(
          title: 'Calories Burned',
          metricKey: 'calories',
          color: Colors.orange,
          unit: 'kcal',
        ),
        const SizedBox(height: 24),
        _buildStepMetricBarChart(
          title: 'Distance Covered',
          metricKey: 'distance',
          color: Colors.green,
          unit: 'km',
        ),
      ],
    );
  }

  Widget _buildStepMetricBarChart({
    required String title,
    required String metricKey,
    required Color color,
    required String unit,
  }) {
    if (_weeklyBarData.isEmpty) return const SizedBox();

    // Prepare data based on metric key
    final List<Map<String, dynamic>> metricData = _weeklyBarData.map((day) {
      double value = 0;
      final rawPoints = day['rawDataPoints'] as List<HealthData>;

      if (rawPoints.isNotEmpty) {
        if (metricKey == 'steps') {
          value = rawPoints
              .map((e) => e.steps)
              .reduce((a, b) => a > b ? a : b)
              .toDouble();
        } else if (metricKey == 'calories') {
          value = rawPoints
              .map((e) => e.calories)
              .reduce((a, b) => a > b ? a : b)
              .toDouble();
        } else if (metricKey == 'distance') {
          final steps = rawPoints
              .map((e) => e.steps)
              .reduce((a, b) => a > b ? a : b);
          value = steps * 0.000762;
        }
      }

      return {
        'day': day['day'],
        'value': value,
        'isToday': day['isToday'],
        'fullDate': day['fullDate'],
      };
    }).toList();

    final values = metricData.map((e) => e['value'] as double).toList();
    final maxValue = values.isEmpty
        ? 100.0
        : values.reduce((a, b) => a > b ? a : b);
    final chartMax = maxValue == 0 ? 100.0 : maxValue * 1.2;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _buildCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFFE8E8E8),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceBetween,
                maxY: chartMax,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: const Color(0xFF1A1A1A),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        '${metricData[groupIndex]['day']} (${metricData[groupIndex]['fullDate']})\n'
                        '${rod.toY.toStringAsFixed(metricKey == 'distance' ? 2 : 0)} $unit',
                        TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index >= 0 && index < metricData.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              metricData[index]['day'],
                              style: const TextStyle(
                                color: Color(0xFF666666),
                                fontSize: 10,
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
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            value >= 1000
                                ? '${(value / 1000).toStringAsFixed(1)}k'
                                : value.toInt().toString(),
                            style: const TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 9,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        );
                      },
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
                  horizontalInterval: chartMax > 0 ? chartMax / 4 : 25,
                  getDrawingHorizontalLine: (value) =>
                      const FlLine(color: Color(0xFF333333), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barGroups: metricData.asMap().entries.map((entry) {
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [
                      BarChartRodData(
                        toY: entry.value['value'],
                        color: entry.value['isToday']
                            ? color
                            : color.withOpacity(0.5),
                        width: 16,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
