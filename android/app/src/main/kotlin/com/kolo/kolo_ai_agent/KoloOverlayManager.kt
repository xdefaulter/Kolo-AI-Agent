package com.kolo.kolo_ai_agent

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
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
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView

/**
 * Manages overlay views (STOP button, border, action text) that float above all apps.
 * Requires SYSTEM_ALERT_WINDOW permission.
 *
 * Two modes:
 * 1. Normal mode (show/hide per-action) — shows border + STOP + action text, auto-hides text after 3s
 * 2. Phone control mode (phoneControlStart/Done) — persistent border + STOP + status text + spinner
 *    Border and status stay until phoneControlDone is called
 *
 * Improvements over v1:
 * - 6dp border with subtle glow (shadow)
 * - Spinner integrated into the status text bar (not separate floating)
 * - STOP button with pulse animation during control mode
 * - Status text larger (15sp) with text shadow for readability
 * - Done state with smooth slide-up animation
 */
object KoloOverlayManager {

    private const val TAG = "KoloOverlay"

    // Overlay views
    private var windowManager: WindowManager? = null
    private var stopButton: View? = null
    private var borderView: View? = null
    private var statusContainer: LinearLayout? = null
    private var statusTextView: TextView? = null
    private var statusSpinner: ProgressBar? = null

