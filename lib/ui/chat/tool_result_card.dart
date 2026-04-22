import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/haptics.dart';

class ToolResultCard extends StatelessWidget {
  final String toolName;
  final String result;
  final bool? success;
  final Duration? duration; // How long the tool took

  const ToolResultCard({
    super.key,
    required this.toolName,
    required this.result,
    this.success,
    this.duration,
  });

  /// Get category icon for the tool
  IconData _categoryIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('phone') || n.contains('device') || n.contains('app') || n.contains('launch'))
      return Icons.phone_android;
    if (n.contains('web') || n.contains('search') || n.contains('scrape') || n.contains('url'))
      return Icons.language;
    if (n.contains('file') || n.contains('read') || n.contains('write') || n.contains('directory'))
      return Icons.folder_outlined;
    if (n.contains('calculate') || n.contains('math'))
      return Icons.calculate_outlined;
    if (n.contains('location') || n.contains('geo'))
      return Icons.location_on_outlined;
    if (n.contains('contact'))
      return Icons.contacts;
    if (n.contains('clipboard') || n.contains('copy'))
      return Icons.content_copy;
    if (n.contains('screenshot') || n.contains('screen') || n.contains('analyze'))
      return Icons.screenshot_outlined;
    if (n.contains('speech') || n.contains('tts') || n.contains('speak'))
      return Icons.record_voice_over_outlined;
    if (n.contains('timer') || n.contains('alarm'))
      return Icons.timer_outlined;
    if (n.contains('qr'))
      return Icons.qr_code_2;
    if (n.contains('download'))
      return Icons.download;
    if (n.contains('control'))
      return Icons.gamepad;
    return Icons.build_outlined;
  }

  /// Get status color based on tool result
  Color _statusColor(BuildContext context) {
    final isSuccess = success ?? true;
    if (!isSuccess) return Colors.red;
    return Colors.green;
  }

  /// Get status label
  String get _statusLabel => (success ?? true) ? 'Success' : 'Error';

  /// Format duration nicely
  String? get _durationLabel {
    if (duration == null) return null;
    if (duration!.inMilliseconds < 1000) return '${duration!.inMilliseconds}ms';
    return '${duration!.inSeconds}.${(duration!.inMilliseconds % 1000) ~/ 100}s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = _statusColor(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: iconColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: Icon(_categoryIcon(toolName), size: 18, color: cs.primary.withValues(alpha: 0.7)),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  toolName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
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
                  _statusLabel,
                  style: TextStyle(fontSize: 10, color: iconColor, fontWeight: FontWeight.w600),
                ),
              ),
              if (_durationLabel != null) ...[
                const SizedBox(width: 6),
                Text(
                  _durationLabel!,
                  style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.4)),
                ),
              ],
            ],
          ),
          trailing: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              Haptics.light();
              Clipboard.setData(ClipboardData(text: result));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Result copied'),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.copy, size: 16, color: cs.onSurface.withValues(alpha: 0.5)),
            ),
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