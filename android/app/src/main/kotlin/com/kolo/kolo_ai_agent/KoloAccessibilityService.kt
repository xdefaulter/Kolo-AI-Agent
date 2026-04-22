package com.kolo.kolo_ai_agent

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.graphics.Bitmap
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class KoloAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "KoloA11y"
        @Volatile var instance: KoloAccessibilityService? = null
            private set
        var methodChannel: MethodChannel? = null
    }

    private val handler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.i(TAG, "Accessibility service connected")
        // MethodChannel must be invoked on the main thread
        handler.post {
            methodChannel?.invokeMethod("accessibility_status", true)
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // We read the tree on-demand when the agent requests it.
    }

    override fun onInterrupt() {
        instance = null
        handler.post {
            methodChannel?.invokeMethod("accessibility_status", false)
        }
        Log.i(TAG, "Accessibility service interrupted")
    }

    override fun onDestroy() {
        instance = null
        handler.post {
            methodChannel?.invokeMethod("accessibility_status", false)
        }
        super.onDestroy()
        Log.i(TAG, "Accessibility service destroyed")
    }

    // ── Screenshot via AccessibilityService.takeScreenshot() ──

    fun takeScreenshot(callback: (ByteArray?) -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            takeScreenshot(
                android.view.Display.DEFAULT_DISPLAY,
                mainExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(screenshot: AccessibilityService.ScreenshotResult) {
                        try {
                            val bitmap = Bitmap.wrapHardwareBuffer(
                                screenshot.hardwareBuffer,
                                screenshot.colorSpace
                            )
                            if (bitmap != null) {
                                // Scale down for faster transfer (max 1080 wide)
                                val scaled = if (bitmap.width > 1080) {
                                    val scale = 1080f / bitmap.width
                                    Bitmap.createScaledBitmap(
                                        bitmap, 1080,
                                        (bitmap.height * scale).toInt(), true
                                    )
                                } else {
                                    bitmap
                                }
                                val stream = ByteArrayOutputStream()
                                scaled.compress(Bitmap.CompressFormat.JPEG, 75, stream)
                                callback(stream.toByteArray())
                                if (scaled !== bitmap) scaled.recycle()
                                bitmap.recycle()
                            } else {
                                callback(null)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error processing screenshot", e)
                            callback(null)
                        } finally {
                            screenshot.hardwareBuffer.close()
                        }
                    }

                    override fun onFailure(errorCode: Int) {
                        Log.e(TAG, "Accessibility screenshot failed: code $errorCode")
                        callback(null)
                    }
                }
            )
        } else {
            Log.w(TAG, "Accessibility screenshot requires API 30+")
            callback(null)
        }
    }

    // ── Gesture: Tap ──

    fun tap(x: Float, y: Float, callback: (Boolean) -> Unit) {
        val path = Path()
        path.moveTo(x, y)
        val stroke = GestureDescription.StrokeDescription(path, 0, 50)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                handler.post { callback(true) }
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                handler.post { callback(false) }
            }
        }, null)
    }

    // ── Gesture: Swipe ──

    fun swipe(startX: Float, startY: Float, endX: Float, endY: Float, durationMs: Long, callback: (Boolean) -> Unit) {
        val path = Path()
        path.moveTo(startX, startY)
        path.lineTo(endX, endY)
        val stroke = GestureDescription.StrokeDescription(path, 0, durationMs)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                handler.post { callback(true) }
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                handler.post { callback(false) }
            }
        }, null)
    }

    // ── Gesture: Long press ──

    fun longPress(x: Float, y: Float, durationMs: Long, callback: (Boolean) -> Unit) {
        val path = Path()
        path.moveTo(x, y)
        val stroke = GestureDescription.StrokeDescription(path, 0, durationMs)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                handler.post { callback(true) }
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                handler.post { callback(false) }
            }
        }, null)
    }

    // ── Type text into focused node ──

    fun typeText(text: String, callback: (Boolean) -> Unit) {
        val rootNode = rootInActiveWindow ?: run {
            callback(false)
            return
        }
        val focusNode = findFocus(rootNode, AccessibilityNodeInfo.FOCUS_INPUT)
        if (focusNode != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val args = Bundle()
            args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            val result = focusNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
            focusNode.recycle()
            rootNode.recycle()
            callback(result)
        } else {
            focusNode?.recycle()
            rootNode.recycle()
            callback(false)
        }
    }

    // ── Press key (back, home, recents, enter) ──

    fun pressBack(callback: (Boolean) -> Unit) {
        callback(performGlobalAction(GLOBAL_ACTION_BACK))
    }

    fun pressHome(callback: (Boolean) -> Unit) {
        callback(performGlobalAction(GLOBAL_ACTION_HOME))
    }

    fun pressRecents(callback: (Boolean) -> Unit) {
        callback(performGlobalAction(GLOBAL_ACTION_RECENTS))
    }

    fun pressNotifications(callback: (Boolean) -> Unit) {
        callback(performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS))
    }

    fun pressQuickSettings(callback: (Boolean) -> Unit) {
        callback(performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS))
    }

    fun pressPowerDialog(callback: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            callback(performGlobalAction(GLOBAL_ACTION_POWER_DIALOG))
        } else {
            callback(false)
        }
    }

    fun pressLockScreen(callback: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            callback(performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN))
        } else {
            callback(false)
        }
    }

    fun pressEnter(callback: (Boolean) -> Unit) {
        val rootNode = rootInActiveWindow ?: run { callback(false); return }
        val focusNode = findFocus(rootNode, AccessibilityNodeInfo.FOCUS_INPUT)
        if (focusNode != null) {
            val result = focusNode.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            focusNode.recycle()
            rootNode.recycle()
            callback(result)
        } else {
            rootNode.recycle()
            callback(false)
        }
    }

    // ── Read accessibility tree ──

    fun readScreenTree(): String {
        val rootNode = rootInActiveWindow ?: return "[]"
        val nodes = mutableListOf<Map<String, Any?>>()
        traverseNode(rootNode, nodes, 0)
        // rootNode must be recycled after use
        rootNode.recycle()
        val sb = StringBuilder()
        sb.append("[\n")
        nodes.forEachIndexed { idx, node ->
            sb.append("  {")
            node.entries.forEachIndexed { i, (k, v) ->
                sb.append("\"$k\":")
                when (v) {
                    is String -> sb.append("\"${escapeJson(v)}\"")
                    is Number -> sb.append(v)
                    is Boolean -> sb.append(v)
                    null -> sb.append("null")
                    else -> sb.append("\"${escapeJson(v.toString())}\"")
                }
                if (i < node.size - 1) sb.append(",")
            }
            sb.append("}")
            if (idx < nodes.size - 1) sb.append(",")
            sb.append("\n")
        }
        sb.append("]")
        return sb.toString()
    }

    private fun traverseNode(node: AccessibilityNodeInfo, result: MutableList<Map<String, Any?>>, depth: Int) {
        if (depth > 30) return

        val rect = Rect()
        node.getBoundsInScreen(rect)
        val map = mutableMapOf<String, Any?>(
            "text" to node.text?.toString(),
            "contentDescription" to node.contentDescription?.toString(),
            "viewIdResourceName" to node.viewIdResourceName,
            "className" to node.className?.toString(),
            "bounds" to "[${rect.left},${rect.top},${rect.right},${rect.bottom}]",
            "clickable" to node.isClickable,
            "focusable" to node.isFocusable,
            "editable" to node.isEditable,
            "scrollable" to node.isScrollable,
            "checkable" to node.isCheckable,
            "checked" to node.isChecked,
            "enabled" to node.isEnabled,
            "depth" to depth,
        )

        val hasContent = !node.text.isNullOrEmpty() ||
                        !node.contentDescription.isNullOrEmpty() ||
                        node.isClickable ||
                        node.isEditable ||
                        node.isScrollable ||
                        node.isCheckable
        if (hasContent) {
            result.add(map)
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            traverseNode(child, result, depth + 1)
            child.recycle()
        }
    }

    // ── Find node and click by text ──

    fun clickByText(text: String, callback: (Boolean) -> Unit) {
        val rootNode = rootInActiveWindow ?: run { callback(false); return }
        val node = findNodeByText(rootNode, text)
        if (node != null && node.isClickable) {
            val result = node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            node.recycle()
            rootNode.recycle()
            callback(result)
        } else {
            node?.recycle()
            rootNode.recycle()
            callback(false)
        }
    }

    // ── Find node and click by viewId ──

    fun clickByViewId(viewId: String, callback: (Boolean) -> Unit) {
        val rootNode = rootInActiveWindow ?: run { callback(false); return }
        val nodes = mutableListOf<AccessibilityNodeInfo>()
        findNodesByViewId(rootNode, viewId, nodes)
        // rootNode is obtained from rootInActiveWindow — must be recycled
        rootNode.recycle()
        if (nodes.isNotEmpty() && nodes[0].isClickable) {
            val result = nodes[0].performAction(AccessibilityNodeInfo.ACTION_CLICK)
            nodes.forEach { it.recycle() }
            callback(result)
        } else {
            nodes.forEach { it.recycle() }
            callback(false)
        }
    }

    // ── Scroll in a direction ──

    fun scroll(direction: String, callback: (Boolean) -> Unit) {
        val rootNode = rootInActiveWindow ?: run { callback(false); return }
        val scrollable = findScrollableNode(rootNode)
        // findScrollableNode may return rootNode itself if root.isScrollable
        val scrollableIsRoot = (scrollable === rootNode)
        if (scrollable == null) {
            rootNode.recycle()
            callback(false)
            return
        }
        if (direction !in listOf("up", "down", "left", "right")) {
            if (!scrollableIsRoot) scrollable.recycle()
            rootNode.recycle()
            callback(false)
            return
        }
        val rect = Rect()
        scrollable.getBoundsInScreen(rect)
        val centerX = (rect.left + rect.right) / 2f
        val centerY = (rect.top + rect.bottom) / 2f
        val scrollDistance = (rect.bottom - rect.top) * 0.5f

        val (startX, startY, endX, endY) = when (direction) {
            "up" -> listOf(centerX, centerY, centerX, centerY - scrollDistance)
            "down" -> listOf(centerX, centerY, centerX, centerY + scrollDistance)
            "left" -> listOf(centerX, centerY, centerX - scrollDistance, centerY)
            "right" -> listOf(centerX, centerY, centerX + scrollDistance, centerY)
            else -> throw AssertionError("unreachable")
        }
        // Only recycle scrollable if it's a separate node from rootNode
        if (!scrollableIsRoot) scrollable.recycle()
        rootNode.recycle()
        swipe(startX, startY, endX, endY, 300, callback)
    }

    // ── Helpers ──

    private fun findFocus(root: AccessibilityNodeInfo, focusType: Int): AccessibilityNodeInfo? {
        return root.findFocus(focusType)
    }

    private fun findNodeByText(root: AccessibilityNodeInfo, text: String): AccessibilityNodeInfo? {
        val list = root.findAccessibilityNodeInfosByText(text)
        val first = list.firstOrNull()
        // Recycle all other nodes in the list to avoid AccessibilityNodeInfo leaks
        for (i in list.indices) {
            if (i == 0) continue // Keep the first match; caller is responsible for recycling it
            list[i].recycle()
        }
        return first
    }

    /**
     * Recursively find all nodes matching viewId.
     * Nodes that match are added to [result] — the CALLER must recycle them after use.
     * Non-matching intermediate nodes are recycled to prevent AccessibilityNodeInfo leaks.
     * Note: the [root] node itself is NOT recycled by this method; the caller owns it.
     */
    private fun findNodesByViewId(root: AccessibilityNodeInfo, viewId: String, result: MutableList<AccessibilityNodeInfo>) {
        for (i in 0 until root.childCount) {
            val child = root.getChild(i) ?: continue
            if (child.viewIdResourceName?.contains(viewId) == true) {
                result.add(child)
                // Matched — caller will recycle. Still recurse to find nested matches.
                findNodesByViewId(child, viewId, result)
            } else {
                // Not matched — recurse to check descendants, then recycle child
                findNodesByViewId(child, viewId, result)
                child.recycle()
            }
        }
    }

    private fun findScrollableNode(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (root.isScrollable) return root
        for (i in 0 until root.childCount) {
            val child = root.getChild(i) ?: continue
            val found = findScrollableNode(child)
            if (found != null) return found
            child.recycle()
        }
        return null
    }

    private fun escapeJson(s: String): String {
        return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
    }
}