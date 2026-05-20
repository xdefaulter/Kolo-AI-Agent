import 'package:flutter/material.dart';

/// A gently-scaling robot icon used as the empty-state hero on the chat
/// screen. Pulses between 0.95x and 1.05x over a 2 second cycle.
///
/// Extracted to its own file so it can be reused elsewhere (e.g. loading
/// states, onboarding) and unit-tested in isolation.
class BreathingIcon extends StatefulWidget {
  final Color color;

  /// Icon size in logical pixels. Defaults to 80 — matches the chat
  /// empty-state original.
  final double size;

  /// The icon glyph. Defaults to `Icons.smart_toy_outlined` so existing
  /// call sites don't have to specify one.
  final IconData icon;

  const BreathingIcon({
    super.key,
    required this.color,
    this.size = 80,
    this.icon = Icons.smart_toy_outlined,
  });

  @override
  State<BreathingIcon> createState() => _BreathingIconState();
}

class _BreathingIconState extends State<BreathingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
      lowerBound: 0.95,
      upperBound: 1.05,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // AnimatedBuilder with a `child` argument is a small but real perf win:
    // the Icon widget (expensive enough to construct) is built once and
    // reused across the 60fps animation ticks — only the Transform.scale
    // rebuilds per frame.
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Transform.scale(scale: _ctrl.value, child: child);
      },
      child: Icon(widget.icon, size: widget.size, color: widget.color),
    );
  }
}
