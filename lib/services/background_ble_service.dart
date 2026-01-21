// background_ble_service.dart - UPDATED FOR KOTLIN INTEGRATION
import 'dart:async';
import 'dart:convert'; // For JSON parsing
import 'package:zyora_final/local_storage_service.dart';
import 'package:zyora_final/services/ble_service.dart';
import 'package:flutter/services.dart';
import 'daily_questions_service.dart';
import 'health_calculations_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:pedometer/pedometer.dart'; // NEW: For iOS Steps

class BackgroundBLEService {
  static const String targetDeviceName = "ESP32_HealthBand";
  static const String serviceUUID = "12345678-1234-1234-1234-123456789abc";
  static const String characteristicUUID =
      "abcd1234-5678-90ab-cdef-123456789abc";

  static const MethodChannel _channel = MethodChannel(
    'zyora10/background_service',
  );
  static const EventChannel _eventChannel = EventChannel(
    'zyora10/background_events',
  );

  final LocalStorageService _localStorage = LocalStorageService();

  static final BackgroundBLEService _instance =
      BackgroundBLEService._internal();
  factory BackgroundBLEService() => _instance;
  BackgroundBLEService._internal();

  // Callbacks for UI updates
  Function(bool)? onConnectionStatusChanged;
  Function(HealthData)? onDataReceived;
  final StreamController<int> _stepStreamController =
      StreamController<int>.broadcast();
  Stream<int> get stepStream => _stepStreamController.stream;

  StreamSubscription<dynamic>? _backgroundEventSubscription;
  bool _isServiceRunning = false;

  // ... (lines 38-78 remain same)
  Future<void> initializeBackgroundService() async {
    try {
      // 🔍 CRITICAL FIX: Don't start if already running
      if (_isServiceRunning) {
        print('✅ Background service already running, skipping start');
        return;
      }

      print('🚀 Starting Kotlin Background Service...');
      if (Platform.isAndroid) {
        await _channel.invokeMethod('startBackgroundService');
        print('✅ Background service started');
      } else {
        print(
          'ℹ️ iOS detected: Using system Bluetooth background mode instead of Kotlin service',
        );
      }

      // 🔍 CRITICAL FIX: Start listening to background events
      _startListeningToBackgroundEvents();

      // NEW: For iOS, start the hardware step counter
      if (Platform.isIOS) {
        _initIOSStepCounting();
      }

      _isServiceRunning = true;
    } catch (e) {
      print('❌ Error starting background service: $e');
    }
  }

  void _startListeningToBackgroundEvents() {
    try {
      _backgroundEventSubscription = _eventChannel
          .receiveBroadcastStream()
          .listen(
            (dynamic event) {
              _handleBackgroundEvent(event);
            },
            onError: (error) {
              print('❌ Background event error: $error');
            },
          );
    } catch (e) {
      print('❌ Error setting up background event listener: $e');
    }
  }

  // --- Step Counter Methods ---
  Future<void> startStepCounter() async {
    try {
      print('🚀 Starting Step Counter Service...');
      if (Platform.isAndroid) {
        await _channel.invokeMethod('startStepCounter');
      }

      // Ensure we are listening to events
      _startListeningToBackgroundEvents();

      print('✅ Step counter service started');
    } catch (e) {
      print('❌ Error starting step counter: $e');
    }
  }

  Future<void> stopStepCounter() async {
    try {
      await _channel.invokeMethod('stopStepCounter');
      print('🛑 Step counter service stopped');
    } catch (e) {
      print('❌ Error stopping step counter: $e');
    }
  }

  Future<int> getSteps() async {
    try {
      if (Platform.isAndroid) {
        final steps = await _channel.invokeMethod('getSteps');
        return steps as int? ?? 0;
      }
      return 0;
    } catch (e) {
      print('❌ Error getting steps: $e');
      return 0;
    }
  }

  // NEW: iOS Hardware Step Counting logic
  void _initIOSStepCounting() {
    print('🏃 Initializing iOS Motion Step Counting...');
    Pedometer.stepCountStream.listen(
      (StepCount event) {
        final steps = event.steps;
        print('🏃 iOS Hardware Steps: $steps');
        _stepStreamController.add(steps);
        _savePhoneSteps(steps);
      },
      onError: (error) => print('❌ iOS Pedometer Error: $error'),
      cancelOnError: false,
    );
  }

