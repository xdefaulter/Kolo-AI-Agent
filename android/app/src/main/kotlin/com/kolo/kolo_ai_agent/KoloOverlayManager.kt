package com.kolo.kolo_ai_agent

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView

/**
 * Manages overlay views (STOP button, border, action text) that float above all apps.
 * Requires SYSTEM_ALERT_WINDOW permission (must check before calling show()).
 *
 * Two modes:
 * 1. Normal mode (show/hide per-action) — shows border + STOP + action text, auto-hides text after 3s
 * 2. Phone control mode (phoneControlStart/Done) — persistent border + STOP + status text + spinner
 *    Border and status stay until phoneControlDone is called
 */
object KoloOverlayManager {

    private const val TAG = "KoloOverlay"

    // Overlay views
    private var windowManager: WindowManager? = null
    private var stopButton: View? = null
    private var borderView: View? = null
    private var actionTextView: TextView? = null
    private var actionContainer: LinearLayout? = null
    private var spinnerView: ProgressBar? = null
    private var spinnerContainer: View? = null

    // State
    private var isShowing = false
    private var isControlMode = false
    private val handler = Handler(Looper.getMainLooper())
    private var actionHideRunnable: Runnable? = null

    // STOP button callback
    var onStopClicked: (() -> Unit)? = null

    /** Check if SYSTEM_ALERT_WINDOW permission is granted */
    fun canDrawOverlays(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else {
            true
        }
    }

    /** Open the overlay permission settings page */
    fun requestOverlayPermission(activity: Activity, requestCode: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${activity.packageName}")
            )
            activity.startActivityForResult(intent, requestCode)
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    fun show(context: Context) {
        if (!canDrawOverlays(context)) {
            Log.e(TAG, "SYSTEM_ALERT_WINDOW not granted — cannot show overlays")
            return
        }
        hide()
        windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        showStopButton(context)
        showBorder(context)
        showActionText(context, "Ready")
        isShowing = true
        isControlMode = false
        Log.i(TAG, "Overlay shown (normal mode)")
    }

    fun hide() {
        try { stopButton?.let { windowManager?.removeView(it) } } catch (_: Exception) {}
        try { borderView?.let { windowManager?.removeView(it) } } catch (_: Exception) {}
        try { actionContainer?.let { windowManager?.removeView(it) } } catch (_: Exception) {}
        try { spinnerContainer?.let { windowManager?.removeView(it) } } catch (_: Exception) {}
        stopButton = null
        borderView = null
        actionTextView = null
        actionContainer = null
        spinnerView = null
        spinnerContainer = null
        isShowing = false
        isControlMode = false
        Log.i(TAG, "Overlay hidden")
    }

    /**
     * Start phone control mode — show persistent border, STOP button, status text, and spinner.
     * Stays visible until phoneControlDone() is called.
     */
    @SuppressLint("SetTextI18n")
    fun phoneControlStart(context: Context, task: String) {
        handler.post {
            // If already showing, just update the text
            if (isShowing) {
                isControlMode = true
                actionHideRunnable?.let { handler.removeCallbacks(it) } // Cancel auto-hide
                borderView?.let { view ->
                    val bg = view.background
                    if (bg is android.graphics.drawable.GradientDrawable) {
                        bg.setStroke(dpToPx(context, 4f).toInt(), Color.parseColor("#FF4CAF50")) // Green border for control mode
                    }
                }
                actionTextView?.text = "🤖 $task"
                actionContainer?.visibility = View.VISIBLE
                showSpinner(context)
                return@post
            }

            // Not showing yet — full setup
            if (!canDrawOverlays(context)) {
                Log.e(TAG, "Cannot start phone control — no overlay permission")
                return@post
            }
            windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            showStopButton(context)
            showBorder(context, borderColor = Color.parseColor("#FF4CAF50")) // Green border
            showActionText(context, task, autoHide = false)
            showSpinner(context)
            isShowing = true
            isControlMode = true
            Log.i(TAG, "Phone control mode started: $task")
        }
    }

    /**
     * End phone control mode — show brief summary then hide overlays.
     */
    fun phoneControlDone(summary: String) {
        handler.post {
            if (summary.isNotEmpty()) {
                actionTextView?.text = "✓ $summary"
                // Change border to gray briefly
                borderView?.let { view ->
                    val bg = view.background
                    if (bg is android.graphics.drawable.GradientDrawable) {
                        bg.setStroke(dpToPx(view.context, 4f).toInt(), Color.parseColor("#FF9E9E9E"))
                    }
                }
                hideSpinner()
                // Auto-hide everything after 2 seconds
                handler.postDelayed({
                    hide()
                }, 2000)
            } else {
                hide()
            }
            isControlMode = false
            Log.i(TAG, "Phone control mode ended: $summary")
        }
    }

    /**
     * Update the status text in phone control mode.
     */
    fun phoneControlStatus(status: String) {
        handler.post {
            actionTextView?.text = "🤖 $status"
            if (actionContainer?.visibility != View.VISIBLE) {
                actionContainer?.visibility = View.VISIBLE
            }
            // Don't auto-hide in control mode
        }
    }

