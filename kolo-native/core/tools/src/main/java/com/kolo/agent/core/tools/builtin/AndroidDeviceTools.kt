package com.kolo.agent.core.tools.builtin

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.ContactsContract
import com.kolo.agent.core.model.ToolExecutionResult
import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.tools.KoloTool
import com.kolo.agent.core.tools.ToolExecutionContext
import com.kolo.agent.core.tools.ToolPlatform
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

private fun ToolExecutionContext.requireAndroidContext(): Context? = androidContext

class DeviceInfoTool : KoloTool() {
    override val name = "device_info"
    override val description = "Get Android device model, OS version, and runtime app context information."
    override val parameterSchema = """{"type":"object","properties":{},"required":[]}"""
    override val permission = ToolPermission.safe
    override val platform = ToolPlatform.ANDROID

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val app = context.requireAndroidContext()
        return ToolExecutionResult.ok(buildString {
            appendLine("Manufacturer: ${Build.MANUFACTURER}")
            appendLine("Model: ${Build.MODEL}")
            appendLine("Device: ${Build.DEVICE}")
            appendLine("Android: ${Build.VERSION.RELEASE} API ${Build.VERSION.SDK_INT}")
            appendLine("Package: ${app?.packageName ?: "unknown"}")
        })
    }
}

class ClipboardReadTool : KoloTool() {
    override val name = "clipboard_read"
    override val description = "Read plain text from the Android clipboard."
    override val parameterSchema = """{"type":"object","properties":{},"required":[]}"""
    override val permission = ToolPermission.sensitive
    override val platform = ToolPlatform.ANDROID

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val app = context.requireAndroidContext() ?: return ToolExecutionResult.err("Android context unavailable")
        val clipboard = app.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val text = clipboard.primaryClip?.getItemAt(0)?.coerceToText(app)?.toString().orEmpty()
        return if (text.isBlank()) ToolExecutionResult.ok("Clipboard is empty.")
        else ToolExecutionResult.ok(text.take(10000))
    }
}

class ClipboardWriteTool : KoloTool() {
    override val name = "clipboard_write"
    override val description = "Write plain text to the Android clipboard."
    override val parameterSchema = """{"type":"object","properties":{"text":{"type":"string","description":"Text to copy to clipboard"}},"required":["text"]}"""
    override val permission = ToolPermission.sensitive
    override val platform = ToolPlatform.ANDROID

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val text = params["text"] ?: return ToolExecutionResult.err("Missing text parameter")
        val app = context.requireAndroidContext() ?: return ToolExecutionResult.err("Android context unavailable")
        val clipboard = app.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("Kolo", text))
        return ToolExecutionResult.ok("Copied ${text.length} characters to clipboard.")
    }
}

class ConnectivityTool : KoloTool() {
    override val name = "connectivity"
    override val description = "Check current network connectivity and transport type."
    override val parameterSchema = """{"type":"object","properties":{},"required":[]}"""
    override val permission = ToolPermission.safe
    override val platform = ToolPlatform.ANDROID

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val app = context.requireAndroidContext() ?: return ToolExecutionResult.err("Android context unavailable")
        val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = cm.activeNetwork ?: return ToolExecutionResult.ok("Offline: no active network.")
        val caps = cm.getNetworkCapabilities(network) ?: return ToolExecutionResult.ok("Network active, capabilities unknown.")
        val transports = buildList {
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) add("wifi")
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) add("cellular")
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) add("ethernet")
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) add("vpn")
        }
        val validated = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        return ToolExecutionResult.ok("Online: $validated\nTransports: ${transports.ifEmpty { listOf("unknown") }.joinToString()}")
    }
}

class BatteryInfoTool : KoloTool() {
    override val name = "battery_info"
    override val description = "Get battery percentage, charging status, and power source."
    override val parameterSchema = """{"type":"object","properties":{},"required":[]}"""
    override val permission = ToolPermission.safe
    override val platform = ToolPlatform.ANDROID

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val app = context.requireAndroidContext() ?: return ToolExecutionResult.err("Android context unavailable")
        val status = app.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            ?: return ToolExecutionResult.err("Battery status unavailable")
        val level = status.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = status.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        val percent = if (level >= 0 && scale > 0) level * 100 / scale else -1
        val plugged = status.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
        val charging = status.getIntExtra(BatteryManager.EXTRA_STATUS, -1) in setOf(
            BatteryManager.BATTERY_STATUS_CHARGING,
            BatteryManager.BATTERY_STATUS_FULL,
        )
        val source = when (plugged) {
            BatteryManager.BATTERY_PLUGGED_USB -> "usb"
            BatteryManager.BATTERY_PLUGGED_AC -> "ac"
            BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"
            else -> "battery"
        }
        return ToolExecutionResult.ok("Battery: ${if (percent >= 0) "$percent%" else "unknown"}\nCharging: $charging\nPower source: $source")
    }
}