  void _handleBackgroundEvent(dynamic event) {
    try {
      if (event is Map) {
        final eventType = event['type'];
        final data = event['data'];

        switch (eventType) {
          case 'health_data_received':
            _processHealthData(data);
            break;
          case 'step_data': // NEW
            if (data != null && data['steps'] != null) {
              final steps = data['steps'] as int;
              _stepStreamController.add(steps);
              _savePhoneSteps(steps);
            }
            break;
          case 'connection_status':
            final connected = data['connected'] ?? false;
            _updateConnectionStatus(connected);
            break;
          case 'service_started':
            print('✅ Background service started successfully');
            _isServiceRunning = true;
            break;
          case 'service_stopped':
            print('🛑 Background service stopped');
            _isServiceRunning = false;
            break;
          case 'error':
            print('❌ Background service error: ${data['message']}');
            break;
          case 'log':
            print('📱 Background: ${data['message']}');
            break;
          case 'notification_received':
            _handleIncomingNotification(data);
            break;
        }
      }
    } catch (e) {
      print('❌ Error handling background event: $e');
    }
  }

  void _handleIncomingNotification(Map<String, dynamic> data) async {
    final message = data['message'];
    if (message == "Please wear your band") {
      print('📢 Received Wear Band notification in Flutter');
      // If we want Flutter to show a local notification as well, we call it here.
      // NOTE: Kotlin is already showing a native notification for reliability in the background.
    }
  }

  Future<void> _savePhoneSteps(int steps) async {
    try {
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();

      // Throttling: only save if steps changed by at least 10 or 10 minutes passed
      final lastSavedSteps = prefs.getInt('last_saved_phone_steps') ?? -1;
      final lastSaveTimeStr = prefs.getString('last_phone_steps_save_time');
      final lastSaveTime = lastSaveTimeStr != null
          ? DateTime.parse(lastSaveTimeStr)
          : DateTime.fromMillisecondsSinceEpoch(0);

      bool isFirstSave = lastSavedSteps == -1;
      bool significantChange = (steps - lastSavedSteps).abs() >= 10;
      bool timePassed = now.difference(lastSaveTime).inMinutes >= 10;

      if (isFirstSave || significantChange || timePassed) {
        final latest = await _localStorage.getLatestHealthData();

        // If latest data is very old, we might want to use defaults for non-step metrics
        // but for now, we'll carry over the last known state for a seamless UI experience
        final dataPoint = HealthDataPoint(
          heartRate: latest?.heartRate ?? 72,
          steps: steps,
          spo2: latest?.spo2 ?? 98,
          calories: (steps * 0.04).round(),
          sleep: latest?.sleep ?? 7.0,
          recovery: latest?.recovery ?? 85,
          stress: latest?.stress ?? 30,
          rhr: latest?.rhr ?? 65,
          hrv: latest?.hrv ?? 45,
          bodyTemperature: latest?.bodyTemperature ?? 36.5,
          breathingRate: latest?.breathingRate ?? 16,
          timestamp: now,
        );

        await _localStorage.saveHealthData(dataPoint);

        // Update prefs
        await prefs.setInt('last_saved_phone_steps', steps);
        await prefs.setString(
          'last_phone_steps_save_time',
          now.toIso8601String(),
        );

        print('💾 Saved phone steps to database: $steps');
      }
    } catch (e) {
      print('❌ Error saving phone steps to database: $e');
    }
  }

  void _updateConnectionStatus(bool connected) {
    if (onConnectionStatusChanged != null) {
      onConnectionStatusChanged!(connected);
    }
  }

