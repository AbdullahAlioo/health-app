import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../local_storage_service.dart';
import 'background_ble_service.dart';
import 'daily_questions_service.dart'; // NEW
import 'health_calculations_service.dart';
import 'notification_service.dart';

class HealthData {
  final int heartRate;
  final int steps;
  final int spo2;
  final int calories;
  final double sleep;
  final int recovery;
  final int stress;
  final int rhr;
  final int hrv;
  final double bodyTemperature;

  final int breathingRate;
  final int? activityIntensity; // NEW
  final DateTime? timestamp;
  final bool isPending;

  HealthData({
    required this.heartRate,
    this.steps = 0, // Default to 0
    required this.spo2,
    required this.calories,
    required this.sleep,
    required this.recovery,
    required this.stress,
    required this.rhr,
    required this.hrv,
    required this.bodyTemperature,
    required this.breathingRate,
    this.activityIntensity, // NEW
    this.timestamp,
    this.isPending = false,
  });

  factory HealthData.fromJson(Map<String, dynamic> json) {
    bool isPending = json['pending'] ?? false;
    int cycleCount = json['cycleCount'] ?? 0;

    DateTime? timestamp;
    if (json['timestamp'] != null) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(json['timestamp']);
    } else if (isPending) {
      // 1 cycle = 5 minutes
      timestamp = DateTime.now().subtract(Duration(minutes: cycleCount * 5));
    }

    return HealthData(
      heartRate: json['heartRate'] ?? 72,
      steps: 0, // IGNORE STEPS FROM BAND - Always use phone stepcounter
      spo2: json['spo2'] ?? 98,
      calories: json['calories'] ?? 0,
      sleep: (json['sleep'] ?? 7.0).toDouble(),
      recovery: json['recovery'] ?? 85,
      stress: json['stress'] ?? 30,
      bodyTemperature: (json['bodyTemperature'] ?? 36.5).toDouble(),
      breathingRate: json['breathingRate'] ?? 16,
      hrv: 45, // IGNORE HRV FROM BAND - Use sensible default
      activityIntensity: json['activityIntensity'],
      rhr: 60, // IGNORE RHR FROM BAND - Use sensible default
      timestamp: timestamp,
      isPending: isPending,
    );
  }

  factory HealthData.fromHealthDataPoint(HealthDataPoint data) {
    return HealthData(
      heartRate: data.heartRate,
      steps: data.steps,
      spo2: data.spo2,
      calories: data.calories,
      sleep: data.sleep,
      recovery: data.recovery,
      stress: data.stress,
      rhr: data.rhr,
      hrv: data.hrv,
      bodyTemperature: data.bodyTemperature,
      breathingRate: data.breathingRate,
      activityIntensity: data.activityIntensity,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'heartRate': heartRate,
      'steps': steps,
      'spo2': spo2,
      'calories': calories,
      'sleep': sleep,
      'recovery': recovery,
      'stress': stress,
      'rhr': rhr,
      'hrv': hrv,
      'bodyTemperature': bodyTemperature,
      'breathingRate': breathingRate,
      'activityIntensity': activityIntensity, // NEW
      'timestamp': timestamp?.millisecondsSinceEpoch,
      'isPending': isPending,
    };
  }

  String getStressLevelText() {
    if (stress <= 33) return 'Low';
    if (stress <= 66) return 'Medium';
    return 'High';
  }

  String getHRVStatus() {
    if (hrv >= 60) return 'Excellent';
    if (hrv >= 40) return 'Good';
    if (hrv >= 30) return 'Fair';
    return 'Poor';
  }

  String getRHRStatus() {
    if (rhr <= 55) return 'Excellent';
    if (rhr <= 65) return 'Good';
    if (rhr <= 75) return 'Fair';
    return 'Poor';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HealthData &&
        other.heartRate == heartRate &&
        other.steps == steps &&
        other.spo2 == spo2 &&
        other.calories == calories &&
        other.sleep == sleep &&
        other.recovery == recovery &&
        other.stress == stress &&
        other.rhr == rhr &&
        other.hrv == hrv;
  }

  @override
  int get hashCode {
    return heartRate.hashCode ^
        steps.hashCode ^
        spo2.hashCode ^
        calories.hashCode ^
        sleep.hashCode ^
        recovery.hashCode ^
        stress.hashCode ^
        rhr.hashCode ^
        hrv.hashCode;
  }

  HealthData copyWith({
    int? heartRate,
    int? steps,
    int? spo2,
    int? calories,
    double? sleep,
    int? recovery,
    int? stress,
    int? rhr,
    int? hrv,
    double? bodyTemperature,
    int? breathingRate,
    int? activityIntensity,
  }) {
    return HealthData(
      heartRate: heartRate ?? this.heartRate,
      steps: steps ?? this.steps,
      spo2: spo2 ?? this.spo2,
      calories: calories ?? this.calories,
      sleep: sleep ?? this.sleep,
      recovery: recovery ?? this.recovery,
      stress: stress ?? this.stress,
      rhr: rhr ?? this.rhr,
      hrv: hrv ?? this.hrv,
      bodyTemperature: bodyTemperature ?? this.bodyTemperature,
      breathingRate: breathingRate ?? this.breathingRate,
      activityIntensity: activityIntensity ?? this.activityIntensity,
      timestamp: timestamp ?? this.timestamp,
      isPending: isPending,
    );
  }
}

