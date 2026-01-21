package com.example.zyora_final

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.content.Context
import android.content.Intent
import android.os.Build

class MainActivity: FlutterActivity() {
    private val METHOD_CHANNEL = "zyora10/background_service"
    private val EVENT_CHANNEL = "zyora10/background_events"

    companion object {
        // Static event sink to send events from background service
        var eventSink: EventChannel.EventSink? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Method channel for commands
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startBackgroundService" -> {
                    try {
                        startBackgroundService()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "stopBackgroundService" -> {
                    try {
                        stopBackgroundService()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "saveDeviceAddress" -> {
                    try {
                        val address = call.arguments as String
                        saveDeviceAddress(address)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SAVE_ERROR", e.message, null)
                    }
                }
                "getHealthDataHistory" -> {
                    try {
                        val history = getHealthDataHistory()
                        result.success(history)
                    } catch (e: Exception) {
                        result.error("GET_ERROR", e.message, null)
                    }
                }
                "startStepCounter" -> {
                    try {
                        startStepCounterService()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "stopStepCounter" -> {
                    try {
                        stopStepCounterService()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "getSteps" -> {
                    try {
                        val steps = getSteps()
                        result.success(steps)
                    } catch (e: Exception) {
                        result.error("GET_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Event channel for background service events
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    // Send initial status
                    eventSink?.success(mapOf(
                        "type" to "log",
                        "data" to mapOf("message" to "Event channel connected")
                    ))
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    private fun startBackgroundService() {
        // 🔥 CRITICAL: Check if service is already running to prevent duplicate starts
        val prefs = getSharedPreferences("health_data", Context.MODE_PRIVATE)
        val isServiceRunning = prefs.getBoolean("service_running", false)
        
        if (isServiceRunning) {
            android.util.Log.d("MainActivity", "✅ Service already running, skipping start")
            return
        }
        
        val intent = Intent(this, BackgroundBLEService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        android.util.Log.d("MainActivity", "🚀 Started background service")
    }

    private fun stopBackgroundService() {
        val intent = Intent(this, BackgroundBLEService::class.java)
        stopService(intent)
    }

    private fun saveDeviceAddress(address: String) {
        val prefs = getSharedPreferences("health_data", Context.MODE_PRIVATE)
        prefs.edit().putString("last_device_address", address).apply()
    }

    private fun getHealthDataHistory(): String {
        val prefs = getSharedPreferences("health_data", Context.MODE_PRIVATE)
        val history = prefs.getString("health_data_history", "[]") ?: "[]"
        android.util.Log.d("MainActivity", "📊 Retrieved ${history.length} chars of history data")
        return history
    }

    private fun startStepCounterService() {
        val intent = Intent(this, StepCounterService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopStepCounterService() {
        val intent = Intent(this, StepCounterService::class.java)
        stopService(intent)
    }

    private fun getSteps(): Int {
         val prefs = getSharedPreferences("step_data", Context.MODE_PRIVATE)
         return prefs.getInt("current_steps", 0)
    }
}