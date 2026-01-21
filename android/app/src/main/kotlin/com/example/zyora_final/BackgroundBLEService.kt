package com.example.zyora_final

import android.app.*
import android.bluetooth.*
import android.content.*
import android.os.*
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import org.json.JSONObject
import java.util.*

class BackgroundBLEService : Service() {
    companion object {
        const val TAG = "BackgroundBLEService"
        const val CHANNEL_ID = "ZyoraBackgroundChannel"
        const val NOTIFICATION_ID = 1
        const val ACTION_START_SERVICE = "ACTION_START_SERVICE"
        const val ACTION_STOP_SERVICE = "ACTION_STOP_SERVICE"
        const val ACTION_HEALTH_DATA = "com.example.zyora_final.HEALTH_DATA"
        const val ACTION_CONNECTION_STATUS = "com.example.zyora_final.CONNECTION_STATUS"
    }

    private lateinit var bluetoothManager: BluetoothManager
    private lateinit var bluetoothAdapter: BluetoothAdapter
    private var bluetoothGatt: BluetoothGatt? = null
    private var isConnected = false
    private var serviceScope = CoroutineScope(Dispatchers.IO)
    private lateinit var sharedPrefs: SharedPreferences
    private var wakeLock: PowerManager.WakeLock? = null

    // BLE UUIDs
    private val serviceUUID = UUID.fromString("12345678-1234-1234-1234-123456789abc")
    private val characteristicUUID = UUID.fromString("abcd1234-5678-90ab-cdef-123456789abc")

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    Log.d(TAG, "✅ Connected to GATT server")
                    isConnected = true
                    
                    // Clear buffer on new connection
                    packetBuffer.setLength(0)
                    
                    // 🔥 Request larger MTU. Failover to service discovery if request fails to start.
                    Log.d(TAG, "📏 Requesting 512 byte MTU...")
                    if (!gatt.requestMtu(512)) {
                        Log.e(TAG, "❌ MTU request failed to start, discovering services immediately")
                        gatt.discoverServices()
                    }
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    Log.d(TAG, "❌ Disconnected from GATT server")
                    isConnected = false
                    
                    // Clear buffer on disconnect
                    packetBuffer.setLength(0)
                    
                    // Notify Flutter of disconnection
                    MainActivity.eventSink?.success(mapOf(
                        "type" to "connection_status",
                        "data" to mapOf("connected" to false)
                    ))
                    
                    // Send broadcast for cross-process communication
                    sendBroadcast(Intent(ACTION_CONNECTION_STATUS).apply {
                        putExtra("connected", false)
                    })
                    