  Future<void> _processHealthData(Map<String, dynamic> data) async {
    try {
      final healthData = HealthData.fromJson(data);

      // NEW: Support for pending data timestamps from Kotlin
      final targetTimestamp = healthData.timestamp ?? DateTime.now();

      // Get activity intensity for the day this data belongs to
      final dailyQuestionsService = DailyQuestionsService();
      final targetQuestions = await dailyQuestionsService.getQuestionsForDate(
        targetTimestamp,
      );
      final activityIntensity = targetQuestions?.activityIntensity;

      // Verification: Check if it fits in sleep window (for logging/debugging)
      bool fitsSleepWindow = false;
      if (healthData.isPending &&
          targetQuestions != null &&
          targetQuestions.bedtime != null &&
          targetQuestions.wakeTime != null) {
        final window = HealthCalculationsService.getSleepWindow(
          targetQuestions.date,
          targetQuestions.bedtime!,
          targetQuestions.wakeTime!,
        );
        if (window != null) {
          fitsSleepWindow =
              targetTimestamp.isAfter(window['start']!) &&
              targetTimestamp.isBefore(window['end']!);
          print(
            '💤 Pending data at $targetTimestamp fits sleep window: $fitsSleepWindow',
          );
        }
      }

      // SYNC SMART METRICS FROM STORAGE
      int smartRecovery = healthData.recovery;
      int smartRHR = healthData.rhr;
      int smartHRV = healthData.hrv;

      try {
        final prefs = await SharedPreferences.getInstance();
        final dateStr = targetTimestamp.toIso8601String().split('T')[0];
        final lastScoreDate = prefs.getString('last_score_date');

        // Note: Currently we only store the LATEST day's metrics in these specific SharedPreferences keys.
        // For historical batch sync, they will fallback to Band defaults (handled in HealthData.fromJson)
        // OR we'd need a more robust persistent daily baseline storage.
        if (lastScoreDate == dateStr) {
          smartRecovery = prefs.getInt('daily_recovery_score') ?? smartRecovery;
          smartRHR = prefs.getInt('daily_calculated_rhr') ?? smartRHR;
          smartHRV = prefs.getInt('daily_calculated_hrv') ?? smartHRV;
          print(
            '📊 Background syncing new data point with smart metrics: Recovery=$smartRecovery',
          );
        }
      } catch (e) {
        print('Error syncing smart metrics in background: $e');
      }

      // 🔍 CRITICAL: Ignore Band steps, use Phone steps from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final latestPhoneSteps = prefs.getInt('last_saved_phone_steps') ?? 0;

      // Save to local storage
      final dataPoint = HealthDataPoint(
        heartRate: healthData.heartRate,
        steps: latestPhoneSteps, // USE PHONE STEPS
        spo2: healthData.spo2,
        calories: (latestPhoneSteps * 0.04).round(),
        sleep: healthData.sleep,
        recovery: smartRecovery,
        stress: healthData.stress,
        rhr: smartRHR,
        hrv: smartHRV,
        bodyTemperature: healthData.bodyTemperature,
        breathingRate: healthData.breathingRate,
        activityIntensity: activityIntensity,
        timestamp: targetTimestamp,
      );

      await _localStorage.saveHealthData(dataPoint);

      print(
        '💾 Background data saved: HR ${healthData.heartRate}, Activity ${activityIntensity ?? "N/A"}% at $targetTimestamp',
      );

      // Notify UI if app is in foreground
      if (onDataReceived != null) {
        onDataReceived!(healthData);
      }
    } catch (e) {
      print('❌ Error processing health data: $e');
    }
  }

  Future<void> stopBackgroundService() async {
    try {
      // Cancel the event subscription to prevent memory leaks
      await _backgroundEventSubscription?.cancel();
      _backgroundEventSubscription = null;

      await _channel.invokeMethod('stopBackgroundService');
      _isServiceRunning = false;
      print('🛑 Background service stopped');
    } catch (e) {
      print('❌ Error stopping background service: $e');
    }
  }

  /// Dispose method to clean up resources
  /// Call this when the service is no longer needed
  Future<void> dispose() async {
    await _backgroundEventSubscription?.cancel();
    _backgroundEventSubscription = null;
    _isServiceRunning = false;
  }

  Future<void> sendTestData() async {
    try {
      await _channel.invokeMethod('testService');
    } on PlatformException catch (e) {
      print("❌ Test failed: '${e.message}'.");
    }
  }

