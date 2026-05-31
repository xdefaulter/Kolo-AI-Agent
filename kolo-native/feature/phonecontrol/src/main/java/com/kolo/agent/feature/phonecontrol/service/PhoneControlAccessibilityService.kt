package com.kolo.agent.feature.phonecontrol.service

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.accessibilityservice.GestureDescription
import android.accessibilityservice.GestureDescription.StrokeDescription
import android.graphics.Bitmap
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.Gravity
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.LinearLayout
import android.widget.TextView
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.io.File
import java.io.FileOutputStream

/**
 * Accessibility service for phone control.
 *
 * Session state machine:
 * - inactive: no phone control session. Tools that require an active session will refuse.
 * - active: phone control is running. Dangerous tools can execute.
 * - stoppedByUser: user pressed STOP. All dangerous phone-control tools refuse until
 *   an explicit `phone_control_start` clears this state.
 */
class PhoneControlAccessibilityService : AccessibilityService() {

    enum class SessionState { inactive, active, stoppedByUser }

    companion object {
        private val _isRunning = MutableStateFlow(false)
        val isRunning: StateFlow<Boolean> = _isRunning

        private val _sessionState = MutableStateFlow(SessionState.inactive)
        val sessionState: StateFlow<SessionState> = _sessionState

        private val _overlayMessage = MutableStateFlow("")
        val overlayMessage: StateFlow<String> = _overlayMessage

        private var instance: PhoneControlAccessibilityService? = null

        fun getInstance(): PhoneControlAccessibilityService? = instance

        /** Called by phone_control_start tool to begin a session. */
        fun beginSession(reason: String = "Agent is controlling your phone") {
            _sessionState.value = SessionState.active
            _overlayMessage.value = reason
        }

        /** Called by phone_control_done tool to end a session. */
        fun endSession() {
            _sessionState.value = SessionState.inactive
            _overlayMessage.value = ""
            instance?.removeOverlay()
        }

        /** Called by STOP button — immediately stops and blocks further actions. */
        fun emergencyStop() {
            _sessionState.value = SessionState.stoppedByUser
            _overlayMessage.value = "STOPPED — tap phone_control_start to resume"
            instance?.showStopOverlay()
        }

        /** Check if phone-control dangerous actions should be blocked. */
        fun isBlocked(): Boolean = _sessionState.value != SessionState.active
    }

    private val handler = Handler(Looper.getMainLooper())
    private var overlayView: android.view.View? = null

    // ──── Lifecycle ────

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        _isRunning.value = true

        serviceInfo = serviceInfo.apply {
            eventTypes = AccessibilityEvent.TYPES_ALL_MASK
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.DEFAULT or
                    AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                    AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
            notificationTimeout = 100
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Process events for screen reading — not used currently
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        super.onDestroy()
        removeOverlay()
        instance = null
        _isRunning.value = false
        _sessionState.value = SessionState.inactive
    }

    // ──── System Overlay (TYPE_ACCESSIBILITY_OVERLAY) ────

    fun showOverlay(message: String) {
        _overlayMessage.value = message
        handler.post { addOverlayView() }
    }

    fun removeOverlay() {
        handler.post { removeOverlayView() }
    }

    private fun showStopOverlay() {
        handler.post { addOverlayView() }
    }

    private fun addOverlayView() {
        if (overlayView != null) return
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setBackgroundColor(0xB3000000.toInt()) // 70% black
            setPadding(16, 8, 8, 8)
            gravity = Gravity.CENTER_VERTICAL

            val statusText = TextView(this@PhoneControlAccessibilityService).apply {
                text = "⚠ Kolo: ${_overlayMessage.value.ifBlank { "Controlling phone" }}"
                setTextColor(0xFFFFFFFF.toInt())
                textSize = 13f
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            }
            addView(statusText)

            val stopButton = TextView(this@PhoneControlAccessibilityService).apply {
                text = "■ STOP"
                setTextColor(0xFFFF4444.toInt())
                textSize = 14f
                setPadding(16, 8, 16, 8)
                setOnClickListener {
                    emergencyStop()
                }
            }
            addView(stopButton)
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP
        }