class BLEService {
  static const String targetDeviceName = "ESP32_HealthBand";
  static const String serviceUUID = "12345678-1234-1234-1234-123456789abc";
  static const String characteristicUUID =
      "abcd1234-5678-90ab-cdef-123456789abc";
  static const String lastDeviceKey = "last_connected_device";

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _targetCharacteristic;
  Timer? _fakeDataTimer;
  Timer? _hourlyTimer;
  Timer? _reconnectTimer;
  bool _isSimulating = false;
  bool _isConnected = false;
  bool _isScanning = false;
  final StringBuffer _packetBuffer = StringBuffer();
  HealthData? _latestHealthData; // Tracks the most recent metrics

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  final StreamController<HealthData> _dataController =
      StreamController<HealthData>.broadcast();
  final LocalStorageService _localStorage = LocalStorageService();

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<HealthData> get dataStream => _dataController.stream;
  bool get isConnected => _isConnected;

  Future<void> initialize() async {
    try {
      _startHourlyProcessing();
      final latestData = await _localStorage.getLatestHealthData();
      if (latestData != null) {
        _latestHealthData = HealthData.fromHealthDataPoint(latestData);
        _dataController.add(_latestHealthData!);
        print('Loaded latest saved data from local storage');
      }

      // 🔍 CRITICAL: Listen for phone steps from background service
      BackgroundBLEService().stepStream.listen((steps) {
        print('📱 BLEService received phone steps: $steps');
        if (_latestHealthData != null) {
          _latestHealthData = _latestHealthData!.copyWith(steps: steps);
          _dataController.add(_latestHealthData!);
        } else {
          // If no data yet, create a default one with these steps
          _latestHealthData = HealthData(
            heartRate: 72,
            steps: steps,
            spo2: 98,
            calories: (steps * 0.04).round(),
            sleep: 7.0,
            recovery: 85,
            stress: 30,
            rhr: 65,
            hrv: 45,
            bodyTemperature: 36.5,
            breathingRate: 16,
          );
          _dataController.add(_latestHealthData!);
        }
      });
    } catch (e) {
      print('Error loading latest data: $e');
    }
  }

  void _startHourlyProcessing() {
    _hourlyTimer = Timer.periodic(const Duration(hours: 1), (timer) {
      _processHourlyData();
    });
  }

  Future<void> _processHourlyData() async {
    try {
      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
      final now = DateTime.now();

      final hourlyAverages = await _localStorage.getHourlyAverages(
        oneHourAgo,
        now,
      );

      print(
        'Processed ${hourlyAverages.length} hourly data points for period: $oneHourAgo to $now',
      );

      await _localStorage.clearOldData();
    } catch (e) {
      print('Error processing hourly data: $e');
    }
  }

