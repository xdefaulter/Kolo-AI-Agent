import 'package:flutter/material.dart';

/// Slide-in animation wrapper for message bubbles.
/// Messages slide up from below with a fade, creating a smooth appearance.
class SlideInMessage extends StatefulWidget {
  final Widget child;
  final bool isActive; // whether to animate (true for new messages, false for loaded history)

  const SlideInMessage({super.key, required this.child, this.isActive = true});

  @override
  State<SlideInMessage> createState() => _SlideInMessageState();
}

class _SlideInMessageState extends State<SlideInMessage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_controller);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    if (widget.isActive) {
      _controller.forward();
    } else {
      _controller.value = 1.0; // instantly show loaded messages
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return widget.child;
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: widget.child,
      ),
    );
  }
}