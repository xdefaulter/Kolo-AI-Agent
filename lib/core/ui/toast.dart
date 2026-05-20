import 'package:flutter/material.dart';

/// Toast flavor drives color and icon.
enum ToastKind { info, success, warning, error }

/// Kolo's branded toast. Replaces bare `ScaffoldMessenger.showSnackBar(...)`
/// usage across screens with an icon, color-coded background, and a sensible
/// default duration.
///
/// Safe to call from anywhere that has a [BuildContext] with a
/// [ScaffoldMessenger] ancestor. Silently no-ops if no messenger is present
/// (e.g. during hot restart).
void showKoloToast(
  BuildContext context,
  String message, {
  ToastKind kind = ToastKind.info,
  Duration duration = const Duration(seconds: 2),
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final theme = Theme.of(context);
  final (IconData icon, Color bg, Color fg) = switch (kind) {
    ToastKind.info => (
      Icons.info_outline,
      theme.colorScheme.inverseSurface,
      theme.colorScheme.onInverseSurface,
    ),
    ToastKind.success => (
      Icons.check_circle_outline,
      const Color(0xFF1B5E20),
      Colors.white,
    ),
    ToastKind.warning => (
      Icons.warning_amber_rounded,
      const Color(0xFFE65100),
      Colors.white,
    ),
    ToastKind.error => (
      Icons.error_outline,
      const Color(0xFFB3261E),
      Colors.white,
    ),
  };
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: duration,
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
      elevation: 4,
      content: Row(
        children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: fg, fontSize: 13)),
          ),
        ],
      ),
      action: action,
    ),
  );
}
