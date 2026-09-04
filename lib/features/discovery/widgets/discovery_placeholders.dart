import 'package:flutter/material.dart';

import '../../../core/ui/app_refresh_indicator.dart';

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

class DiscoveryEmpty extends StatelessWidget {
  const DiscoveryEmpty({super.key, required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return AppRefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 150),
          Icon(Icons.library_music_outlined, size: 40),
          SizedBox(height: 12),
          Text('暂时没有精选歌单', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
