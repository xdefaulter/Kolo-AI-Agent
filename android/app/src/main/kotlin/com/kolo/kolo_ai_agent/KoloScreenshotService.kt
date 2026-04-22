package com.kolo.kolo_ai_agent

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.Log

/**
 * Lightweight foreground service that just keeps the app alive with a notification.
 * Screenshots are handled by KoloAccessibilityService.takeScreenshot() — no MediaProjection needed.
 * Overlays are managed by KoloOverlayManager.
 */
class KoloScreenshotService : Service() {

    companion object {
        private const val TAG = "KoloService"
        const val CHANNEL_ID = "kolo_agent_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "com.kolo.START_FOREGROUND"
        const val ACTION_STOP = "com.kolo.STOP_FOREGROUND"
        const val OVERLAY_PERMISSION_REQUEST = 2001

        @Volatile var instance: KoloScreenshotService? = null
            private set

        fun start(context: Context) {
            val intent = Intent(context, KoloScreenshotService::class.java)
            intent.action = ACTION_START
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, KoloScreenshotService::class.java)
            intent.action = ACTION_STOP
            context.startService(intent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                startForegroundWithNotification()
                // Show overlays (border + stop button) when service starts
                // Only if overlay permission is granted
                if (KoloOverlayManager.canDrawOverlays(this)) {
                    KoloOverlayManager.show(this)
                } else {
                    Log.w(TAG, "SYSTEM_ALERT_WINDOW not granted — skipping overlays")
                }
            }
            ACTION_STOP -> {
                KoloOverlayManager.hide()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        KoloOverlayManager.hide()
        instance = null
        super.onDestroy()
    }

    // ── Foreground notification ──

    /**
     * Start foreground with proper API-level handling:
     * - API 34+: must specify foregroundServiceType
     * - API 33+: should have POST_NOTIFICATIONS (service still starts without it but
     *   notification is silently dropped; the service will still survive)
     */
    private fun startForegroundWithNotification() {
        val notification = buildNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+ (API 34): must declare foregroundServiceType
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Kolo AI Agent",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Kolo AI Agent is running in the background"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val stopIntent = Intent(this, KoloScreenshotService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("Kolo AI Agent")
                .setContentText("Phone controller active — tap to stop")
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentIntent(stopPending)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("Kolo AI Agent")
                .setContentText("Phone controller active")
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentIntent(stopPending)
                .setOngoing(true)
                .build()
        }
    }
}