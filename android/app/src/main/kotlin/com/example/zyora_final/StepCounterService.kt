package com.example.zyora_final

import android.app.*
import android.content.*
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.*
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import org.json.JSONObject

class StepCounterService : Service(), SensorEventListener {
    companion object {
        const val TAG = "StepCounterService"
        const val CHANNEL_ID = "StepCounterChannel"
        const val NOTIFICATION_ID = 222
        const val ACTION_START_SERVICE = "ACTION_START_SERVICE"
        const val ACTION_STOP_SERVICE = "ACTION_STOP_SERVICE"
        const val ACTION_STEP_DATA = "com.example.zyora_final.STEP_DATA"
    }

    private lateinit var sensorManager: SensorManager
    private var stepCounterSensor: Sensor? = null
    private var serviceScope = CoroutineScope(Dispatchers.IO)
    private lateinit var sharedPrefs: SharedPreferences
    private var wakeLock: PowerManager.WakeLock? = null
    
    private var initialSteps = -1f
    private var currentSteps = 0f

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "🚀 Creating Step Counter Service")
        sharedPrefs = getSharedPreferences("step_data", Context.MODE_PRIVATE)
        
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        stepCounterSensor = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        
        if (stepCounterSensor == null) {
            Log.e(TAG, "❌ Step counter sensor not available!")
        }

        createNotificationChannel()
        acquireWakeLock()
        
        sharedPrefs.edit().putBoolean("service_running", true).apply()
        
        registerSensor()
    }

    private fun registerSensor() {
        stepCounterSensor?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "📞 onStartCommand called")
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService()
        }
        
        return START_STICKY
    }

    private fun startForegroundService() {
        val notification = createNotification(currentSteps.toInt())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Step Counter Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Counting steps in the background"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(steps: Int): Notification {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Zyora Steps")
            .setContentText("Steps today: $steps")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type == Sensor.TYPE_STEP_COUNTER) {
            val totalSteps = event.values[0]
            
            if (initialSteps == -1f) {
                // First event since service started
                // We should ideally load initialSteps from SharedPreferences to persist across service restarts
                // but for simplicity, let's say we count since service start OR since midnight
                initialSteps = sharedPrefs.getFloat("initial_steps", totalSteps)
                if (initialSteps > totalSteps) {
                    // Sensor was reset (reboot)
                    initialSteps = totalSteps
                }
                sharedPrefs.edit().putFloat("initial_steps", initialSteps).apply()
            }
            
            currentSteps = totalSteps - initialSteps
            Log.d(TAG, "👣 SENSOR UPDATE: Total=$totalSteps, Initial=$initialSteps, Current=$currentSteps")
            
            updateNotification(currentSteps.toInt())
            saveStepData(currentSteps.toInt())
            notifyFlutter(currentSteps.toInt())
        } else {
            Log.d(TAG, "❓ Unknown sensor event: ${event?.sensor?.type}")
        }
    }

    private fun updateNotification(steps: Int) {
        val notification = createNotification(steps)
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun saveStepData(steps: Int) {
        sharedPrefs.edit().putInt("current_steps", steps).apply()
    }

    private fun notifyFlutter(steps: Int) {
        serviceScope.launch(Dispatchers.Main) {
            try {
                MainActivity.eventSink?.success(mapOf(
                    "type" to "step_data",
                    "data" to mapOf("steps" to steps)
                ))
            } catch (e: Exception) {
                // Log.e(TAG, "Failed to notify Flutter: ${e.message}")
            }
        }
        
        // Broadcast for other receivers if needed
        val intent = Intent(ACTION_STEP_DATA).apply {
            putExtra("steps", steps)
        }
        sendBroadcast(intent)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.d(TAG, "⚠️ App swiped away, but service continues running...")
        
        val restartServiceIntent = Intent(applicationContext, this::class.java).also {
            it.setPackage(packageName)
        }
        val restartServicePendingIntent = PendingIntent.getService(
            this,
            2,
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

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "🛑 Destroying Step Counter Service")
        sharedPrefs.edit().putBoolean("service_running", false).apply()
        sensorManager.unregisterListener(this)
        releaseWakeLock()
        serviceScope.cancel()
    }

    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "Zyora::StepCounterWakeLock"
            )
            wakeLock?.acquire()
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to acquire WakeLock: ${e.message}")
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let {
                if (it.isHeld) {
                    it.release()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error releasing WakeLock: ${e.message}")
        }
    }
}
