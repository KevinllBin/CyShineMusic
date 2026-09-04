import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/playlist_summary.dart';
import '../discovery_controller.dart';
import 'discovery_helpers.dart';
import 'discovery_playlist_cover.dart';

class PlaylistPreviewDialog extends ConsumerWidget {
  const PlaylistPreviewDialog({super.key, required this.summary});

  final PlaylistSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = OnlinePlaylistKey(source: summary.source, id: summary.id);
    final detail = ref.watch(onlinePlaylistDetailProvider(key));
    final loaded = detail.asData?.value;
    final coverUrl = _firstNonEmpty(summary.coverUrl, loaded?.coverUrl);
    final creator = _firstNonEmpty(summary.creator, loaded?.creator);
    final description = _firstNonEmpty(
      summary.description,
      loaded?.description,
    );
    final trackCount = summary.trackCount ?? loaded?.totalTracks;
    final metadata = <String>[summary.source.label];
    if (creator != null) metadata.add(creator);
    if (trackCount != null) metadata.add('$trackCount 首');
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 650),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox.square(
                      dimension: 92,
                      child: DiscoveryPlaylistCover(url: coverUrl, size: 30),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.name,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 17,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          metadata.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                            height: 1.25,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if (description != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            Divider(height: 1, color: scheme.outlineVariant),
            Flexible(
              child: detail.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          discoveryFriendlyError(error),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        IconButton.filledTonal(
                          tooltip: '重试',
                          onPressed: () =>
                              ref.invalidate(onlinePlaylistDetailProvider(key)),
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (playlist) => ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: math.min(8, playlist.tracks.length),
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    indent: 54,
                    color: scheme.outlineVariant.withValues(alpha: 0.42),
                  ),
                  itemBuilder: (context, index) {
                    final music = playlist.tracks[index];
                    return ListTile(
                      dense: true,
                      minTileHeight: 48,
                      leading: SizedBox(
                        width: 28,
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        music.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        music.singer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push(
                      discoveryPlaylistDetailPath(summary),
                      extra: summary,
                    );
                  },
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('查看完整歌单'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _firstNonEmpty(String? primary, String? fallback) {
  final first = primary?.trim();
  if (first != null && first.isNotEmpty) return first;
  final second = fallback?.trim();
  return second == null || second.isEmpty ? null : second;
}
