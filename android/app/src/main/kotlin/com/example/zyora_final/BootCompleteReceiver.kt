package com.example.zyora_final

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootCompleteReceiver : BroadcastReceiver() {
    companion object {
        const val TAG = "BootCompleteReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, "android.intent.action.QUICKBOOT_POWERON" -> {
                Log.d(TAG, "Device boot completed, starting background service")
                
                // Start the background service on boot
                val bleServiceIntent = Intent(context, BackgroundBLEService::class.java).apply {
                    action = BackgroundBLEService.ACTION_START_SERVICE
                }
                
                // Start the step counter service on boot
                val stepServiceIntent = Intent(context, StepCounterService::class.java).apply {
                    action = StepCounterService.ACTION_START_SERVICE
                }
                
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    context.startForegroundService(bleServiceIntent)
                    context.startForegroundService(stepServiceIntent)
                } else {
                    context.startService(bleServiceIntent)
                    context.startService(stepServiceIntent)
                }
                
                Log.d(TAG, "Background services started after boot")
            }
        }
    }
}