  Future<void> _processAndSaveData(HealthData data) async {
    try {
      final targetTimestamp = data.timestamp ?? DateTime.now();

      // Get activity intensity for the day this data belongs to
      final dailyQuestionsService = DailyQuestionsService();
      final targetQuestions = await dailyQuestionsService.getQuestionsForDate(
        targetTimestamp,
      );
      final activityIntensity = targetQuestions?.activityIntensity;

      // Verification: Check if it fits in sleep window
      if (data.isPending &&
          targetQuestions != null &&
          targetQuestions.bedtime != null &&
          targetQuestions.wakeTime != null) {
        final window = HealthCalculationsService.getSleepWindow(
          targetQuestions.date,
          targetQuestions.bedtime!,
          targetQuestions.wakeTime!,
        );
        if (window != null) {
          bool fitsSleepWindow =
              targetTimestamp.isAfter(window['start']!) &&
              targetTimestamp.isBefore(window['end']!);
          print(
            '💤 Foreground sync: Pending data at $targetTimestamp fits sleep window: $fitsSleepWindow',
          );
        }
      }

      // SYNC SMART METRICS FROM STORAGE (Calculated by Dashboard once a day)
      // This ensures AI chat and other screens don't see raw defaults (85/60/45)
      int smartRecovery = data.recovery;
      int smartRHR = data.rhr;
      int smartHRV = data.hrv;

      try {
        final prefs = await SharedPreferences.getInstance();
        final dateStr = targetTimestamp.toIso8601String().split('T')[0];
        final lastScoreDate = prefs.getString('last_score_date');

        if (lastScoreDate == dateStr) {
          smartRecovery = prefs.getInt('daily_recovery_score') ?? smartRecovery;
          smartRHR = prefs.getInt('daily_calculated_rhr') ?? smartRHR;
          smartHRV = prefs.getInt('daily_calculated_hrv') ?? smartHRV;
          print(
            '📊 Syncing new data point with smart metrics: Recovery=$smartRecovery, RHR=$smartRHR, HRV=$smartHRV',
          );
        }
      } catch (e) {
        print('Error syncing smart metrics for saving: $e');
      }

      // 🔍 CRITICAL FIX: Fetch latest phone steps from SharedPreferences
      // instead of using whatever (now 0) came from the Band.
      final prefs = await SharedPreferences.getInstance();
      final latestPhoneSteps = prefs.getInt('last_saved_phone_steps') ?? 0;

      final dataPoint = HealthDataPoint(
        heartRate: data.heartRate,
        steps: latestPhoneSteps, // USE PHONE STEPS
        spo2: data.spo2,
        calories: (latestPhoneSteps * 0.04).round(),
        sleep: data.sleep,
        recovery: smartRecovery,
        timestamp: targetTimestamp,
        stress: data.stress,
        rhr: smartRHR,
        hrv: smartHRV,
        bodyTemperature: data.bodyTemperature,
        breathingRate: data.breathingRate,
        activityIntensity: activityIntensity,
      );

      await _localStorage.saveHealthData(dataPoint);

      // Create a copy of 'data' with smart metrics for the stream
      final updatedData = data.copyWith(
        recovery: smartRecovery,
        rhr: smartRHR,
        hrv: smartHRV,
      );

      _latestHealthData = updatedData;
      _dataController.add(updatedData);

      print(
        'Data saved: ${targetTimestamp.toString()} - HR: ${data.heartRate}, Recovery: $smartRecovery%, HRV: $smartHRV',
      );
    } catch (e) {
      print('Error processing data: $e');
    }
  }

  void _stopReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<bool> autoConnect() async {
    if (_isConnected) return true;

    final prefs = await SharedPreferences.getInstance();
    final lastDeviceId = prefs.getString(lastDeviceKey);

    if (lastDeviceId != null) {
      try {
        final connectedDevices = FlutterBluePlus.connectedDevices;
        for (var connectedDevice in connectedDevices) {
          if (connectedDevice.remoteId.toString() == lastDeviceId) {
            print(' Device already connected: ${connectedDevice.platformName}');
            _connectedDevice = connectedDevice;
            _isConnected = true;
            _connectionController.add(true);
            await _subscribeToCharacteristics(connectedDevice);
            _stopFakeData();
            _stopReconnectTimer();
            return true;
          }
        }

        print('Attempting auto-connect to last device: $lastDeviceId');
        final device = BluetoothDevice.fromId(lastDeviceId);

        await device.connect(timeout: const Duration(seconds: 15));

        _connectedDevice = device;
        _isConnected = true;
        _connectionController.add(true);
        await _subscribeToCharacteristics(device);
        _stopFakeData();
        print('Auto-connect successful');
        return true;
      } catch (e) {
        print("Auto-connect failed: $e");

        return await scanForDevices();
      }
    } else {
      return await scanForDevices();
    }
  }

