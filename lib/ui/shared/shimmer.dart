import 'package:flutter/material.dart';

/// Shimmer effect for loading skeletons
class ShimmerEffect extends StatefulWidget {
  final Widget child;
  const ShimmerEffect({super.key, required this.child});

  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final slidePercent = _controller.value * 2 - 0.5;
            return LinearGradient(
              colors: [
                cs.surfaceContainerHighest.withValues(alpha: 0.5),
                cs.surfaceContainerHigh.withValues(alpha: 0.8),
                cs.surfaceContainerHighest.withValues(alpha: 0.5),
              ],
              stops: [
                (slidePercent - 0.3).clamp(0.0, 1.0),
                slidePercent.clamp(0.0, 1.0),
                (slidePercent + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

/// A skeleton placeholder for chat loading state
class ChatSkeletonLoader extends StatelessWidget {
  const ChatSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: Column(
        children: [
          _skeletonBubble(context, isUser: false, width: 0.7),
          const SizedBox(height: 12),
          _skeletonBubble(context, isUser: true, width: 0.5),
          const SizedBox(height: 12),
          _skeletonBubble(context, isUser: false, width: 0.6),
        ],
      ),
    );
  }

  Widget _skeletonBubble(BuildContext context, {required bool isUser, required double width}) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: MediaQuery.of(context).size.width * width,
        height: 60,
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
          ),
        ),
      ),
    );
  }
}

/// Skeleton for drawer chat list items
class ChatListSkeletonLoader extends StatelessWidget {
  final int count;
  const ChatListSkeletonLoader({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ShimmerEffect(
      child: Column(
        children: List.generate(count, (_) => ListTile(
          leading: Container(
            width: 24, height: 24,
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
          ),
          title: Container(
            height: 14,
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
          ),
          subtitle: Container(
            width: 100, height: 10,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
          ),
        )),
      ),
    );
  }
}