        try {
            wm.addView(container, params)
            overlayView = container
        } catch (_: Exception) {
            // TYPE_ACCESSIBILITY_OVERLAY may not be available on all devices
        }
    }

    private fun removeOverlayView() {
        overlayView?.let {
            try {
                val wm = getSystemService(WINDOW_SERVICE) as WindowManager
                wm.removeView(it)
            } catch (_: Exception) { }
            overlayView = null
        }
    }

    // ──── Phone control actions (all guarded by session state) ────

    fun getScreenTree(): String {
        // Reading the screen tree is always allowed even when stopped
        val rootNode = rootInActiveWindow ?: return "No active window"
        return buildString { appendNode(rootNode, 0) }
    }

    suspend fun takeScreenshot(): ToolExecutionResult {
        if (isBlocked()) return ToolExecutionResult.err("Phone control session is not active. Start with phone_control_start first.")
        val rootNode = rootInActiveWindow ?: return ToolExecutionResult.err("No active window to screenshot")

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return ToolExecutionResult.err("Pixel screenshot requires Android 11/API 30 or newer.")
        }

        return try {
            val result = captureScreenshotResult()
            val hardwareBuffer = result.hardwareBuffer
            val hardwareBitmap = Bitmap.wrapHardwareBuffer(hardwareBuffer, result.colorSpace)
                ?: return ToolExecutionResult.err("Android returned an empty screenshot buffer.")
            val bitmap = hardwareBitmap.copy(Bitmap.Config.ARGB_8888, false)
            hardwareBuffer.close()

            val file = withContext(Dispatchers.IO) {
                val screenshotsDir = File(cacheDir, "screenshots").apply { mkdirs() }
                val output = File(screenshotsDir, "kolo_screen_${System.currentTimeMillis()}.png")
                FileOutputStream(output).use { stream ->
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                }
                output
            }
            bitmap.recycle()

            val tree = buildString { appendNode(rootNode, 0) }
            ToolExecutionResult.ok(
                output = buildString {
                    appendLine("Pixel screenshot captured.")
                    appendLine("File: ${file.absolutePath}")
                    appendLine("Size: ${file.length()} bytes")
                    appendLine("Dimensions: ${hardwareBitmap.width}x${hardwareBitmap.height}")
                    appendLine("Timestamp: ${result.timestamp}")
                    appendLine()
                    appendLine("Accessibility tree:")
                    append(tree.take(12000))
                },
                metadata = mapOf(
                    "path" to file.absolutePath,
                    "mime" to "image/png",
                    "width" to hardwareBitmap.width.toString(),
                    "height" to hardwareBitmap.height.toString(),
                    "timestamp" to result.timestamp.toString(),
                ),
            )
        } catch (e: Exception) {
            ToolExecutionResult.err("Failed to capture pixel screenshot: ${e.message}")
        }
    }

    private suspend fun captureScreenshotResult(): ScreenshotResult {
        val deferred = CompletableDeferred<ScreenshotResult>()
        takeScreenshot(
            Display.DEFAULT_DISPLAY,
            mainExecutor,
            object : TakeScreenshotCallback {
                override fun onSuccess(screenshot: ScreenshotResult) {
                    deferred.complete(screenshot)
                }

                override fun onFailure(errorCode: Int) {
                    deferred.completeExceptionally(
                        IllegalStateException("Accessibility screenshot failed with code $errorCode")
                    )
                }
            },
        )
        return withTimeout(5_000) { deferred.await() }
    }

    fun findNodeByText(text: String): AccessibilityNodeInfo? {
        val rootNode = rootInActiveWindow ?: return null
        return findNodeByText(rootNode, text)
    }

    fun tapAt(x: Int, y: Int): ToolExecutionResult {
        if (isBlocked()) return ToolExecutionResult.err("Phone control session is not active. Start with phone_control_start first.")
        val path = Path().apply {
            moveTo(x.toFloat(), y.toFloat())
            lineTo(x.toFloat() + 1f, y.toFloat())
        }
        val stroke = StrokeDescription(path, 0L, 100L)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        return if (dispatchGesture(gesture, null, null)) ToolExecutionResult.ok("Tapped at ($x, $y)")
        else ToolExecutionResult.err("Failed to tap at ($x, $y)")
    }

    fun swipe(startX: Int, startY: Int, endX: Int, endY: Int, duration: Long = 300L): ToolExecutionResult {
        if (isBlocked()) return ToolExecutionResult.err("Phone control session is not active. Start with phone_control_start first.")
        val path = Path().apply {
            moveTo(startX.toFloat(), startY.toFloat())
            lineTo(endX.toFloat(), endY.toFloat())
        }
        val stroke = StrokeDescription(path, 0L, duration)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        return if (dispatchGesture(gesture, null, null)) ToolExecutionResult.ok("Swiped from ($startX,$startY) to ($endX,$endY)")
        else ToolExecutionResult.err("Swipe failed")
    }

    fun longPressAt(x: Int, y: Int, duration: Long = 500L): ToolExecutionResult {
        if (isBlocked()) return ToolExecutionResult.err("Phone control session is not active. Start with phone_control_start first.")
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val stroke = StrokeDescription(path, 0L, duration)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        return if (dispatchGesture(gesture, null, null)) ToolExecutionResult.ok("Long pressed at ($x, $y)")
        else ToolExecutionResult.err("Long press failed")
    }

    fun typeText(text: String): ToolExecutionResult {
        if (isBlocked()) return ToolExecutionResult.err("Phone control session is not active. Start with phone_control_start first.")
        val rootNode = rootInActiveWindow ?: return ToolExecutionResult.err("No active window")
        val focusNode = rootNode.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            ?: return ToolExecutionResult.err("No focused input field found")

        if (!focusNode.isEditable) {
            return ToolExecutionResult.err("Focused node is not editable")
        }

        val args = android.os.Bundle()
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        val success = focusNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        return if (success) ToolExecutionResult.ok("Typed text: ${text.take(100)}${if (text.length > 100) "..." else ""}")
        else ToolExecutionResult.err("Failed to type text")
    }

    fun pressKey(key: String): ToolExecutionResult {
        if (isBlocked()) return ToolExecutionResult.err("Phone control session is not active. Start with phone_control_start first.")
        val globalAction = when (key) {
            "back" -> AccessibilityService.GLOBAL_ACTION_BACK
            "home" -> AccessibilityService.GLOBAL_ACTION_HOME
            "recents" -> AccessibilityService.GLOBAL_ACTION_RECENTS
            "notifications" -> AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS
            "quick_settings" -> AccessibilityService.GLOBAL_ACTION_QUICK_SETTINGS
            "power_dialog" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) AccessibilityService.GLOBAL_ACTION_POWER_DIALOG else return ToolExecutionResult.err("power_dialog requires Android 9+")
            }
            else -> null
        }

        if (globalAction != null) {
            val success = performGlobalAction(globalAction)
            return if (success) ToolExecutionResult.ok("Pressed $key")
            else ToolExecutionResult.err("Failed to press $key (may require proper permissions)")
        }

        // Handle text-editing keys via focused node
        val rootNode = rootInActiveWindow ?: return ToolExecutionResult.err("No active window")
        val focusNode = rootNode.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            ?: return ToolExecutionResult.err("No focused input field for key '$key'")

        return when (key) {
            "enter" -> {
                val clicked = focusNode.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                if (clicked) ToolExecutionResult.ok("Pressed enter") else ToolExecutionResult.err("Failed to press enter")
            }
            "tab" -> {
                val nextFocus = focusNode.focusSearch(android.view.View.FOCUS_FORWARD)
                if (nextFocus != null) {
                    val gainedFocus = nextFocus.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
                    if (gainedFocus) ToolExecutionResult.ok("Pressed tab (moved focus forward)")
                    else ToolExecutionResult.ok("Pressed tab (identified next focus)")
                } else ToolExecutionResult.err("No next focusable element")
            }
            "delete" -> {
                if (focusNode.isEditable) {
                    val args = android.os.Bundle()
                    args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "")
                    val cleared = focusNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                    if (cleared) ToolExecutionResult.ok("Pressed delete (cleared field)")
                    else ToolExecutionResult.err("Failed to delete")
                } else ToolExecutionResult.err("Focused node is not editable, cannot delete")
            }
            else -> ToolExecutionResult.err("Unknown key: $key. Supported: back, home, recents, notifications, quick_settings, power_dialog, enter, tab, delete")
        }
    }

    fun scroll(direction: String, distance: Int = 500): ToolExecutionResult {
        if (isBlocked()) return ToolExecutionResult.err("Phone control session is not active. Start with phone_control_start first.")
        val rootNode = rootInActiveWindow ?: return ToolExecutionResult.err("No active window")
        val scrollable = findScrollableNode(rootNode)
            ?: return ToolExecutionResult.err("No scrollable container found")

        val action = when (direction) {
            "up" -> AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
            "down" -> AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            "left" -> AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
            "right" -> AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            else -> return ToolExecutionResult.err("Unknown direction: $direction. Use up, down, left, right")
        }

        val scrolls = (distance / 300).coerceIn(1, 10)
        var success = true
        repeat(scrolls) {
            if (!scrollable.performAction(action)) success = false
        }
        return if (success) ToolExecutionResult.ok("Scrolled $direction ($scrolls steps)")
        else ToolExecutionResult.ok("Partially scrolled $direction")
    }

    // ──── Private helpers ────

    private fun findScrollableNode(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isScrollable) return node
        for (i in 0 until node.childCount) {
            node.getChild(i)?.let { child ->
                findScrollableNode(child)?.let { return it }
            }
        }
        return null
    }

    private fun StringBuilder.appendNode(node: AccessibilityNodeInfo, depth: Int) {
        if (depth > 20) return
        val indent = "  ".repeat(depth)
        val text = node.text?.toString() ?: node.contentDescription?.toString() ?: ""
        val className = node.className?.toString()?.substringAfterLast('.') ?: "?"
        val clickable = if (node.isClickable) " [clickable]" else ""
        val scrollable = if (node.isScrollable) " [scrollable]" else ""
        val editable = if (node.isEditable) " [editable]" else ""
        val bounds = Rect().also { node.getBoundsInScreen(it) }

        if (text.isNotBlank() || clickable.isNotBlank() || scrollable.isNotBlank() || editable.isNotBlank()) {
            append("$indent$className")
            if (text.isNotBlank()) append(" \"$text\"")
            append(clickable)
            append(scrollable)
            append(editable)
            append(" bounds=${bounds.toShortString()}")
            appendLine()
        }

        for (i in 0 until node.childCount) {
            node.getChild(i)?.let { appendNode(it, depth + 1) }
        }
    }

    private fun findNodeByText(node: AccessibilityNodeInfo, text: String): AccessibilityNodeInfo? {
        val nodeText = node.text?.toString() ?: node.contentDescription?.toString() ?: ""
        if (nodeText.contains(text, ignoreCase = true) && node.isClickable) return node
        for (i in 0 until node.childCount) {
            node.getChild(i)?.let { child ->
                findNodeByText(child, text)?.let { return it }
            }
        }
        return null
    }
}

/** Shortcut to use ToolExecutionResult from the service without the full tool context. */
private typealias ToolExecutionResult = com.kolo.agent.core.model.ToolExecutionResult
