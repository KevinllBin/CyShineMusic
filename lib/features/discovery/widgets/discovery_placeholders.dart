import 'package:flutter/material.dart';

import '../../../core/ui/animated_empty_state.dart';

class DiscoveryLoading extends StatelessWidget {
  const DiscoveryLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class DiscoveryError extends StatelessWidget {
  const DiscoveryError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
        AnimatedEmptyState(
          kind: EmptyStateKind.cloud,
          title: '暂时无法加载',
          message: message,
          actionLabel: '重试',
          onAction: onRetry,
        ),
      ],
    );
  }
}

/// 发现页「精选歌单」区块级占位：嵌在常驻的页面 ListView 里，切换分类时
/// 只替换这一块，上方的官方排行榜保持挂载。
class DiscoverySectionLoading extends StatelessWidget {
  const DiscoverySectionLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: ValueKey('discovery-featured-loading'),
      padding: EdgeInsets.symmetric(vertical: 72),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class DiscoverySectionError extends StatelessWidget {
  const DiscoverySectionError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AnimatedEmptyState(
      key: const ValueKey('discovery-featured-error'),
      kind: EmptyStateKind.cloud,
      title: '暂时无法加载歌单',
      message: message,
      actionLabel: '重试',
      onAction: onRetry,
      compact: true,
    );
  }
}

class DiscoverySectionEmpty extends StatelessWidget {
  const DiscoverySectionEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return const AnimatedEmptyState(
      key: ValueKey('discovery-featured-empty'),
      kind: EmptyStateKind.playlist,
      title: '暂时没有精选歌单',
      message: '换个分类，或稍后再来',
      compact: true,
    );
  }
}
