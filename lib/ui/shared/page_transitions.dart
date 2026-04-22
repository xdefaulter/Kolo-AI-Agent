import 'package:flutter/material.dart';

/// Slide-from-right page transition (iOS-like with fade)
class SlideRightPageRoute<T> extends MaterialPageRoute<T> {
  SlideRightPageRoute({required super.builder, super.settings});

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final tween = Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
        .chain(CurveTween(curve: Curves.easeOutCubic));
    return SlideTransition(
      position: animation.drive(tween),
      child: FadeTransition(opacity: animation, child: child),
    );
  }
}

/// Convenience: push with custom transition
Future<T?> pushSlideRight<T>(BuildContext context, Widget page) {
  return Navigator.push<T>(context, SlideRightPageRoute(builder: (_) => page));
}