class VibrateTool : KoloTool() {
    override val name = "vibrate"
    override val description = "Vibrate the device for a short duration."
    override val parameterSchema = """{"type":"object","properties":{"duration_ms":{"type":"integer","description":"Duration in milliseconds, max 2000"}},"required":[]}"""
    override val permission = ToolPermission.sensitive
    override val platform = ToolPlatform.ANDROID

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val app = context.requireAndroidContext() ?: return ToolExecutionResult.err("Android context unavailable")
        val duration = (params["duration_ms"]?.toLongOrNull() ?: 250L).coerceIn(1L, 2000L)
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (app.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            app.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        vibrator.vibrate(VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE))
        return ToolExecutionResult.ok("Vibrated for ${duration}ms.")
    }
}

class ListInstalledAppsTool : KoloTool() {
    override val name = "list_installed_apps"
    override val description = "List launchable apps visible to Kolo with labels and package names."
    override val parameterSchema = """{"type":"object","properties":{"query":{"type":"string","description":"Optional app-name filter"},"limit":{"type":"integer","description":"Maximum results, default 50"}},"required":[]}"""
    override val permission = ToolPermission.sensitive
    override val platform = ToolPlatform.ANDROID

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val app = context.requireAndroidContext() ?: return ToolExecutionResult.err("Android context unavailable")
        val pm = app.packageManager
        val query = params["query"].orEmpty().lowercase()
        val limit = (params["limit"]?.toIntOrNull() ?: 50).coerceIn(1, 100)
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val apps = pm.queryIntentActivities(intent, 0)
            .map { info ->
                val label = info.loadLabel(pm).toString()
                label to info.activityInfo.packageName
            }
            .distinctBy { it.second }
            .filter { query.isBlank() || it.first.lowercase().contains(query) || it.second.lowercase().contains(query) }
            .sortedBy { it.first.lowercase() }
            .take(limit)
        if (apps.isEmpty()) return ToolExecutionResult.ok("No launchable apps found.")
        return ToolExecutionResult.ok(apps.joinToString("\n") { "${it.first}: ${it.second}" })
    }
}

class LaunchAppTool : KoloTool() {
    override val name = "launch_app"
    override val description = "Launch an installed Android app by package name."
    override val parameterSchema = """{"type":"object","properties":{"package_name":{"type":"string","description":"Android package name, e.g. com.spotify.music"}},"required":["package_name"]}"""
    override val permission = ToolPermission.dangerous
    override val platform = ToolPlatform.ANDROID

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val packageName = params["package_name"] ?: return ToolExecutionResult.err("Missing package_name parameter")
        val app = context.requireAndroidContext() ?: return ToolExecutionResult.err("Android context unavailable")
        val intent = app.packageManager.getLaunchIntentForPackage(packageName)
            ?: return ToolExecutionResult.err("No launch intent found for $packageName")
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        app.startActivity(intent)
        return ToolExecutionResult.ok("Launched $packageName.")
    }
}

class TimerTool : KoloTool() {
    override val name = "timer"
    override val description = "Start, check, or cancel lightweight in-app timers."
    override val parameterSchema = """{"type":"object","properties":{"action":{"type":"string","enum":["start","check","cancel"]},"seconds":{"type":"integer","description":"Seconds for start action"},"timer_id":{"type":"string","description":"Timer id for check/cancel"}},"required":["action"]}"""
    override val permission = ToolPermission.safe

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        return when (params["action"]?.lowercase()) {
            "start" -> {
                val seconds = (params["seconds"]?.toLongOrNull() ?: 60L).coerceIn(1L, 86_400L)
                val id = UUID.randomUUID().toString().take(8)
                timers[id] = System.currentTimeMillis() + seconds * 1000
                ToolExecutionResult.ok("Started timer $id for ${seconds}s.")
            }
            "check" -> {
                val id = params["timer_id"] ?: return ToolExecutionResult.err("timer_id required")
                val end = timers[id] ?: return ToolExecutionResult.ok("Timer $id has completed or does not exist.")
                val remaining = ((end - System.currentTimeMillis()) / 1000).coerceAtLeast(0)
                if (remaining == 0L) {
                    timers.remove(id)
                    ToolExecutionResult.ok("Timer $id has completed.")
                } else {
                    ToolExecutionResult.ok("Timer $id: ${remaining}s remaining.")
                }
            }
            "cancel" -> {
                val id = params["timer_id"] ?: return ToolExecutionResult.err("timer_id required")
                timers.remove(id)
                ToolExecutionResult.ok("Timer $id cancelled.")
            }
            else -> ToolExecutionResult.err("Unknown action. Use start, check, or cancel.")
        }
    }

    companion object {
        private val timers = ConcurrentHashMap<String, Long>()
    }
}

