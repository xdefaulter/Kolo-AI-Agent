import 'dart:async';
import 'package:flutter/material.dart';

/// Cross-platform phone control overlay widget.
/// On Android, the native KoloOverlayManager handles system-wide overlays.
/// On iOS (and as fallback on Android), this Flutter widget provides:
/// - Green border during phone control
/// - STOP button with pulse animation
/// - Status text with elapsed timer
/// - Minimize to floating dot (double-tap STOP)
class PhoneControlOverlay extends StatefulWidget {
  final bool isActive;
  final String? taskName;
  final String? status;
  final VoidCallback? onStop;

  const PhoneControlOverlay({
    super.key,
    required this.isActive,
    this.taskName,
    this.status,
    this.onStop,
  });

  @override
  State<PhoneControlOverlay> createState() => _PhoneControlOverlayState();
}

class _PhoneControlOverlayState extends State<PhoneControlOverlay>
    with SingleTickerProviderStateMixin {
  bool _isMinimized = false;
  late AnimationController _pulseController;
  DateTime? _startTime;
  Duration _elapsed = Duration.zero;
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    if (widget.isActive) {
      _startElapsed();
    }
  }

  @override
  void didUpdateWidget(PhoneControlOverlay old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _isMinimized = false;
      _startElapsed();
    } else if (!widget.isActive && old.isActive) {
      _stopElapsed();
    }
  }

  void _startElapsed() {
    _startTime = DateTime.now();
    _elapsed = Duration.zero;
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_startTime != null) {
        setState(() {
          _elapsed = DateTime.now().difference(_startTime!);
        });
      }
    });
  }

  void _stopElapsed() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _startTime = null;
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return const SizedBox.shrink();

    // Minimized: just a green floating dot
    if (_isMinimized) {
      return Positioned(
        right: 16,
        bottom: 100,
        child: GestureDetector(
          onTap: () => setState(() => _isMinimized = false),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.green.withValues(alpha: 0.4), blurRadius: 8),
              ],
            ),
          ),
        ),
      );
    }

    // Full overlay
    final cs = Theme.of(context).colorScheme;
    final statusText = widget.status ?? widget.taskName ?? 'Controlling phone';
    final elapsedText = _formatElapsed(_elapsed);

    return Positioned(
      right: 12,
      bottom: 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Status bar with timer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pulse indicator
                ListenableBuilder(
                  listenable: _pulseController,
                  builder: (_, __) {
                    return Container(
                      width: 8 + (_pulseController.value * 4),
                      height: 8 + (_pulseController.value * 4),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                // Text
                Flexible(
                  child: Text(
                    '🤖 $elapsedText | $statusText',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // STOP button
          GestureDetector(
            onDoubleTap: () => setState(() => _isMinimized = true),
            onTap: widget.onStop,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.red.shade700,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24, width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.red.withValues(alpha: 0.4), blurRadius: 12),
                ],
              ),
              child: const Center(
                child: Text('⏹', style: TextStyle(color: Colors.white, fontSize: 24)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Green border overlay for phone control mode
class PhoneControlBorder extends StatelessWidget {
  final bool isActive;
  const PhoneControlBorder({super.key, required this.isActive});

  @override
  Widget build(BuildContext context) {
    if (!isActive) return const SizedBox.shrink();
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.green.withValues(alpha: 0.6),
            width: 3,
          ),
        ),
      ),
    );
  }
}