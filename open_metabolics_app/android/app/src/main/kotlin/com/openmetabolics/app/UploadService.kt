package com.openmetabolics.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class UploadService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var hasActiveUploads = false

    inner class LocalBinder : Binder() {
        fun getService(): UploadService = this@UploadService
    }

    companion object {
        private const val NOTIFICATION_ID = 2
        private const val CHANNEL_ID = "upload_channel"
        private const val CHANNEL_NAME = "File Upload"
        private const val WAKE_LOCK_TAG = "OpenMetabolics::UploadWakeLock"

        fun startService(context: Context) {
            val intent = Intent(context, UploadService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopService(context: Context) {
            val intent = Intent(context, UploadService::class.java)
            context.stopService(intent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()

        // Initialize PowerManager and WakeLock
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock =
                powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).apply {
                    setReferenceCounted(false)
                }

        // Start as foreground service with the appropriate type
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                    NOTIFICATION_ID,
                    createNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIFICATION_ID, createNotification())
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Acquire WakeLock when service starts
        if (wakeLock?.isHeld == false) {
            wakeLock?.acquire()
            println("UploadService: WakeLock acquired.")
        }
        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel =
                    NotificationChannel(
                            CHANNEL_ID,
                            CHANNEL_NAME,
                            NotificationManager.IMPORTANCE_LOW
                    )
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE)

        return NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("File Upload")
                .setContentText("Uploading files in background")
                .setSmallIcon(android.R.drawable.ic_menu_upload)
                .setContentIntent(pendingIntent)
                .build()
    }

    override fun onBind(intent: Intent?): IBinder {
        return LocalBinder()
    }

    override fun onDestroy() {
        super.onDestroy()
        // Only release WakeLock if there are no active uploads
        if (wakeLock?.isHeld == true && !hasActiveUploads) {
            wakeLock?.release()
            println("UploadService: WakeLock released.")
        } else if (wakeLock?.isHeld == true) {
            println("UploadService: WakeLock maintained due to active uploads.")
        }
    }

    fun setHasActiveUploads(active: Boolean) {
        hasActiveUploads = active
        println("UploadService: Active uploads state updated to: $active")
    }
}
