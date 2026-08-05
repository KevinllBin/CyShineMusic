import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/music_info.dart';
import '../../shell/player_pull_scope.dart';
import '../player_controller.dart';
import 'player_palette.dart';
import 'spinning_cover_art.dart';
import 'track_change_switcher.dart';

class AlbumPage extends ConsumerWidget {
  const AlbumPage({super.key, this.wide = false});

  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(playerControllerProvider.select((s) => s.track));

    return LayoutBuilder(
      builder: (context, constraints) {
        final coverSize = math.min(
          wide ? 400.0 : 360.0,
          math.min(
            constraints.maxWidth * (wide ? 0.88 : 0.86),
            constraints.maxHeight * (wide ? 0.68 : 0.62),
          ),
        );
        final resolvedCoverSize = coverSize
            .clamp(160.0, wide ? 400.0 : 360.0)
            .toDouble();
        final artworkKey = track == null
            ? 'album-artwork:loading'
            : 'album-artwork:${track.id}:${track.coverUrl ?? ''}:'
                  '${identityHashCode(track.coverBytes)}';
        final metadataKey = track == null
            ? 'album-metadata:loading'
            : 'album-metadata:${track.id}:${track.album}:'
                  '${track.sourceLabel}:${track.qualityLabel}';
        return Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(vertical: wide ? 8 : 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: resolvedCoverSize,
                  // Dragging the record down dismisses the player. This sits
                  // inside the scroll view on purpose so it wins the arena,
                  // and covers only the artwork so the metadata below can
                  // still be scrolled on short screens.
                  child: PlayerPullHandle(
                    child: TrackChangeSwitcher(
                      transitionKey: artworkKey,
                      incomingOffset: Offset.zero,
                      scaleBegin: 0.88,
                      expand: true,
                      child: track == null
                          ? _LoadingAlbumArtwork(size: resolvedCoverSize)
                          : SpinningCoverArt(
                              track: track,
                              size: resolvedCoverSize,
                              placeholder: ColoredBox(
                                color: Colors.white.withValues(alpha: 0.34),
                                child: Center(
                                  child: Icon(
                                    Icons.album_rounded,
                                    size: 56,
                                    color: playerMuted(context),
                                  ),
                                ),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.16),
                                  blurRadius: 28,
                                  offset: const Offset(0, 18),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
                SizedBox(height: wide ? 18 : 22),
                TrackChangeSwitcher(
                  transitionKey: metadataKey,
                  incomingOffset: const Offset(0.12, 0),
                  child: track == null
                      ? const SizedBox(height: 105)
                      : _AlbumMetadata(track: track),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LoadingAlbumArtwork extends StatelessWidget {
  const _LoadingAlbumArtwork({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: CircularProgressIndicator(
        color: playerInk(context),
        strokeWidth: 3,
      ),
    );
  }
}

class _AlbumMetadata extends StatelessWidget {
  const _AlbumMetadata({required this.track});

  final PlayerTrack track;

  @override
  Widget build(BuildContext context) {
    final album = track.album.trim().isEmpty ? '未知专辑' : track.album.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          album,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: playerMuted(context).withValues(alpha: 0.78),
            fontSize: 15,
            fontWeight: FontWeight.w500,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            _PlaybackQualityControl(track: track),
            _PlayerTag(
              key: const ValueKey('player-source-chip'),
              label: _sourceLabel(track),
            ),
          ],
        ),
      ],
    );
  }

  String _sourceLabel(PlayerTrack track) {
    if (track.isLocal) return '本地';
    final source = track.sourceLabel.trim();
    return source.isEmpty ? '其他' : source;
  }
}

class _PlaybackQualityControl extends ConsumerWidget {
  const _PlaybackQualityControl({required this.track});

  final PlayerTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (track.isLocal) {
      return _PlayerTag(
        key: const ValueKey('player-quality-tag'),
        label: track.qualityLabel,
      );
    }

    final loading = ref.watch(
      playerControllerProvider.select((state) => state.loading),
    );
    final parsedCurrent = Quality.tryFromCode(track.qualityLabel);
    final allOptions = track.availableQualityOptions.isEmpty
        ? [
            for (final quality
                in track.availableQualities.isEmpty
                    ? [?parsedCurrent]
                    : track.availableQualities)
              QualityOption(type: quality),
          ]
        : track.availableQualityOptions;
    final options = [
      for (final option in allOptions)
        if (_knownQualitySize(option) != null) option,
    ];
    final canSwitch = !loading && options.length > 1;

    return Tooltip(
      message: canSwitch ? '切换音质' : '当前音质',
      child: _PlayerTag(
        key: const ValueKey('player-quality-tag'),
        actionKey: const ValueKey('player-quality-button'),
        label: _qualityTagLabel(parsedCurrent, track.qualityLabel),
        loading: loading,
        showDropdown: options.length > 1,
        onTap: canSwitch
            ? () => unawaited(
                _showPlaybackQualitySheet(
                  context,
                  ref,
                  options: options,
                  current: parsedCurrent,
                ),
              )
            : null,
      ),
    );
  }
}

Future<void> _showPlaybackQualitySheet(
  BuildContext context,
  WidgetRef ref, {
  required List<QualityOption> options,
  required Quality? current,
}) async {
  final controller = ref.read(playerControllerProvider.notifier);
  final scheme = Theme.of(context).colorScheme;
  final selected = await showModalBottomSheet<Quality>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    barrierColor: scheme.scrim.withValues(alpha: 0.36),
    builder: (_) => _PlaybackQualitySheet(options: options, current: current),
  );
  if (selected == null || selected == current) return;
  await controller.switchQuality(selected);
}

class _PlaybackQualitySheet extends StatelessWidget {
  const _PlaybackQualitySheet({required this.options, required this.current});

  final List<QualityOption> options;
  final Quality? current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    return SafeArea(
      key: const ValueKey('player-quality-sheet'),
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
                child: Text(
                  '播放音质',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: options.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final option = options[index];
                    final selected = option.type == current;
                    return ListTile(
                      key: ValueKey(
                        'player-quality-option-${option.type.code}',
                      ),
                      minTileHeight: 62,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      selected: selected,
                      selectedTileColor: scheme.secondaryContainer.withValues(
                        alpha: 0.72,
                      ),
                      title: Text(
                        _qualityName(option.type),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('文件大小 ${_knownQualitySize(option)!}'),
                      trailing: selected
                          ? Icon(
                              Icons.check_circle_rounded,
                              color: scheme.onSecondaryContainer,
                            )
                          : null,
                      onTap: () => Navigator.of(context).pop(option.type),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerTag extends StatelessWidget {
  const _PlayerTag({
    super.key,
    required this.label,
    this.actionKey,
    this.loading = false,
    this.showDropdown = false,
    this.onTap,
  });

  final String label;
  final Key? actionKey;
  final bool loading;
  final bool showDropdown;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: playerInk(context).withValues(alpha: 0.10)),
    );
    return SizedBox(
      width: 80,
      height: 28,
      child: Material(
        color: Colors.white.withValues(alpha: 0.28),
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: actionKey,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: _chipTextStyle(context),
                  ),
                ),
                SizedBox.square(
                  dimension: 14,
                  child: loading
                      ? Padding(
                          padding: const EdgeInsets.all(2),
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            color: playerMuted(context),
                          ),
                        )
                      : showDropdown
                      ? Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 14,
                          color: playerMuted(context),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _qualityTagLabel(Quality? quality, String fallback) {
  return switch (quality) {
    Quality.atmosPlus => 'Atmos+',
    Quality.flac24bit => '24bit',
    _ => fallback,
  };
}

String _qualityName(Quality quality) {
  return switch (quality) {
    Quality.master => '母带音质',
    Quality.atmosPlus => 'Atmos Plus',
    Quality.atmos => '杜比全景声',
    Quality.hires => 'Hi-Res',
    Quality.flac24bit => '24-bit FLAC',
    Quality.flac => '无损 FLAC',
    Quality.wav => 'WAV',
    Quality.ape => 'APE',
    Quality.k320 => '高品质 320K',
    Quality.k192 => '较高品质 192K',
    Quality.k128 => '标准品质 128K',
  };
}

String? _knownQualitySize(QualityOption option) {
  final size = option.size?.trim();
  return size == null || size.isEmpty ? null : size;
}

TextStyle _chipTextStyle(BuildContext context) {
  return TextStyle(
    color: playerMuted(context),
    fontSize: 10.5,
    fontWeight: FontWeight.w500,
    height: 1.1,
  );
}
