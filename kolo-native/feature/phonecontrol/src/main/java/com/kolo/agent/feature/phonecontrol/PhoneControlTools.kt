package com.kolo.agent.feature.phonecontrol

import com.kolo.agent.core.model.ToolExecutionResult
import com.kolo.agent.core.model.ToolPermission
import com.kolo.agent.core.tools.KoloTool
import com.kolo.agent.core.tools.ToolExecutionContext
import com.kolo.agent.feature.phonecontrol.service.PhoneControlAccessibilityService

// ──────────────────────── Screen reading (always allowed, even when stopped) ────────────────────────

class ScreenReadTool : KoloTool() {
    override val name = "screen_read"
    override val description = "Read the accessibility tree of the current screen. Returns a structured description of all visible UI elements. Always available even when phone control session is stopped."
    override val parameterSchema = """{"type":"object","properties":{},"required":[]}"""
    override val permission = ToolPermission.dangerous

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val service = PhoneControlAccessibilityService.getInstance()
            ?: return ToolExecutionResult.err("Phone control accessibility service is not running. Please enable it in Settings > Accessibility.")
        return try {
            val tree = service.getScreenTree()
            if (tree.isBlank()) ToolExecutionResult.err("Empty screen tree.")
            else ToolExecutionResult.ok(tree.take(50000))
        } catch (e: Exception) { ToolExecutionResult.err("Failed to read screen: ${e.message}") }
    }
}

// ──────────────────────── Dangerous gesture tools (require active session) ────────────────────────

class TapTool : KoloTool() {
    override val name = "tap"
    override val description = "Tap at specific screen coordinates (x, y). Requires an active phone control session."
    override val parameterSchema = """{"type":"object","properties":{"x":{"type":"integer","description":"X coordinate"},"y":{"type":"integer","description":"Y coordinate"}},"required":["x","y"]}"""
    override val permission = ToolPermission.dangerous

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val x = params["x"]?.toIntOrNull() ?: return ToolExecutionResult.err("Missing or invalid x")
        val y = params["y"]?.toIntOrNull() ?: return ToolExecutionResult.err("Missing or invalid y")
        val service = PhoneControlAccessibilityService.getInstance()
            ?: return ToolExecutionResult.err("Phone control service not running")
        return service.tapAt(x, y)
    }
}

class SwipeTool : KoloTool() {
    override val name = "swipe"
    override val description = "Perform a swipe gesture from one point to another. Requires an active phone control session."
    override val parameterSchema = """{"type":"object","properties":{"start_x":{"type":"integer"},"start_y":{"type":"integer"},"end_x":{"type":"integer"},"end_y":{"type":"integer"},"duration":{"type":"integer","description":"Duration in ms (default: 300)"}},"required":["start_x","start_y","end_x","end_y"]}"""
    override val permission = ToolPermission.dangerous

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val startX = params["start_x"]?.toIntOrNull() ?: return ToolExecutionResult.err("Missing start_x")
        val startY = params["start_y"]?.toIntOrNull() ?: return ToolExecutionResult.err("Missing start_y")
        val endX = params["end_x"]?.toIntOrNull() ?: return ToolExecutionResult.err("Missing end_x")
        val endY = params["end_y"]?.toIntOrNull() ?: return ToolExecutionResult.err("Missing end_y")
        val duration = params["duration"]?.toLongOrNull() ?: 300L
        val service = PhoneControlAccessibilityService.getInstance()
            ?: return ToolExecutionResult.err("Phone control service not running")
        return service.swipe(startX, startY, endX, endY, duration)
    }
}

