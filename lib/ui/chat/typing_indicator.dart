import 'package:flutter/material.dart';

/// Animated 3-dot typing indicator for the assistant's "thinking" state.
class TypingIndicator extends StatefulWidget {
  final Color? color;
  final double dotSize;
  const TypingIndicator({super.key, this.color, this.dotSize = 8});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return _TypingDot(
          animation: _controller,
          index: i,
          color: color,
          dotSize: widget.dotSize,
        );
      }),
    );
  }
}

class _TypingDot extends StatelessWidget {
  final Animation<double> animation;
  final int index;
  final Color color;
  final double dotSize;

  _TypingDot({
    super.key,
    required this.animation,
    required this.index,
    required this.color,
    required this.dotSize,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final delay = index * 0.2;
        final t = (animation.value - delay).clamp(0.0, 1.0);
        final scale = (t < 0.4)
            ? 0.5 + t / 0.4 * 0.5 // grow
            : (t < 0.7)
                ? 1.0 // hold
                : 1.0 - (t - 0.7) / 0.3 * 0.5; // shrink

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: scale.clamp(0.4, 1.0),
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}