  Future<bool> scanForDevices() async {
    if (_isScanning) return false;

    try {
      _isScanning = true;

      final connectedDevices = FlutterBluePlus.connectedDevices;
      for (var connectedDevice in connectedDevices) {
        if (connectedDevice.platformName == targetDeviceName) {
          print(
            ' Target device already connected: ${connectedDevice.platformName}',
          );
          _isScanning = false;
          _connectedDevice = connectedDevice;
          _isConnected = true;
          _connectionController.add(true);
          await _subscribeToCharacteristics(connectedDevice);
          _stopFakeData();
          _stopReconnectTimer();
          await _saveLastDevice(connectedDevice.remoteId.toString());
          await BackgroundBLEService().saveDeviceAddress(
            connectedDevice.remoteId.toString(),
          );
          return true;
        }
      }

      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }

      print('Starting BLE scan for $targetDeviceName...');
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      final completer = Completer<bool>();
      StreamSubscription<List<ScanResult>>? subscription;

      subscription = FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult result in results) {
          if (result.device.platformName == targetDeviceName) {
            print('Found target device: ${result.device.platformName}');
            subscription?.cancel();
            await FlutterBluePlus.stopScan();
            _isScanning = false;
            bool connected = await _connectToDevice(result.device);
            completer.complete(connected);
            return;
          }
        }
      });

      Future.delayed(const Duration(seconds: 15), () {
        if (!completer.isCompleted) {
          subscription?.cancel();
          FlutterBluePlus.stopScan();
          _isScanning = false;
          completer.complete(false);
          print('Scan timeout - device not found');
        }
      });

      final result = await completer.future;

      if (!result) {
        print('Scan completed - device not found');
        _isConnected = false;
      }

      return result;
    } catch (e) {
      print("Error scanning: $e");
      _isScanning = false;
      _isConnected = false;
      return false;
    }
  }

  Future<bool> _connectToDevice(BluetoothDevice device) async {
    try {
      print('Connecting to device: ${device.platformName}');
      await device.connect(timeout: const Duration(seconds: 15));

      // 🔥 Request larger MTU to prevent JSON truncation
      try {
        await device.requestMtu(512);
        print('Requested MTU 512 for ${device.platformName}');
      } catch (e) {
        print('Could not request MTU: $e');
      }

      _connectedDevice = device;
      _isConnected = true;
      _connectionController.add(true);
      _saveLastDevice(device.remoteId.toString());

      await BackgroundBLEService().saveDeviceAddress(
        device.remoteId.toString(),
      );

      List<BluetoothService> services = await device.discoverServices();
      await _findTargetService(services);
      _stopFakeData();
      _stopReconnectTimer();

      print('Successfully connected to ${device.platformName}');
      return true;
    } catch (e) {
      print("Error connecting to device: $e");
      _isConnected = false;
      _connectionController.add(false);
      return false;
    }
  }

  Future<void> _subscribeToCharacteristics(BluetoothDevice device) async {
    try {
      List<BluetoothService> services = await device.discoverServices();
      await _findTargetService(services);
    } catch (e) {
      print("Error discovering services: $e");
    }
  }

  Future<void> _findTargetService(List<BluetoothService> services) async {
    for (BluetoothService service in services) {
      if (service.uuid.toString().toLowerCase() == serviceUUID) {
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          if (characteristic.uuid.toString().toLowerCase() ==
              characteristicUUID) {
            _targetCharacteristic = characteristic;
            await _startListeningToCharacteristics();
            print('Found target characteristic - starting data stream');
            return;
          }
        }
      }
    }
    print('Warning: Target service or characteristic not found');
  }

  Future<void> _startListeningToCharacteristics() async {
    if (_targetCharacteristic == null) return;

    try {
      await _targetCharacteristic!.setNotifyValue(true);

      _targetCharacteristic!.onValueReceived.listen((value) async {
        try {
          String chunk = String.fromCharCodes(value).trim();
          // Remove any non-printable characters
          chunk = chunk.replaceAll(RegExp(r'[^\x20-\x7E]'), '');

          if (chunk.isEmpty) return;

          _packetBuffer.write(chunk);
          String accumulated = _packetBuffer.toString();

          // 🔄 Robust Frame Extraction: Handle concatenated or partial JSONs
          while (accumulated.contains('{') && accumulated.contains('}')) {
            int start = accumulated.indexOf('{');
            int end = accumulated.indexOf('}') + 1;

            if (end > start) {
              String frame = accumulated.substring(start, end);
              print("📊 Processing frame: $frame");

              try {
                Map<String, dynamic> jsonData = json.decode(frame);

                if (jsonData.containsKey('message') &&
                    jsonData['message'] == "Please wear your band") {
                  print('📢 Received Wear Band notification in foreground');
                  // Use the notification service to show an alert
                  NotificationService().showBandWearNotification();
                } else {
                  HealthData healthData = HealthData.fromJson(jsonData);
                  await _processAndSaveData(healthData);
                }
              } catch (e) {
                print("Error decoding frame: $e");
              }

              // Remove processed frame from buffer
              accumulated = accumulated.substring(end);
              _packetBuffer.clear();
              _packetBuffer.write(accumulated);
            } else {
              // Discard garbage before the first '{'
              accumulated = accumulated.substring(start);
              _packetBuffer.clear();
              _packetBuffer.write(accumulated);
              break;
            }
          }

          if (_packetBuffer.length > 2000) {
            print("⚠️ Buffer overflow, clearing");
            _packetBuffer.clear();
          }
        } catch (e) {
          print("Error parsing data chunk: $e");
        }
      });

      print('Successfully subscribed to characteristic notifications');
    } catch (e) {
      print("Error subscribing to characteristic: $e");
    }
  }

  void _stopFakeData() {
    if (!_isSimulating) return;

    _isSimulating = false;
    _fakeDataTimer?.cancel();
    _fakeDataTimer = null;
    print('Stopped simulation mode - using real device data');
  }

  Future<void> _saveLastDevice(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastDeviceKey, deviceId);
      print('Saved last device ID: $deviceId');
    } catch (e) {
      print('Error saving last device: $e');
    }
  }

  Future<List<HealthDataPoint>> getHourlyAverages(
    DateTime startDate,
    DateTime endDate,
  ) async {
    return await _localStorage.getHourlyAverages(startDate, endDate);
  }

  Future<List<HealthDataPoint>> getAllHealthData() async {
    return await _localStorage.getAllHealthData();
  }

  Future<HealthData?> getLatestHealthData() async {
    final latestData = await _localStorage.getLatestHealthData();
    if (latestData == null) return null;
    return HealthData.fromHealthDataPoint(latestData);
  }

  Future<List<int>> getHRDataForRange(DateTime start, DateTime end) async {
    return await _localStorage.getHRDataForRange(start, end);
  }

  // NEW: Get activity intensity from storage for today
  Future<int?> getActivityIntensityForToday() async {
    final today = DateTime.now();
    return await _localStorage.getActivityIntensityForDate(today);
  }

  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      print('Disconnecting from device: ${_connectedDevice!.platformName}');
      await _connectedDevice!.disconnect();
    }
    _isConnected = false;
    _connectionController.add(false);
    _connectedDevice = null;
    _targetCharacteristic = null;
    _packetBuffer.clear(); // Clear buffer on disconnect
    _stopReconnectTimer();
  }

  // NEW: Save calculated RHR/HRV for a specific date
  Future<void> saveCalculatedDailyBaselines(
    DateTime date,
    int rhr,
    int hrv,
    int recovery,
  ) async {
    await _localStorage.updateDailyCalculatedMetrics(date, rhr, hrv, recovery);
  }

  void dispose() {
    print('Disposing BLE Service...');
    _stopFakeData();
    _stopReconnectTimer();
    _hourlyTimer?.cancel();
    _connectionController.close();
    _dataController.close();
  }
}
