import 'package:flutter/services.dart';

/// Haptic feedback utility for the app.
class Haptics {
  /// Light impact — for button presses, sending messages
  static void light() => HapticFeedback.lightImpact();

  /// Medium impact — for tool execution start
  static void medium() => HapticFeedback.mediumImpact();

  /// Heavy impact — for errors
  static void heavy() => HapticFeedback.heavyImpact();

  /// Selection click — for toggles, switching chats
  static void selection() => HapticFeedback.selectionClick();
}