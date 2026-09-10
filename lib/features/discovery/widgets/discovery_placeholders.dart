import 'package:flutter/material.dart';

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
        Icon(
          Icons.cloud_off_rounded,
          size: 38,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Text(message, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 14),
        Center(
          child: IconButton.filledTonal(
            tooltip: '重试',
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
          ),
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
    return Padding(
      key: const ValueKey('discovery-featured-error'),
      padding: const EdgeInsets.fromLTRB(30, 40, 30, 24),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 38,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          IconButton.filledTonal(
            tooltip: '重试',
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class DiscoverySectionEmpty extends StatelessWidget {
  const DiscoverySectionEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: ValueKey('discovery-featured-empty'),
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.library_music_outlined, size: 40),
          SizedBox(height: 12),
          Text('暂时没有精选歌单', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