class LongPressTool : KoloTool() {
    override val name = "long_press"
    override val description = "Perform a long press at specific screen coordinates. Requires an active phone control session."
    override val parameterSchema = """{"type":"object","properties":{"x":{"type":"integer"},"y":{"type":"integer"},"duration":{"type":"integer","description":"Duration in ms (default: 500)"}},"required":["x","y"]}"""
    override val permission = ToolPermission.dangerous

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val x = params["x"]?.toIntOrNull() ?: return ToolExecutionResult.err("Missing x")
        val y = params["y"]?.toIntOrNull() ?: return ToolExecutionResult.err("Missing y")
        val duration = params["duration"]?.toLongOrNull() ?: 500L
        val service = PhoneControlAccessibilityService.getInstance()
            ?: return ToolExecutionResult.err("Phone control service not running")
        return service.longPressAt(x, y, duration)
    }
}

class ClickTextTool : KoloTool() {
    override val name = "click_text"
    override val description = "Find and click a UI element by its text content. Requires an active phone control session."
    override val parameterSchema = """{"type":"object","properties":{"text":{"type":"string","description":"Text to search for"}},"required":["text"]}"""
    override val permission = ToolPermission.dangerous

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val text = params["text"] ?: return ToolExecutionResult.err("Missing text parameter")
        val service = PhoneControlAccessibilityService.getInstance()
            ?: return ToolExecutionResult.err("Phone control service not running")
        val node = service.findNodeByText(text)
            ?: return ToolExecutionResult.err("Could not find clickable element with text '$text'")
        val bounds = android.graphics.Rect()
        node.getBoundsInScreen(bounds)
        val cx = bounds.centerX()
        val cy = bounds.centerY()
        return service.tapAt(cx, cy)
    }
}

class TypeTextTool : KoloTool() {
    override val name = "type_text"
    override val description = "Type text into the currently focused input field using accessibility actions. Requires an active phone control session."
    override val parameterSchema = """{"type":"object","properties":{"text":{"type":"string","description":"Text to type"}},"required":["text"]}"""
    override val permission = ToolPermission.dangerous

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val text = params["text"] ?: return ToolExecutionResult.err("Missing text parameter")
        val service = PhoneControlAccessibilityService.getInstance()
            ?: return ToolExecutionResult.err("Phone control service not running")
        return service.typeText(text)
    }
}

class PressKeyTool : KoloTool() {
    override val name = "press_key"
    override val description = "Press a system key. Supported keys: back, home, recents, notifications, quick_settings, power_dialog, enter, tab, delete. Requires an active phone control session."
    override val parameterSchema = """{"type":"object","properties":{"key":{"type":"string","description":"Key to press: back, home, recents, notifications, quick_settings, power_dialog, enter, tab, delete"}},"required":["key"]}"""
    override val permission = ToolPermission.dangerous

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val key = params["key"]?.lowercase() ?: return ToolExecutionResult.err("Missing key parameter")
        val service = PhoneControlAccessibilityService.getInstance()
            ?: return ToolExecutionResult.err("Phone control service not running")
        return service.pressKey(key)
    }
}

class ScrollTool : KoloTool() {
    override val name = "scroll"
    override val description = "Scroll in a direction on the screen. Requires an active phone control session."
    override val parameterSchema = """{"type":"object","properties":{"direction":{"type":"string","description":"Direction: up, down, left, right"},"distance":{"type":"integer","description":"Scroll distance in pixels (default: 500)"}},"required":["direction"]}"""
    override val permission = ToolPermission.dangerous

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val direction = params["direction"]?.lowercase() ?: return ToolExecutionResult.err("Missing direction")
        val distance = params["distance"]?.toIntOrNull() ?: 500
        val service = PhoneControlAccessibilityService.getInstance()
            ?: return ToolExecutionResult.err("Phone control service not running")
        return service.scroll(direction, distance)
    }
}

class ScreenReadFullTool : KoloTool() {
    override val name = "screen_read_full"
    override val description = "Read the full accessibility tree of the current screen. Returns detailed information about all visible UI elements. This is not a visual screenshot — it returns a structured text description. Always available."
    override val parameterSchema = """{"type":"object","properties":{},"required":[]}"""
    override val permission = ToolPermission.dangerous

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val service = PhoneControlAccessibilityService.getInstance()
            ?: return ToolExecutionResult.err("Phone control service not running")
        // screen_read_full is always allowed — reading the screen doesn't modify anything
        val tree = service.getScreenTree()
        return if (tree.isBlank()) ToolExecutionResult.err("Empty screen")
        else ToolExecutionResult.ok("Screen content:\n${tree.take(50000)}")
    }
}

