/*
 * Copyright (c) 2026 kayb28 and contributors.
 *
 * This file is part of WebLibre
 * (see https://weblibre.eu).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
package eu.weblibre.gecko

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service that keeps the app's process alive while the user is in
 * another app, so open tabs keep their sessions and connections running
 * instead of being frozen with the process — a chat that streams its answers
 * keeps streaming while its site is marked keep-alive.
 *
 * Started and stopped from Dart through the `eu.weblibre.gecko/keep_alive`
 * MethodChannel (see [MainActivity]) whenever a keep-alive-marked site starts
 * or stops being open (see keep_alive_service.dart on the Dart side).
 *
 * `dataSync` is the closest matching type for "holds a web session open".
 * Note Android 15 caps a `dataSync` foreground service at six hours; after
 * that the system ends it quietly, and the app starts it again on the next
 * relevant change while it is in use.
 */
class KeepAliveService : Service() {

    companion object {
        private const val TAG = "KeepAliveService"
        private const val NOTIFICATION_ID = 1002
        private const val CHANNEL_ID = "keep_alive_service"

        const val ACTION_START = "eu.weblibre.gecko.keep_alive.START"
        const val ACTION_STOP = "eu.weblibre.gecko.keep_alive.STOP"

        /**
         * Whether the service is currently in the foreground state, as the
         * `isActive` channel method answers. Process-local by design: the
         * service runs in the app's own process, so the flag is born and dies
         * with exactly the process whose liveness it describes.
         */
        @Volatile
        var isRunning: Boolean = false
            private set
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startInForeground()

            ACTION_STOP -> {
                isRunning = false
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }

            else -> {
                // Only a sticky restart delivers a null intent, and we never
                // return START_STICKY; anything else unexpected stands down.
                Log.w(TAG, "Unexpected start with action ${intent?.action}, stopping")
                isRunning = false
                stopSelf()
            }
        }

        // Explicitly user-driven; never resurrect on its own after a kill.
        return START_NOT_STICKY
    }

    private fun startInForeground() {
        val notification = createNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        isRunning = true
    }

    private fun createNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE)
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("WebLibre")
            .setContentText(
                "Keeping your marked sites active while you use other apps"
            )
            .setSmallIcon(R.drawable.ic_bg_service_small)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Background sessions",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description =
                    "Shown while a marked site keeps its session running in the background"
                setShowBadge(false)
            }

            val notificationManager =
                getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Service destroyed")
        isRunning = false
    }
}
