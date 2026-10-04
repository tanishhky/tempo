package me.tanishkyadav.tempo.companion

import android.content.Context
import java.net.Inet4Address
import java.net.NetworkInterface
import java.security.SecureRandom

object Prefs {
    const val PORT = 8765

    fun token(context: Context): String {
        val prefs = context.getSharedPreferences("tempo", Context.MODE_PRIVATE)
        prefs.getString("token", null)?.let { return it }
        return regenerateToken(context)
    }

    fun regenerateToken(context: Context): String {
        val bytes = ByteArray(24).also { SecureRandom().nextBytes(it) }
        val token = bytes.joinToString("") { "%02x".format(it) }
        context.getSharedPreferences("tempo", Context.MODE_PRIVATE).edit().putString("token", token).apply()
        return token
    }

    /** Private IPv4 addresses of this phone, Wi-Fi first. */
    fun addresses(): List<String> {
        val found = mutableListOf<Pair<String, String>>()
        try {
            for (nif in NetworkInterface.getNetworkInterfaces()) {
                if (!nif.isUp || nif.isLoopback) continue
                for (addr in nif.inetAddresses) {
                    if (addr is Inet4Address && addr.isSiteLocalAddress) found += nif.name to addr.hostAddress!!
                }
            }
        } catch (_: Exception) {
        }
        return found.sortedBy { if (it.first.startsWith("wlan")) 0 else 1 }.map { it.second }
    }
}