                    attemptReconnect()
                }
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            Log.d(TAG, "📏 MTU updated to $mtu (Status: $status)")
            
            // After MTU is set, discover services
            gatt.discoverServices()
            
            // Notify Flutter of connection (we do it here now to ensure MTU is ready)
            MainActivity.eventSink?.success(mapOf(
                "type" to "connection_status",
                "data" to mapOf("connected" to true)
            ))
            
            // Send broadcast for cross-process communication
            sendBroadcast(Intent(ACTION_CONNECTION_STATUS).apply {
                putExtra("connected", true)
            })
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                val service = gatt.getService(serviceUUID)
                service?.getCharacteristic(characteristicUUID)?.let { characteristic ->
                    gatt.setCharacteristicNotification(characteristic, true)
                    
                    // Write to CCCD descriptor to enable notifications
                    val descriptor = characteristic.getDescriptor(
                        UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
                    )
                    descriptor?.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    gatt.writeDescriptor(descriptor)
                    
                    Log.d(TAG, "📡 Subscribed to characteristic notifications")
                }
            }
        }

        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            val data = characteristic.value
            processHealthData(data)
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "🚀 Creating Background BLE Service")
        sharedPrefs = getSharedPreferences("health_data", Context.MODE_PRIVATE)
        initializeBluetooth()
        createNotificationChannel()
        acquireWakeLock()
        
        // Mark service as running
        sharedPrefs.edit().putBoolean("service_running", true).apply()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "📞 onStartCommand called")
        
        // 🔥 Check if app was updated - if so, stop this outdated service instance
        val currentVersionCode = getAppVersionCode()
        val savedVersionCode = sharedPrefs.getLong("service_version_code", -1L)
        
        if (savedVersionCode != -1L && savedVersionCode != currentVersionCode) {
            Log.d(TAG, "⚠️ App was updated (old: $savedVersionCode, new: $currentVersionCode) - stopping outdated service")
            // Clear the saved version to prevent restart loops
            sharedPrefs.edit().putLong("service_version_code", currentVersionCode).apply()
            sharedPrefs.edit().putBoolean("service_running", false).apply()
            cleanup()
            stopSelf()
            return START_NOT_STICKY // Don't restart this outdated instance
        }
        
        // Save current version code
        sharedPrefs.edit().putLong("service_version_code", currentVersionCode).apply()
        
        // Start foreground service
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService()
        }
        
        // Only connect if not already connected
        if (!isConnected && bluetoothGatt == null) {
            Log.d(TAG, "🔌 Not connected, attempting to connect...")
            connectToLastDevice()
        } else {
            Log.d(TAG, "✅ Already connected or connection in progress, skipping...")
        }
        
        // Return START_STICKY to restart service if killed
        return START_STICKY
    }
    
    private fun getAppVersionCode(): Long {
        return try {
            val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(packageName, android.content.pm.PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageInfo.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                packageInfo.versionCode.toLong()
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error getting app version: ${e.message}")
            -1L
        }
    }

    // 🔥 CRITICAL: Prevents service from being stopped when app is swiped away
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.d(TAG, "⚠️ App swiped away, but service continues running...")
        
        // Restart the service immediately
        val restartServiceIntent = Intent(applicationContext, this::class.java).also {
            it.setPackage(packageName)
        }
        val restartServicePendingIntent = PendingIntent.getService(
            this,
            1,
            restartServiceIntent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val alarmService = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmService.set(
            AlarmManager.ELAPSED_REALTIME,
            SystemClock.elapsedRealtime() + 1000,
            restartServicePendingIntent
        )
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "🛑 Destroying Background BLE Service")
        
        // Mark service as not running
        sharedPrefs.edit().putBoolean("service_running", false).apply()
        
        cleanup()
    }

    private fun initializeBluetooth() {
        bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager.adapter
    }

    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "ZyoraApp::BackgroundBLEWakeLock"
            )
            wakeLock?.acquire()
            Log.d(TAG, "🔋 WakeLock acquired for persistent BLE scanning")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to acquire WakeLock: ${e.message}")
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let {
                if (it.isHeld) {
                    it.release()
                    Log.d(TAG, "🔋 WakeLock released")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error releasing WakeLock: ${e.message}")
        }
    }

    private fun startForegroundService() {
        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Zyora Health Monitor",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Monitoring health data in background"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Zyora Health Monitor")
            .setContentText("Monitoring health data continuously")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }

    private fun connectToLastDevice() {
        val deviceAddress = sharedPrefs.getString("last_device_address", null)
        if (deviceAddress != null && bluetoothAdapter.isEnabled) {
            try {
                val device = bluetoothAdapter.getRemoteDevice(deviceAddress)
                // 🔥 CRITICAL: Use autoConnect = true for persistent reconnection
                bluetoothGatt = device.connectGatt(this, true, gattCallback)
                Log.d(TAG, "🔌 Attempting to connect to: $deviceAddress (autoConnect enabled)")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Connection error: ${e.message}")
                attemptReconnect()
            }
        } else {
            Log.e(TAG, "❌ No saved device or Bluetooth off")
            attemptReconnect()
        }
    }

    private var packetBuffer = StringBuilder()

    private fun processHealthData(data: ByteArray) {
        try {
            val chunk = String(data).trim().filter { it.code in 32..126 }
            if (chunk.isEmpty()) return
            
            packetBuffer.append(chunk)
            var accumulated = packetBuffer.toString()
            
            // 🔄 Robust Frame Extraction: Handle concatenated or partial JSONs
            while (accumulated.contains("{") && accumulated.contains("}")) {
                val start = accumulated.indexOf("{")
                val end = accumulated.indexOf("}") + 1
                
                if (end > start) {
                    val frame = accumulated.substring(start, end)
                    Log.d(TAG, "📊 Processing frame: $frame")
                    
                    val healthData = parseHealthData(frame)
                    if (healthData != null) {
                        saveHealthData(healthData)
                        
                        // Notify Flutter via EventChannel
                        try {
                            MainActivity.eventSink?.success(mapOf(
                                "type" to "health_data_received",
                                "data" to healthData
                            ))
                        } catch (e: Exception) {}
                        
                        // Send broadcast for cross-process
                        sendBroadcast(Intent(ACTION_HEALTH_DATA).apply {
                            putExtra("data", JSONObject(healthData).toString())
                        })
                    }
                    
                    // Remove processed frame from buffer
                    accumulated = accumulated.substring(end)
                    packetBuffer.setLength(0)
                    packetBuffer.append(accumulated)
                } else {
                    // Nested or malformed brackets scenario - discard garbage before '{'
                    accumulated = accumulated.substring(start)
                    packetBuffer.setLength(0)
                    packetBuffer.append(accumulated)
                    break 
                }
            }

            if (packetBuffer.length > 2000) {
                Log.e(TAG, "⚠️ Buffer overflow, clearing")
                packetBuffer.setLength(0)
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error processing packets: ${e.message}")
            packetBuffer.setLength(0)
        }
    }

    private fun parseHealthData(dataString: String): Map<String, Any>? {
        return try {
            val json = JSONObject(dataString)

            // 📢 Handle "Please wear your band" notification from ESP32
            if (json.has("message") && json.optString("message") == "Please wear your band") {
                Log.d(TAG, "📢 Received wear band notification from ESP32")
                showWearBandNotification()
                
                // Also notify Flutter via EventChannel if app is in foreground
                try {
                    MainActivity.eventSink?.success(mapOf(
                        "type" to "notification_received",
                        "data" to mapOf("message" to "Please wear your band")
                    ))
                } catch (e: Exception) {
                    Log.d(TAG, "📱 Flutter EventSink not available (app likely in background/killed)")
                }
                
                return null // This frame processed as notification, skip health data processing
            }
            
            // Require at least heartRate to be present to consider it valid health data
            if (!json.has("heartRate")) {
                return null
            }

            val isPending = json.optBoolean("pending", false)
            val cycleCount = json.optInt("cycleCount", 0)
            
            // Calculate timestamp: if pending, subtract (cycleCount * 5 minutes)
            val baseTimestamp = System.currentTimeMillis()
            val correctedTimestamp = if (isPending) {
                baseTimestamp - (cycleCount.toLong() * 5 * 60 * 1000)
            } else {
                baseTimestamp
            }

            mapOf(
                "heartRate" to json.optInt("heartRate", 72),
                "steps" to json.optInt("steps", 0),
                "spo2" to json.optInt("spo2", 98),
                "calories" to json.optInt("calories", 0),
                "sleep" to json.optDouble("sleep", 7.0),
                "recovery" to 0, 
                "stress" to json.optInt("stress", 30),
                "rhr" to 60,
                "hrv" to 45,
                "bodyTemperature" to json.optDouble("bodyTemperature", 36.5),
                "breathingRate" to json.optInt("breathingRate", 16),
                "timestamp" to correctedTimestamp,
                "pending" to isPending
            )

        } catch (e: Exception) {
            Log.e(TAG, "❌ JSON parse error for string: $dataString")
            null // Return null to prevent saving junk default values
        }
    }

    private fun getDefaultHealthData(): Map<String, Any> {
        return mapOf(
            "heartRate" to 72,
            "steps" to 0,
            "spo2" to 98,
            "calories" to 0,
            "sleep" to 7.0,
            "recovery" to 85,
            "stress" to 30,
            "rhr" to 60, // IGNORE RHR
            "hrv" to 45, // IGNORE HRV
            "bodyTemperature" to 36.5,
            "breathingRate" to 16,
            "timestamp" to System.currentTimeMillis()
        )
    }

    private fun saveHealthData(healthData: Map<String, Any>) {
        try {
            val jsonData = JSONObject(healthData).toString()
            val timestamp = System.currentTimeMillis()
            
            // Save latest data
            sharedPrefs.edit().apply {
                putString("last_health_data", jsonData)
                putLong("last_update", timestamp)
                apply()
            }
            
            // Also append to history (store last 2000 data points to cover ~16 hours)
            val historyKey = "health_data_history"
            val existingHistory = sharedPrefs.getString(historyKey, "[]")
            val historyArray = org.json.JSONArray(existingHistory)
            
            historyArray.put(JSONObject(healthData))
            
            // Keep only last 2000 entries (covers approx 16-17 hours at 30s intervals)
            val trimmedHistory = if (historyArray.length() > 2000) {
                org.json.JSONArray().apply {
                    for (i in (historyArray.length() - 2000) until historyArray.length()) {
                        put(historyArray.get(i))
                    }
                }
            } else {
                historyArray
            }
            
            sharedPrefs.edit().putString(historyKey, trimmedHistory.toString()).apply()
            
            Log.d(TAG, "💾 Data saved successfully (HR: ${healthData["heartRate"]})")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Save error: ${e.message}")
        }
    }

    private fun showWearBandNotification() {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        // Use a different channel or same channel? Let's use a high priority channel for alerts.
        val ALERT_CHANNEL_ID = "ZyoraAlertChannel"
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                ALERT_CHANNEL_ID,
                "Zyora Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Emergency or high-priority health alerts"
                enableLights(true)
                lightColor = android.graphics.Color.RED
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(channel)
        }

        // Create an intent to open the app when notification is clicked
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setContentTitle("Band Reminder")
            .setContentText("Please wear your band")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        notificationManager.notify(101, notification)
    }

    private fun attemptReconnect() {
        serviceScope.launch {
            delay(15000) // 15 seconds
            if (!isConnected) {
                Log.d(TAG, "🔄 Attempting reconnect...")
                connectToLastDevice()
            }
        }
    }

    private fun cleanup() {
        serviceScope.cancel()
        bluetoothGatt?.disconnect()
        bluetoothGatt?.close()
        bluetoothGatt = null
        releaseWakeLock()
    }
}