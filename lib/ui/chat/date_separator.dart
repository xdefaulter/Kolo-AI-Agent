import 'package:flutter/material.dart';

/// Date separator header shown between messages from different days.
class DateSeparator extends StatelessWidget {
  final String label; // e.g. "Today", "Yesterday", "April 19"
  const DateSeparator({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: cs.outlineVariant.withValues(alpha: 0.3))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ),
          Expanded(child: Divider(color: cs.outlineVariant.withValues(alpha: 0.3))),
        ],
      ),
    );
  }
}