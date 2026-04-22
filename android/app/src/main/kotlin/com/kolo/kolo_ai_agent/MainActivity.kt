package com.kolo.kolo_ai_agent

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.util.Base64
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall

class MainActivity : FlutterActivity() {

    private val TAG = "KoloMain"
    private val CHANNEL = "com.kolo.ai/phone_control"
    private val OVERLAY_PERMISSION_REQUEST = 2001
    private val NOTIFICATION_PERMISSION_REQUEST = 2002

    private var pendingControllerStart: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        KoloAccessibilityService.methodChannel = channel

        // STOP button callback — stops the whole controller
        KoloOverlayManager.onStopClicked = {
            KoloScreenshotService.stop(this)
            try {
                channel.invokeMethod("controller_stopped", null)
            } catch (_: Exception) {}
        }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // ── Check if accessibility service is enabled ──
                "isAccessibilityEnabled" -> {
                    val enabled = isAccessibilityEnabled()
                    result.success(enabled)
                }

                // ── Open accessibility settings ──
                "openAccessibilitySettings" -> {
                    try {
                        val intent = Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }

                // ── Check if overlay permission is granted ──
                "isOverlayPermissionGranted" -> {
                    result.success(KoloOverlayManager.canDrawOverlays(this))
                }

                // ── Request overlay permission ──
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(
                            android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            android.net.Uri.parse("package:$packageName")
                        )
                        startActivityForResult(intent, OVERLAY_PERMISSION_REQUEST)
                        pendingControllerStart = result
                    } else {
                        result.success(true) // Pre-M always granted
                    }
                }

                // ── Request notification permission (Android 13+) ──
                "requestNotificationPermission" -> {
                    // FlutterActivity extends Activity (not ComponentActivity),
                    // so registerForActivityResult isn't easily available.
                    // On API 33+, the foreground service still starts without this permission —
                    // notifications just won't show. The user can grant it from app settings.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        try {
                            val intent = Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            intent.putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, packageName)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(false) // Can't auto-verify; user must grant manually
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(true)
                    }
                }

                // ── Screen reading ──
                "readScreen" -> {
                    val service = KoloAccessibilityService.instance
                    if (service == null) {
                        result.error("NO_SERVICE", "Accessibility service not running", null)
                    } else {
                        try {
                            val tree = service.readScreenTree()
                            result.success(tree)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                }

                // ── Tap at coordinates ──
                "tap" -> {
                    val service = KoloAccessibilityService.instance
                    if (service == null) {
                        result.error("NO_SERVICE", "Accessibility service not running", null)
                    } else {
                        val x = call.argument<Double>("x")?.toFloat() ?: 0f
                        val y = call.argument<Double>("y")?.toFloat() ?: 0f
                        service.tap(x, y) { success ->
                            runOnUiThread { result.success(success) }
                        }
                    }
                }

                // ── Swipe ──
                "swipe" -> {
                    val service = KoloAccessibilityService.instance
                    if (service == null) {
                        result.error("NO_SERVICE", "Accessibility service not running", null)
                    } else {
                        val startX = call.argument<Double>("startX")?.toFloat() ?: 0f
                        val startY = call.argument<Double>("startY")?.toFloat() ?: 0f
                        val endX = call.argument<Double>("endX")?.toFloat() ?: 0f
                        val endY = call.argument<Double>("endY")?.toFloat() ?: 0f
                        val duration = call.argument<Int>("duration")?.toLong() ?: 300L
                        service.swipe(startX, startY, endX, endY, duration) { success ->
                            runOnUiThread { result.success(success) }
                        }
                    }
                }

                // ── Long press ──
                "longPress" -> {
                    val service = KoloAccessibilityService.instance
                    if (service == null) {
                        result.error("NO_SERVICE", "Accessibility service not running", null)
                    } else {
                        val x = call.argument<Double>("x")?.toFloat() ?: 0f
                        val y = call.argument<Double>("y")?.toFloat() ?: 0f
                        val duration = call.argument<Int>("duration")?.toLong() ?: 500L
                        service.longPress(x, y, duration) { success ->
                            runOnUiThread { result.success(success) }
                        }
                    }
                }

                // ── Type text ──
                "typeText" -> {
                    val service = KoloAccessibilityService.instance
                    if (service == null) {
                        result.error("NO_SERVICE", "Accessibility service not running", null)
                    } else {
                        val text = call.argument<String>("text") ?: ""
                        service.typeText(text) { success ->
                            runOnUiThread { result.success(success) }
                        }
                    }
                }

                // ── Press key ──
                "pressKey" -> {
                    val service = KoloAccessibilityService.instance
                    if (service == null) {
                        result.error("NO_SERVICE", "Accessibility service not running", null)
                    } else {
                        val key = call.argument<String>("key") ?: ""
                        when (key) {
                            "back" -> service.pressBack { runOnUiThread { result.success(it) } }
                            "home" -> service.pressHome { runOnUiThread { result.success(it) } }
                            "recents" -> service.pressRecents { runOnUiThread { result.success(it) } }
                            "notifications" -> service.pressNotifications { runOnUiThread { result.success(it) } }
                            "quick_settings" -> service.pressQuickSettings { runOnUiThread { result.success(it) } }
                            "power_dialog" -> service.pressPowerDialog { runOnUiThread { result.success(it) } }
                            "lock_screen" -> service.pressLockScreen { runOnUiThread { result.success(it) } }
                            "enter" -> service.pressEnter { runOnUiThread { result.success(it) } }
                            else -> result.error("UNKNOWN_KEY", "Unknown key: $key", null)
                        }
                    }
                }

                // ── Scroll ──
                "scroll" -> {
                    val service = KoloAccessibilityService.instance
                    if (service == null) {
                        result.error("NO_SERVICE", "Accessibility service not running", null)
                    } else {
                        val direction = call.argument<String>("direction") ?: "down"
                        service.scroll(direction) { success ->
                            runOnUiThread { result.success(success) }
                        }
                    }
                }

                // ── Click by text ──
                "clickByText" -> {
                    val service = KoloAccessibilityService.instance
                    if (service == null) {
                        result.error("NO_SERVICE", "Accessibility service not running", null)
                    } else {
                        val text = call.argument<String>("text") ?: ""
                        service.clickByText(text) { success ->
                            runOnUiThread { result.success(success) }
                        }
                    }
                }

                // ── Click by viewId ──
                "clickByViewId" -> {
                    val service = KoloAccessibilityService.instance
                    if (service == null) {
                        result.error("NO_SERVICE", "Accessibility service not running", null)
                    } else {
                        val viewId = call.argument<String>("viewId") ?: ""
                        service.clickByViewId(viewId) { success ->
                            runOnUiThread { result.success(success) }
                        }
                    }
                }

                // ── Screenshot (via AccessibilityService.takeScreenshot, no MediaProjection) ──
                "takeScreenshot" -> {
                    val service = KoloAccessibilityService.instance
                    if (service == null) {
                        result.error("NO_SERVICE", "Accessibility service not running", null)
                    } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                        result.error("UNSUPPORTED", "Screenshots require Android 11+ (API 30)", null)
                    } else {
                        service.takeScreenshot { jpegBytes ->
                            if (jpegBytes != null) {
                                val base64 = Base64.encodeToString(jpegBytes, Base64.NO_WRAP)
                                runOnUiThread { result.success(base64) }
                            } else {
                                runOnUiThread { result.error("CAPTURE_FAILED", "Failed to capture screenshot", null) }
                            }
                        }
                    }
                }

                // ── Start controller (foreground service + overlays — NO MediaProjection) ──
                "startController" -> {
                    // Check accessibility first
                    val a11yEnabled = isAccessibilityEnabled()
                    if (!a11yEnabled) {
                        val intent = Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.error("NO_ACCESSIBILITY", "Accessibility service not enabled. Opened settings — enable Kolo AI Agent, then try phone_start again.", null)
                    } else if (!KoloOverlayManager.canDrawOverlays(this)) {
                        // Need overlay permission — open settings to let user grant it
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(
                                android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                android.net.Uri.parse("package:$packageName")
                            )
                            startActivityForResult(intent, OVERLAY_PERMISSION_REQUEST)
                            pendingControllerStart = result
                        } else {
                            // Pre-M: overlay always granted
                            KoloScreenshotService.start(this)
                            result.success(true)
                        }
                    } else {
                        // Both permissions granted — start!
                        KoloScreenshotService.start(this)
                        result.success(true)
                    }
                }

                // ── Stop controller ──
                "stopController" -> {
                    KoloScreenshotService.stop(this)
                    result.success(true)
                }

                // ── Show action overlay text ──
                "showAction" -> {
                    val text = call.argument<String>("text") ?: ""
                    KoloOverlayManager.showActionText(text)
                    result.success(true)
                }

                // ── Phone control: start persistent mode ──
                "phoneControlStart" -> {
                    val task = call.argument<String>("task") ?: "Controlling phone"
                    KoloOverlayManager.phoneControlStart(this, task)
                    result.success(true)
                }

                // ── Phone control: end persistent mode ──
                "phoneControlDone" -> {
                    val summary = call.argument<String>("summary") ?: ""
                    KoloOverlayManager.phoneControlDone(summary)
                    result.success(true)
                }

                // ── Phone control: update status text ──
                "phoneControlStatus" -> {
                    val status = call.argument<String>("status") ?: ""
                    KoloOverlayManager.phoneControlStatus(status)
                    result.success(true)
                }

                // ── Launch app by package name ──
                "launchApp" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    if (packageName.isEmpty()) {
                        result.error("INVALID", "packageName is required", null)
                    } else {
                        try {
                            val pm = packageManager
                            val intent = pm.getLaunchIntentForPackage(packageName)
                            if (intent == null) {
                                result.error("APP_NOT_FOUND", "App not installed: $packageName. Use listInstalledApps to find the correct package name.", null)
                            } else {
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                val appName = try {
                                    val appInfo = pm.getApplicationInfo(packageName, 0)
                                    pm.getApplicationLabel(appInfo).toString()
                                } catch (_: Exception) { packageName }
                                startActivity(intent)
                                result.success(mapOf("success" to true, "appName" to appName, "packageName" to packageName))
                            }
                        } catch (e: Exception) {
                            result.error("LAUNCH_FAILED", "Failed to launch $packageName: ${e.message}", null)
                        }
                    }
                }

                // ── List installed apps ──
                "listInstalledApps" -> {
                    val query = (call.argument<String>("query") ?: "").lowercase()
                    try {
                        val pm = packageManager
                        val apps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
                        val results = mutableListOf<Map<String, String>>()
                        for (app in apps) {
                            // Skip system-only apps that have no launch intent
                            val launchIntent = pm.getLaunchIntentForPackage(app.packageName)
                            if (launchIntent == null) continue

                            val label = try {
                                pm.getApplicationLabel(app).toString()
                            } catch (_: Exception) { app.packageName }

                            // Filter by query if provided
                            if (query.isNotEmpty()) {
                                if (label.lowercase().contains(query) || app.packageName.lowercase().contains(query)) {
                                    results.add(mapOf("appName" to label, "packageName" to app.packageName))
                                }
                            } else {
                                results.add(mapOf("appName" to label, "packageName" to app.packageName))
                            }
                        }
                        // Sort by name
                        results.sortBy { it["appName"]?.lowercase() }
                        val json = org.json.JSONArray().apply {
                            for (r in results) {
                                val obj = org.json.JSONObject()
                                obj.put("appName", r["appName"])
                                obj.put("packageName", r["packageName"])
                                put(obj)
                            }
                        }
                        result.success(json.toString())
                    } catch (e: Exception) {
                        result.error("LIST_FAILED", "Failed to list apps: ${e.message}", null)
                    }
                }

                // ── Device info ──
                "deviceInfo" -> {
                    try {
                        val displayMetrics = resources.displayMetrics
                        val screenWidth = displayMetrics.widthPixels
                        val screenHeight = displayMetrics.heightPixels
                        val a11yEnabled = isAccessibilityEnabled()

                        @Suppress("DEPRECATION")
                        val overlayEnabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            Settings.canDrawOverlays(this)
                        } else {
                            true
                        }

                        result.success(mapOf(
                            "manufacturer" to Build.MANUFACTURER,
                            "model" to Build.MODEL,
                            "version" to Build.VERSION.RELEASE,
                            "apiLevel" to Build.VERSION.SDK_INT,
                            "width" to screenWidth,
                            "height" to screenHeight,
                            "accessibilityEnabled" to a11yEnabled,
                            "overlayEnabled" to overlayEnabled
                        ))
                    } catch (e: Exception) {
                        result.error("DEVICE_INFO_FAILED", "Failed to get device info: ${e.message}", null)
                    }
                }

                // ── Terminal: execute shell command ──
                "exec" -> {
                    val command = call.argument<String>("command") ?: ""
                    val workDir = call.argument<String>("workingDir") ?: "/sdcard/KoloProjects"
                    if (command.isEmpty()) {
                        result.error("INVALID", "command is required", null)
                    } else {
                        Thread {
                            try {
                                val process = Runtime.getRuntime().exec(
                                    arrayOf("/system/bin/sh", "-c", command),
                                    arrayOf("TERM=xterm-256color", "HOME=/sdcard"),
                                    java.io.File(workDir)
                                )
                                val stdout = process.inputStream.bufferedReader().readText()
                                val stderr = process.errorStream.bufferedReader().readText()
                                process.waitFor(30, java.util.concurrent.TimeUnit.SECONDS)
                                val exitCode = process.exitValue()
                                runOnUiThread {
                                    result.success(mapOf(
                                        "stdout" to stdout,
                                        "stderr" to stderr,
                                        "exitCode" to exitCode
                                    ))
                                }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("EXEC_FAILED", e.message, null)
                                }
                            }
                        }.start()
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    // ── Handle overlay permission result ──
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            OVERLAY_PERMISSION_REQUEST -> {
                if (KoloOverlayManager.canDrawOverlays(this)) {
                    // Permission granted — start the controller
                    KoloScreenshotService.start(this)
                    pendingControllerStart?.success(true)
                } else {
                    pendingControllerStart?.error("NO_OVERLAY", "Overlay permission is required for the STOP button and screen indicator. Please grant it in Settings.", null)
                }
                pendingControllerStart = null
            }
        }
    }



    // ── Helper: check accessibility service status ──
    private fun isAccessibilityEnabled(): Boolean {
        return try {
            val cr = contentResolver
            val setting = android.provider.Settings.Secure.getInt(cr, android.provider.Settings.Secure.ACCESSIBILITY_ENABLED, 0)
            val enabledServices = android.provider.Settings.Secure.getString(cr, android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
            setting == 1 && enabledServices.contains("com.kolo.kolo_ai_agent/com.kolo.kolo_ai_agent.KoloAccessibilityService")
        } catch (_: Exception) {
            KoloAccessibilityService.instance != null
        }
    }
}