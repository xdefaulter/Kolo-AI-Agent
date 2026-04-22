import 'package:flutter/material.dart';

class ToolResultCard extends StatelessWidget {
  final String toolName;
  final String result;
  final bool? success;

  const ToolResultCard({
    super.key,
    required this.toolName,
    required this.result,
    this.success,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSuccess = success ?? true;
    final icon = isSuccess ? Icons.check_circle : Icons.error;
    final iconColor = isSuccess ? Colors.green : Colors.red;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSuccess
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.red.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: Icon(icon, size: 18, color: iconColor),
          title: Row(
            children: [
              Text(
                'Tool: $toolName',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isSuccess ? 'Success' : 'Error',
                  style: TextStyle(fontSize: 10, color: iconColor, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: SelectableText(
                    result,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}