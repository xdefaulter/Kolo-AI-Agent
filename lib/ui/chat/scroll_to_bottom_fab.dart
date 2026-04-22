import 'package:flutter/material.dart';

/// Scroll-to-bottom FAB that appears when the user has scrolled up.
class ScrollToBottomFab extends StatelessWidget {
  final VoidCallback onTap;
  final bool visible;
  const ScrollToBottomFab({super.key, required this.onTap, this.visible = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedScale(
        scale: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: FloatingActionButton.small(
            onPressed: onTap,
            backgroundColor: cs.surfaceContainerHigh,
            elevation: 2,
            child: Icon(Icons.keyboard_arrow_down, color: cs.onSurface),
          ),
        ),
      ),
    );
  }
}