class ContactsSearchTool : KoloTool() {
    override val name = "contacts_search"
    override val description = "Search device contacts by name, phone number, or email. Returns matching contact details."
    override val parameterSchema = """{"type":"object","properties":{"query":{"type":"string","description":"Name, phone, or email to search"},"limit":{"type":"integer","description":"Max results, default 10"}},"required":["query"]}"""
    override val permission = ToolPermission.sensitive
    override val platform = ToolPlatform.ANDROID

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val app = context.requireAndroidContext() ?: return ToolExecutionResult.err("Android context unavailable")
        if (app.checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
            return ToolExecutionResult.err("Contacts permission is not granted. Enable Contacts permission for Kolo in Android settings.")
        }
        val query = params["query"]?.trim().orEmpty()
        if (query.isBlank()) return ToolExecutionResult.err("Missing query parameter")
        val limit = (params["limit"]?.toIntOrNull() ?: 10).coerceIn(1, 25)
        val projection = arrayOf(
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
            ContactsContract.CommonDataKinds.Phone.NUMBER,
            ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
        )
        val selection = "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ? OR ${ContactsContract.CommonDataKinds.Phone.NUMBER} LIKE ?"
        val args = arrayOf("%$query%", "%$query%")
        val results = linkedMapOf<String, MutableList<String>>()
        app.contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            projection,
            selection,
            args,
            "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC",
        )?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
            val numberIndex = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
            if (nameIndex < 0 || numberIndex < 0) {
                return ToolExecutionResult.err("Contacts provider did not return expected columns.")
            }
            while (cursor.moveToNext() && results.size < limit) {
                val name = cursor.getString(nameIndex).orEmpty().ifBlank { "Unknown" }
                val number = cursor.getString(numberIndex).orEmpty()
                results.getOrPut(name) { mutableListOf() }.add(number)
            }
        }
        if (results.isEmpty()) return ToolExecutionResult.ok("No contacts found for '$query'.")
        return ToolExecutionResult.ok(results.entries.joinToString("\n") { (name, phones) ->
            "$name: ${phones.distinct().joinToString(", ")}"
        })
    }
}

class LocationTool : KoloTool() {
    override val name = "location"
    override val description = "Get the device's last known location coordinates and provider details."
    override val parameterSchema = """{"type":"object","properties":{},"required":[]}"""
    override val permission = ToolPermission.sensitive
    override val platform = ToolPlatform.ANDROID

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val app = context.requireAndroidContext() ?: return ToolExecutionResult.err("Android context unavailable")
        val hasFine = app.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val hasCoarse = app.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!hasFine && !hasCoarse) {
            return ToolExecutionResult.err("Location permission is not granted. Enable Location permission for Kolo in Android settings.")
        }
        val manager = app.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val providers = manager.getProviders(true)
        val best = providers
            .mapNotNull { provider ->
                try {
                    @Suppress("MissingPermission")
                    manager.getLastKnownLocation(provider)
                } catch (_: SecurityException) {
                    null
                }
            }
            .maxByOrNull { it.time }
            ?: return ToolExecutionResult.err("No last known location is available yet. Open Maps or enable GPS, then try again.")

        return ToolExecutionResult.ok(
            buildString {
                appendLine("Latitude: ${best.latitude}")
                appendLine("Longitude: ${best.longitude}")
                appendLine("Accuracy: ${best.accuracy}m")
                appendLine("Provider: ${best.provider}")
                appendLine("Timestamp: ${java.util.Date(best.time)}")
            },
            mapOf(
                "latitude" to best.latitude.toString(),
                "longitude" to best.longitude.toString(),
                "accuracy" to best.accuracy.toString(),
            ),
        )
    }
}