// ──────────────────────── Session management tools ────────────────────────

class ShowActionTool : KoloTool() {
    override val name = "show_action"
    override val description = "Show a brief status message on the phone control overlay, e.g. 'Tapping button X' or 'Scrolling down'. Only works during an active session."
    override val parameterSchema = """{"type":"object","properties":{"message":{"type":"string","description":"Status message to display"}},"required":["message"]}"""
    override val permission = ToolPermission.safe

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val message = params["message"] ?: return ToolExecutionResult.err("Missing message parameter")
        val service = PhoneControlAccessibilityService.getInstance()
            ?: return ToolExecutionResult.err("Phone control service not running")
        service.showOverlay(message)
        return ToolExecutionResult.ok("Displayed: $message")
    }
}

class PhoneControlStartTool : KoloTool() {
    override val name = "phone_control_start"
    override val description = "Signal that the agent is starting phone control. Activates the session, shows the safety overlay with STOP button, and clears any stopped-by-user state."
    override val parameterSchema = """{"type":"object","properties":{"reason":{"type":"string","description":"Why the agent is controlling the phone"}},"required":[]}"""
    override val permission = ToolPermission.dangerous

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val reason = params["reason"] ?: "Agent is controlling your phone"
        val running = PhoneControlAccessibilityService.isRunning.value
        if (!running) return ToolExecutionResult.err("Phone control accessibility service is not running. Please enable it in Settings > Accessibility.")
        PhoneControlAccessibilityService.beginSession(reason)
        val service = PhoneControlAccessibilityService.getInstance()
        service?.showOverlay(reason)
        return ToolExecutionResult.ok("Phone control session started: $reason")
    }
}

class PhoneControlStatusTool : KoloTool() {
    override val name = "phone_control_status"
    override val description = "Check whether the phone control accessibility service is running and the current session state (inactive, active, or stopped by user)."
    override val parameterSchema = """{"type":"object","properties":{},"required":[]}"""
    override val permission = ToolPermission.safe

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val running = PhoneControlAccessibilityService.isRunning.value
        val state = PhoneControlAccessibilityService.sessionState.value
        if (!running) return ToolExecutionResult.ok("Phone control service is NOT running. Enable it in Settings > Accessibility.")
        return ToolExecutionResult.ok("Phone control service: running | Session state: $state")
    }
}

class PhoneControlDoneTool : KoloTool() {
    override val name = "phone_control_done"
    override val description = "Signal that the agent is done controlling the phone. Ends the active session and hides the safety overlay."
    override val parameterSchema = """{"type":"object","properties":{"message":{"type":"string","description":"Completion message to show"}},"required":[]}"""
    override val permission = ToolPermission.safe

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val message = params["message"] ?: "Done!"
        PhoneControlAccessibilityService.endSession()
        return ToolExecutionResult.ok("Phone control session ended: $message")
    }
}

class ScreenScreenshotTool : KoloTool() {
    override val name = "screen_screenshot"
    override val description = "Capture a structural screenshot of the current screen. Returns all visible UI elements with text, bounds, properties, and screen metrics. Requires phone control session to be active."
    override val parameterSchema = """{"type":"object","properties":{},"required":[]}"""
    override val permission = ToolPermission.dangerous

    override suspend fun execute(params: Map<String, String>, context: ToolExecutionContext): ToolExecutionResult {
        val service = PhoneControlAccessibilityService.getInstance()
            ?: return ToolExecutionResult.err("Phone control accessibility service is not running. Please enable it in Settings > Accessibility.")
        return service.takeScreenshot()
    }
}