  Future<void> saveDeviceAddress(String address) async {
    try {
      await _channel.invokeMethod('saveDeviceAddress', address);
      print('💾 Device address saved to Kotlin service');
    } catch (e) {
      print('❌ Error saving device address: $e');
    }
  }

  /// Get health data history collected by background service
  Future<List<HealthDataPoint>> getHealthDataHistory() async {
    try {
      final String? historyJson = await _channel.invokeMethod(
        'getHealthDataHistory',
      );
      if (historyJson == null || historyJson == '[]') {
        print('📊 No background data history found');
        return [];
      }

      final List<dynamic> jsonArray = json.decode(historyJson);
      print(
        '📊 Loading ${jsonArray.length} data points from background service',
      );

      final List<HealthDataPoint> dataPoints = [];
      for (var item in jsonArray) {
        try {
          final healthData = HealthData.fromJson(item as Map<String, dynamic>);

          final timestamp = DateTime.fromMillisecondsSinceEpoch(
            (item['timestamp'] as num).toInt(),
          );
          final dateStr = timestamp.toIso8601String().split('T')[0];

          int smartRecovery = healthData.recovery;
          int smartRHR = healthData.rhr;
          int smartHRV = healthData.hrv;

          // Note: This sync is less efficient in a loop but ensures historical accuracy if keys exists
          try {
            final prefs = await SharedPreferences.getInstance();
            final lastScoreDate = prefs.getString('last_score_date');
            if (lastScoreDate == dateStr) {
              smartRecovery =
                  prefs.getInt('daily_recovery_score') ?? smartRecovery;
              smartRHR = prefs.getInt('daily_calculated_rhr') ?? smartRHR;
              smartHRV = prefs.getInt('daily_calculated_hrv') ?? smartHRV;
            }
          } catch (_) {}

          dataPoints.add(
            HealthDataPoint(
              heartRate: healthData.heartRate,
              steps: healthData.steps,
              spo2: healthData.spo2,
              calories: healthData.calories,
              sleep: healthData.sleep,
              recovery: smartRecovery,
              stress: healthData.stress,
              rhr: smartRHR,
              hrv: smartHRV,
              bodyTemperature: healthData.bodyTemperature,
              breathingRate: healthData.breathingRate,
              timestamp: timestamp,
            ),
          );
        } catch (e) {
          print('⚠️ Error parsing data point: $e');
        }
      }

      print('✅ Loaded ${dataPoints.length} background data points');
      return dataPoints;
    } catch (e) {
      print('❌ Error getting health data history: $e');
      return [];
    }
  }

  /// Syncs background-collected data from Kotlin service to Flutter SQLite database
  /// This should be called when the app starts to ensure all background data is visible
  Future<void> syncBackgroundDataToDatabase() async {
    try {
      print('🔄 Syncing background data to database...');

      // Get historical data from Kotlin SharedPreferences
      final backgroundDataPoints = await getHealthDataHistory();

      if (backgroundDataPoints.isEmpty) {
        print('📊 No background data to sync');
        return;
      }

      print(
        '📊 Found ${backgroundDataPoints.length} background data points to sync',
      );

      // Get latest data from SQLite to avoid duplicates
      final latestSqliteData = await _localStorage.getLatestHealthData();
      final latestSqliteTimestamp =
          latestSqliteData?.timestamp.millisecondsSinceEpoch ?? 0;

      int syncedCount = 0;

      // Save each background data point to SQLite if it's newer than latest SQLite data
      for (var dataPoint in backgroundDataPoints) {
        final dataTimestamp = dataPoint.timestamp.millisecondsSinceEpoch;

        // Only sync data that's newer than what we have in SQLite
        if (dataTimestamp > latestSqliteTimestamp) {
          await _localStorage.saveHealthData(dataPoint);
          syncedCount++;
        }
      }

      print(
        '✅ Synced $syncedCount new data points from background service to database',
      );
    } catch (e) {
      print('❌ Error syncing background data to database: $e');
    }
  }

  // Getters
  bool get isServiceRunning => _isServiceRunning;
  bool get isConnected {
    // This would be updated via the event channel
    return false; // You'll need to track this from events
  }
}