    // State
    private var isShowing = false
    private var isControlMode = false
    private val handler = Handler(Looper.getMainLooper())
    private var actionHideRunnable: Runnable? = null
    private var pulseAnimator: ValueAnimator? = null

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
        showStatusText(context, "Ready", autoHide = true)
        isShowing = true
        isControlMode = false
        Log.i(TAG, "Overlay shown (normal mode)")
    }

    fun hide() {
        stopPulseAnimation()
        try { stopButton?.let { windowManager?.removeView(it) } } catch (_: Exception) {}
        try { borderView?.let { windowManager?.removeView(it) } } catch (_: Exception) {}
        try { statusContainer?.let { windowManager?.removeView(it) } } catch (_: Exception) {}
        stopButton = null
        borderView = null
        statusContainer = null
        statusTextView = null
        statusSpinner = null
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
            // If already showing, just update to control mode
            if (isShowing) {
                isControlMode = true
                actionHideRunnable?.let { handler.removeCallbacks(it) } // Cancel auto-hide
                // Switch border to green
                borderView?.let { view ->
                    val bg = view.background
                    if (bg is android.graphics.drawable.GradientDrawable) {
                        bg.setStroke(dpToPx(context, 6f).toInt(), Color.parseColor("#FF4CAF50"))
                    }
                }
                statusTextView?.text = "🤖 $task"
                statusContainer?.visibility = View.VISIBLE
                statusSpinner?.visibility = View.VISIBLE
                startPulseAnimation(context)
                return@post
            }

            // Not showing yet — full setup
            if (!canDrawOverlays(context)) {
                Log.e(TAG, "Cannot start phone control — no overlay permission")
                return@post
            }
            windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            showStopButton(context)
            showBorder(context, borderColor = Color.parseColor("#FF4CAF50")) // Green border for control
            showStatusText(context, task, autoHide = false, showSpinner = true)
            isShowing = true
            isControlMode = true
            startPulseAnimation(context)
            Log.i(TAG, "Phone control mode started: $task")
        }
    }

    /**
     * End phone control mode — show brief summary then hide overlays.
     */
    fun phoneControlDone(summary: String) {
        handler.post {
            stopPulseAnimation()
            isControlMode = false
            if (summary.isNotEmpty()) {
                statusSpinner?.visibility = View.GONE
                statusTextView?.text = "✓ $summary"
                // Change border to gray
                borderView?.let { view ->
                    val bg = view.background
                    if (bg is android.graphics.drawable.GradientDrawable) {
                        bg.setStroke(dpToPx(view.context, 6f).toInt(), Color.parseColor("#FF9E9E9E"))
                    }
                }
                // Stop button: turn gray briefly
                stopButton?.let { btn ->
                    if (btn is TextView) {
                        val bg = btn.background
                        if (bg is android.graphics.drawable.GradientDrawable) {
                            bg.setColor(Color.parseColor("#FF757575"))
                        }
                    }
                }
                // Auto-hide everything after 2 seconds
                handler.postDelayed({
                    hide()
                }, 2000)
            } else {
                hide()
            }
            Log.i(TAG, "Phone control mode ended: $summary")
        }
    }

    /**
     * Update the status text in phone control mode.
     */
    fun phoneControlStatus(status: String) {
        handler.post {
            statusTextView?.text = "🤖 $status"
            if (statusContainer?.visibility != View.VISIBLE) {
                statusContainer?.visibility = View.VISIBLE
            }
        }
    }

    fun showActionText(text: String) {
        handler.post {
            if (isControlMode) {
                // In control mode, just update the persistent text (don't auto-hide)
                statusTextView?.text = "🤖 $text"
                return@post
            }
            statusTextView?.text = "🤖 $text"
            statusContainer?.visibility = View.VISIBLE
            actionHideRunnable?.let { handler.removeCallbacks(it) }
            actionHideRunnable = Runnable { statusContainer?.visibility = View.GONE }
            handler.postDelayed(actionHideRunnable!!, 3000)
        }
    }

    // ── STOP Button ──

    @SuppressLint("ClickableViewAccessibility")
    private fun showStopButton(context: Context) {
        val wm = windowManager ?: return
        val size = dpToPx(context, 60f).toInt()

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

        val layoutParams = FrameLayout.LayoutParams(size, size)
        button.layoutParams = layoutParams
        button.clipToOutline = true
        button.elevation = dpToPx(context, 10f)

        val shape = android.graphics.drawable.GradientDrawable().apply {
            shape = android.graphics.drawable.GradientDrawable.OVAL
            setColor(Color.parseColor("#D32F2F"))
            // White ring for visibility on light backgrounds
            setStroke(dpToPx(context, 2f).toInt(), Color.argb(80, 255, 255, 255))
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

        val winParams = WindowManager.LayoutParams(
            size, size, layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = dpToPx(context, 16f).toInt()
            y = dpToPx(context, 80f).toInt()
        }

        wm.addView(button, winParams)
        stopButton = button
    }

    // ── Pulse animation on STOP button during control mode ──

    private fun startPulseAnimation(context: Context) {
        stopPulseAnimation()
        val btn = stopButton ?: return
        pulseAnimator = ValueAnimator.ofFloat(0.85f, 1.15f).apply {
            duration = 800
            repeatMode = ValueAnimator.REVERSE
            repeatCount = ValueAnimator.INFINITE
            addUpdateListener { animator ->
                val scale = animator.animatedValue as Float
                btn.scaleX = scale
                btn.scaleY = scale
            }
        }
        pulseAnimator?.start()
    }

    private fun stopPulseAnimation() {
        pulseAnimator?.cancel()
        pulseAnimator = null
        stopButton?.scaleX = 1f
        stopButton?.scaleY = 1f
    }

    // ── Border ──

    private fun showBorder(context: Context, borderColor: Int = Color.parseColor("#BFFF1744")) {
        val wm = windowManager ?: return

        val border = View(context)
        val borderThickness = dpToPx(context, 6f).toInt()
        val borderDrawable = android.graphics.drawable.GradientDrawable().apply {
            setStroke(borderThickness, borderColor)
            setColor(Color.TRANSPARENT)
            // Subtle outer glow shadow (via corner radius 0)
            // Note: Window system overlays don't support elevation shadows natively,
            // but the thicker 6dp green/red border is much more visible than 4dp
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

    // ── Status Text Bar (with integrated spinner) ──

    @SuppressLint("SetTextI18n")
    private fun showStatusText(context: Context, initialText: String, autoHide: Boolean = true, showSpinner: Boolean = false) {
        val wm = windowManager ?: return

        // Container: horizontal with spinner + text
        val container = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(
                dpToPx(context, 16f).toInt(),
                dpToPx(context, 8f).toInt(),
                dpToPx(context, 16f).toInt(),
                dpToPx(context, 8f).toInt()
            )
            val bg = android.graphics.drawable.GradientDrawable().apply {
                setColor(Color.parseColor("#E6323232")) // dark pill
                cornerRadius = dpToPx(context, 20f)
                // Thin border for readability on light backgrounds
                setStroke(dpToPx(context, 1f).toInt(), Color.argb(40, 255, 255, 255))
            }
            background = bg
            elevation = dpToPx(context, 6f)
        }

        // Spinner (integrated into the bar, not floating separately)
        val spinner = ProgressBar(context, null, android.R.attr.progressBarStyleSmall).apply {
            isIndeterminate = true
            val color = Color.parseColor("#FF4CAF50")
            indeterminateDrawable?.setColorFilter(color, android.graphics.PorterDuff.Mode.SRC_IN)
            visibility = if (showSpinner || isControlMode) View.VISIBLE else View.GONE
            layoutParams = LinearLayout.LayoutParams(
                dpToPx(context, 20f).toInt(),
                dpToPx(context, 20f).toInt()
            ).apply { marginEnd = dpToPx(context, 8f).toInt() }
        }
        container.addView(spinner)
        statusSpinner = spinner

        // Text
        val tv = TextView(context).apply {
            text = "🤖 $initialText"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            maxLines = 2
            // Text shadow for readability on any background
            setShadowLayer(2f, 1f, 1f, Color.argb(180, 0, 0, 0))
        }
        container.addView(tv)
        statusTextView = tv
        statusContainer = container

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

    private fun dpToPx(context: Context, dp: Float): Float {
        return TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, dp, context.resources.displayMetrics)
    }
}