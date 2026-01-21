// boot_complete_receiver.dart - SIMPLIFIED
import 'package:flutter/services.dart';
import 'background_ble_service.dart';

class BootCompleteReceiver {
  static const MethodChannel _channel = MethodChannel('zyora10/boot_receiver');

  static Future<void> initialize() async {
    try {
      print('🔧 Initializing Boot Complete Receiver...');
      // The Kotlin receiver will handle boot events automatically
      await BackgroundBLEService().initializeBackgroundService();
    } catch (e) {
      print('❌ Error initializing boot receiver: $e');
    }
  }
}
