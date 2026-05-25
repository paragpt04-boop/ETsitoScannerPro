package com.jsus.jsus_iptv

import android.app.*
import android.content.Intent
import android.os.IBinder
import android.os.PowerManager

class ScanService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    override fun onCreate() {
        super.onCreate()
        val chan = NotificationChannel("scan", "JsusIPTV Scanner", NotificationManager.IMPORTANCE_LOW)
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(chan)
        val notif = Notification.Builder(this, "scan")
            .setContentTitle("JsusIPTV Scanner")
            .setContentText("Escaneando en segundo plano...")
            .setSmallIcon(android.R.drawable.ic_menu_search)
            .setOngoing(true).build()
        startForeground(1, notif)
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "JsusIPTV::WakeLock")
        wakeLock?.acquire(12 * 60 * 60 * 1000L)
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int) = START_STICKY
    override fun onDestroy() { wakeLock?.release(); super.onDestroy() }
    override fun onBind(intent: Intent?): IBinder? = null
}
