package me.tanishkyadav.tempo.companion

import android.app.NotificationManager
import android.content.Context

/**
 * Switches the phone's Do Not Disturb. It uses "Priority only", so the user's own DND allow-list
 * (starred contacts, alarms) still applies, and it restores whatever filter was active before.
 */
class DndController(context: Context) {
    private val nm = context.getSystemService(NotificationManager::class.java)
    private val prefs = context.getSharedPreferences("tempo", Context.MODE_PRIVATE)

    fun hasAccess(): Boolean = nm.isNotificationPolicyAccessGranted

    /** True while the phone is in any Do Not Disturb mode. */
    fun isActive(): Boolean = nm.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL

    fun on(): Boolean {
        if (!hasAccess()) return false
        if (!prefs.getBoolean(ARMED, false)) {
            prefs.edit()
                .putInt(PREVIOUS, nm.currentInterruptionFilter)
                .putBoolean(ARMED, true)
                .apply()
        }
        nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
        return true
    }

    fun off() {
        if (!prefs.getBoolean(ARMED, false)) return
        if (hasAccess()) {
            val previous = prefs.getInt(PREVIOUS, NotificationManager.INTERRUPTION_FILTER_ALL)
            nm.setInterruptionFilter(
                if (previous == NotificationManager.INTERRUPTION_FILTER_UNKNOWN) {
                    NotificationManager.INTERRUPTION_FILTER_ALL
                } else {
                    previous
                }
            )
        }
        prefs.edit().putBoolean(ARMED, false).apply()
    }

    private companion object {
        const val ARMED = "dnd_armed"
        const val PREVIOUS = "dnd_previous_filter"
    }
}
