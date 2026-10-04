package me.tanishkyadav.tempo.companion

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/** Foreground service that listens for the Mac and switches Do Not Disturb. */
class ControlService : Service(), MiniHttpServer.Handler {
    private var server: MiniHttpServer? = null
    private lateinit var dnd: DndController
    private val main = Handler(Looper.getMainLooper())
    private val failsafe = Runnable { dnd.off() }

    override fun onCreate() {
        super.onCreate()
        dnd = DndController(this)
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, "Tempo Companion", NotificationManager.IMPORTANCE_LOW)
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val where = Prefs.addresses().firstOrNull()?.let { "$it:${Prefs.PORT}" } ?: "no network"
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        val notification = Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat)
            .setContentTitle("Tempo Companion is listening")
            .setContentText(where)
            .setOngoing(true)
            .setContentIntent(open)
            .build()
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (_: Exception) {
            stopSelf()
            return START_NOT_STICKY
        }

        if (server == null) {
            val s = MiniHttpServer(Prefs.PORT, { Prefs.token(this) }, this)
            try {
                s.start()
                server = s
            } catch (_: Exception) {
                stopSelf()
                return START_NOT_STICKY
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        server?.stop()
        server = null
        main.removeCallbacks(failsafe)
        dnd.off() // never leave the phone silenced because the listener went away
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // MiniHttpServer.Handler

    override fun status(): MiniHttpServer.Reply = MiniHttpServer.Reply(200, json(true))

    override fun setDnd(on: Boolean, ttlMinutes: Int): MiniHttpServer.Reply {
        if (!dnd.hasAccess()) {
            return MiniHttpServer.Reply(409, """{"ok":false,"error":"dnd_access_denied","dnd_access":false}""")
        }
        main.removeCallbacks(failsafe)
        if (on) {
            dnd.on()
            // If the Mac never says "off" (crash, sleep, Wi-Fi drop) the phone switches itself back.
            main.postDelayed(failsafe, ttlMinutes * 60_000L)
        } else {
            dnd.off()
        }
        return MiniHttpServer.Reply(200, json(true))
    }

    private fun json(ok: Boolean) =
        """{"ok":$ok,"app":"tempo-companion","version":1,"dnd_access":${dnd.hasAccess()},"dnd_active":${dnd.isActive()}}"""

    private companion object {
        const val CHANNEL = "listener"
        const val NOTIFICATION_ID = 1
    }
}