    fun showActionText(text: String) {
        handler.post {
            if (isControlMode) {
                // In control mode, just update the persistent text (don't auto-hide)
                actionTextView?.text = "🤖 $text"
                return@post
            }
            actionTextView?.text = "🤖 $text"
            actionContainer?.visibility = View.VISIBLE
            actionHideRunnable?.let { handler.removeCallbacks(it) }
            actionHideRunnable = Runnable {
                actionContainer?.visibility = View.GONE
            }
            handler.postDelayed(actionHideRunnable!!, 3000)
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun showStopButton(context: Context) {
        val wm = windowManager ?: return

        val size = dpToPx(context, 56f).toInt()
        val button = TextView(context).apply {
            text = "⏹"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            gravity = Gravity.CENTER
            setOnClickListener {
                Log.i(TAG, "STOP button clicked")
                onStopClicked?.invoke()
            }
        }

        val params = FrameLayout.LayoutParams(size, size)
        button.layoutParams = params
        button.clipToOutline = true
        button.elevation = dpToPx(context, 8f)

        val shape = android.graphics.drawable.GradientDrawable().apply {
            shape = android.graphics.drawable.GradientDrawable.OVAL
            setColor(Color.parseColor("#D32F2F"))
        }
        button.background = shape

        var initialX = 0; var initialY = 0
        var initialTouchX = 0f; var initialTouchY = 0f
        var isDragging = false

        button.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = (button.layoutParams as? WindowManager.LayoutParams)?.x ?: 0
                    initialY = (button.layoutParams as? WindowManager.LayoutParams)?.y ?: 0
                    initialTouchX = event.rawX; initialTouchY = event.rawY
                    isDragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (Math.abs(dx) > 10 || Math.abs(dy) > 10) isDragging = true
                    val lp = button.layoutParams as? WindowManager.LayoutParams ?: return@setOnTouchListener false
                    lp.x = initialX + dx.toInt()
                    lp.y = initialY + dy.toInt()
                    wm.updateViewLayout(button, lp)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!isDragging) v.performClick()
                    true
                }
                else -> false
            }
        }

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_SYSTEM_ALERT

        val layoutParams = WindowManager.LayoutParams(
            size, size, layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = dpToPx(context, 16f).toInt()
            y = dpToPx(context, 80f).toInt()
        }

        wm.addView(button, layoutParams)
        stopButton = button
    }

    private fun showBorder(context: Context, borderColor: Int = Color.parseColor("#BFFF1744")) {
        val wm = windowManager ?: return

        val border = View(context)
        val borderDrawable = android.graphics.drawable.GradientDrawable().apply {
            setStroke(dpToPx(context, 4f).toInt(), borderColor)
            setColor(Color.TRANSPARENT)
        }
        border.background = borderDrawable

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_SYSTEM_ALERT

        val layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.CENTER }

        wm.addView(border, layoutParams)
        borderView = border
    }

    @SuppressLint("SetTextI18n")
    private fun showActionText(context: Context, initialText: String, autoHide: Boolean = true) {
        val wm = windowManager ?: return

        val container = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(
                dpToPx(context, 12f).toInt(),
                dpToPx(context, 6f).toInt(),
                dpToPx(context, 12f).toInt(),
                dpToPx(context, 6f).toInt()
            )
            val bg = android.graphics.drawable.GradientDrawable().apply {
                setColor(Color.parseColor("#E6323232"))
                cornerRadius = dpToPx(context, 16f)
            }
            background = bg
        }

        val tv = TextView(context).apply {
            text = "🤖 $initialText"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            maxLines = 2
        }
        container.addView(tv)
        actionTextView = tv
        actionContainer = container

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_SYSTEM_ALERT

        val layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = dpToPx(context, 48f).toInt()
        }

        wm.addView(container, layoutParams)

        // Auto-hide after 3s (only in non-control mode)
        if (autoHide && !isControlMode) {
            actionHideRunnable?.let { handler.removeCallbacks(it) }
            actionHideRunnable = Runnable { container.visibility = View.GONE }
            handler.postDelayed(actionHideRunnable!!, 3000)
        }
    }

    private fun showSpinner(context: Context) {
        val wm = windowManager ?: return
        if (spinnerView != null) return // Already showing

        val spinner = ProgressBar(context, null, android.R.attr.progressBarStyleSmall).apply {
            isIndeterminate = true
            val color = Color.parseColor("#FF4CAF50")
            indeterminateDrawable?.setColorFilter(color, android.graphics.PorterDuff.Mode.SRC_IN)
        }
        spinnerView = spinner

        // Small container above the STOP button
        val container = FrameLayout(context).apply {
            addView(spinner, FrameLayout.LayoutParams(
                dpToPx(context, 24f).toInt(),
                dpToPx(context, 24f).toInt(),
                Gravity.CENTER
            ))
        }
        spinnerContainer = container

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_SYSTEM_ALERT

        val layoutParams = WindowManager.LayoutParams(
            dpToPx(context, 32f).toInt(),
            dpToPx(context, 32f).toInt(),
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = dpToPx(context, 24f).toInt()
            y = dpToPx(context, 148f).toInt() // Below the STOP button
        }

        wm.addView(container, layoutParams)
    }

    private fun hideSpinner() {
        handler.post {
            try { spinnerContainer?.let { windowManager?.removeView(it) } } catch (_: Exception) {}
            spinnerView = null
            spinnerContainer = null
        }
    }

    private fun dpToPx(context: Context, dp: Float): Float {
        return TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, dp, context.resources.displayMetrics)
    }
}