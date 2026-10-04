package me.tanishkyadav.tempo.companion

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

/** One screen: permission checklist, the address and token to type into Tempo, and a test button. */
class MainActivity : Activity() {
    private lateinit var content: LinearLayout
    private lateinit var dnd: DndController
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        dnd = DndController(this)
        val scroll = ScrollView(this)
        content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(24), dp(24), dp(40))
        }
        scroll.addView(content)
        setContentView(scroll)
        scroll.setOnApplyWindowInsetsListener { v, insets ->
            val top: Int
            val bottom: Int
            if (Build.VERSION.SDK_INT >= 30) {
                val bars = insets.getInsets(WindowInsets.Type.systemBars())
                top = bars.top
                bottom = bars.bottom
            } else {
                @Suppress("DEPRECATION")
                top = insets.systemWindowInsetTop
                @Suppress("DEPRECATION")
                bottom = insets.systemWindowInsetBottom
            }
            v.setPadding(0, top, 0, bottom)
            insets
        }
    }

    override fun onResume() {
        super.onResume()
        render()
    }

    private fun render() {
        content.removeAllViews()
        val running = serviceRunning()

        text("Tempo Companion", 28f, bold = true)
        text("Lets the Tempo app on your Mac switch this phone to Do Not Disturb while a focus session runs.", 15f, muted = true)
        gap(20)

        section("1. Allow it")
        check(
            "Do Not Disturb access", dnd.hasAccess(),
            "Required. Android asks you to switch this on in Settings.", "Open settings"
        ) { startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)) }
        check(
            "Notifications", notificationsGranted(),
            "Shows the 'listening' notification Android requires for a background listener.", "Allow"
        ) {
            if (Build.VERSION.SDK_INT >= 33) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
        check(
            "Unrestricted battery use", ignoringBatteryOptimisations(),
            "Recommended. Without it Android can delay the Mac's request while the phone sleeps.", "Allow"
        ) {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
            )
        }
        gap(20)

        section("2. Start listening")
        button(if (running) "Stop listening" else "Start listening", filled = !running) {
            if (running) {
                stopService(Intent(this, ControlService::class.java))
            } else {
                startForegroundService(Intent(this, ControlService::class.java))
            }
            handler.postDelayed({ render() }, 400)
        }
        gap(20)

        section("3. Enter this in Tempo on your Mac")
        val addresses = Prefs.addresses()
        field("Address", addresses.firstOrNull() ?: "No Wi-Fi address found")
        if (addresses.size > 1) text("Other addresses: " + addresses.drop(1).joinToString(", "), 13f, muted = true)
        field("Port", Prefs.PORT.toString())
        field("Token", Prefs.token(this), copy = true)
        button("Generate a new token", filled = false) {
            Prefs.regenerateToken(this)
            toast("New token. Update it in Tempo.")
            render()
        }
        text("Tempo, Settings, Do Not Disturb on your Android phone.", 13f, muted = true)
        gap(20)

        section("Try it")
        button("Silence this phone for 10 seconds", filled = false) {
            if (!dnd.hasAccess()) {
                toast("Grant Do Not Disturb access first.")
            } else {
                dnd.on()
                handler.postDelayed({ dnd.off(); toast("Back to normal.") }, 10_000)
                toast("Do Not Disturb is on for 10 seconds.")
            }
        }
        gap(16)
        text(
            "Do Not Disturb is set to Priority only, so your own allowed contacts and alarms still get through. " +
                "Whatever mode you had before is restored afterwards. Everything stays on your local network.",
            13f, muted = true
        )
    }

    // MARK: Checks

    private fun serviceRunning(): Boolean {
        @Suppress("DEPRECATION")
        return getSystemService(ActivityManager::class.java).getRunningServices(50)
            .any { it.service.className == ControlService::class.java.name }
    }

    private fun notificationsGranted() =
        Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun ignoringBatteryOptimisations() =
        getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName)

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(code, permissions, results)
        render()
    }

    // MARK: Small view helpers

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun text(s: String, size: Float, bold: Boolean = false, muted: Boolean = false): TextView =
        TextView(this).apply {
            this.text = s
            setTextSize(TypedValue.COMPLEX_UNIT_SP, size)
            if (bold) setTypeface(typeface, Typeface.BOLD)
            if (muted) alpha = 0.7f
            setPadding(0, dp(2), 0, dp(2))
            content.addView(this)
        }

    private fun gap(h: Int) {
        content.addView(View(this), ViewGroup.LayoutParams.MATCH_PARENT, dp(h))
    }

    private fun section(s: String) = text(s, 13f, bold = true, muted = true).also { it.isAllCaps = true }

    private fun check(title: String, ok: Boolean, note: String, action: String, onClick: () -> Unit) {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(8), 0, dp(8))
        }
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        col.addView(TextView(this).apply {
            this.text = (if (ok) "✓  " else "○  ") + title
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTypeface(typeface, Typeface.BOLD)
            if (ok) setTextColor(Color.rgb(22, 163, 74))
        })
        col.addView(TextView(this).apply {
            this.text = note
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            alpha = 0.7f
        })
        row.addView(col, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        if (!ok) {
            row.addView(Button(this).apply {
                this.text = action
                isAllCaps = false
                setOnClickListener { onClick() }
            })
        }
        content.addView(row)
    }

    private fun field(label: String, value: String, copy: Boolean = false) {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(10), dp(14), dp(10))
            background = GradientDrawable().apply {
                cornerRadius = dp(10).toFloat()
                setColor(Color.argb(24, 128, 128, 128))
            }
            if (copy) setOnClickListener {
                getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Tempo token", value))
                toast("Token copied")
            }
        }
        box.addView(TextView(this).apply {
            text = label + if (copy) "  (tap to copy)" else ""
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            alpha = 0.7f
        })
        box.addView(TextView(this).apply {
            text = value
            setTextSize(TypedValue.COMPLEX_UNIT_SP, if (copy) 13f else 18f)
            typeface = Typeface.MONOSPACE
            setTextIsSelectable(true)
        })
        content.addView(box, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(6) })
    }

    private fun button(label: String, filled: Boolean, onClick: () -> Unit) {
        content.addView(Button(this).apply {
            text = label
            isAllCaps = false
            if (filled) {
                setTextColor(Color.WHITE)
                background = GradientDrawable().apply {
                    cornerRadius = dp(24).toFloat()
                    setColor(Color.rgb(99, 102, 241))
                }
            }
            setOnClickListener { onClick() }
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(6) })
    }

    private fun toast(s: String) = Toast.makeText(this, s, Toast.LENGTH_SHORT).show()
}
