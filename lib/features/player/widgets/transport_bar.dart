import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../theme/app_motion.dart';
import '../player_controller.dart';
import 'playback_queue_sheet.dart';
import 'player_palette.dart';
import 'player_control_color.dart';
import 'player_slider_thumb_shape.dart';

class TransportBar extends ConsumerStatefulWidget {
  const TransportBar({super.key});

  @override
  ConsumerState<TransportBar> createState() => _TransportBarState();
}

class _TransportBarState extends ConsumerState<TransportBar> {
  /// 拖动和等待 seek 时保留目标进度，松手只提交一次。
  double? _dragMs;
  Object? _interactionToken;
  String? _trackId;

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(
      playerControllerProvider.select(
        (s) => (
          position: s.position,
          duration: s.duration,
          playing: s.playing,
          loading: s.loading,
          buffering: s.buffering,
          ended: s.processingState == PlayerProcessingState.completed,
          hasTrack: s.track != null,
          trackId: s.track?.id,
          playbackMode: s.playbackMode,
          queueCount: s.queue.isEmpty
              ? (s.track == null ? 0 : 1)
              : s.queue.length,
        ),
      ),
    );
    if (_trackId != vm.trackId) {
      _trackId = vm.trackId;
      _dragMs = null;
      _interactionToken = null;
    }
    final controller = ref.read(playerControllerProvider.notifier);
    final maxMs = math.max(1, vm.duration.inMilliseconds);
    final shownMs = (_dragMs ?? vm.position.inMilliseconds.toDouble()).clamp(
      0.0,
      maxMs.toDouble(),
    );
    final canControl = vm.hasTrack && !vm.loading;
    return PlayerControlColor(
      builder: (context, ink) {
        final controlColor = canControl ? ink : ink.withValues(alpha: 0.22);
        final indicatorTextColor =
            ThemeData.estimateBrightnessForColor(ink) == Brightness.dark
            ? Colors.white
            : Colors.black;
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  trackShape: const RoundedRectSliderTrackShape(),
                  activeTrackColor: ink,
                  inactiveTrackColor: ink.withValues(alpha: 0.22),
                  thumbColor: ink,
                  overlayColor: ink.withValues(alpha: 0.10),
                  thumbShape: PlayerSliderThumbShape(
                    disableAnimations: MediaQuery.disableAnimationsOf(context),
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                  showValueIndicator: ShowValueIndicator.onDrag,
                  valueIndicatorShape:
                      const RoundedRectSliderValueIndicatorShape(),
                  valueIndicatorColor: ink,
                  valueIndicatorTextStyle: TextStyle(
                    color: indicatorTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Slider(
                  key: ValueKey(vm.trackId),
                  value: shownMs,
                  max: maxMs.toDouble(),
                  label: _formatDuration(
                    Duration(milliseconds: shownMs.round()),
                  ),
                  semanticFormatterCallback: (value) =>
                      _formatDuration(Duration(milliseconds: value.round())),
                  onChangeStart: canControl
                      ? (value) => setState(() {
                          _interactionToken = Object();
                          _dragMs = value;
                        })
                      : null,
                  onChanged: canControl
                      ? (value) => setState(() => _dragMs = value)
                      : null,
                  onChangeEnd: canControl
                      ? (value) async {
                          final token = _interactionToken;
                          try {
                            await controller.seek(
                              Duration(milliseconds: value.round()),
                            );
                          } finally {
                            // 旧 seek 结束不能清掉换曲或后一次拖动的状态。
                            if (mounted &&
                                identical(_interactionToken, token)) {
                              setState(() {
                                _dragMs = null;
                                _interactionToken = null;
                              });
                            }
                          }
                        }
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Text(
                      _formatDuration(Duration(milliseconds: shownMs.round())),
                      style: _timeStyle(context),
                    ),
                    const Spacer(),
                    Text(
                      _formatDuration(vm.duration),
                      style: _timeStyle(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _PlaybackModeButton(
                    color: ink,
                    mode: vm.playbackMode,
                    enabled: vm.hasTrack,
                    onPressed: controller.cyclePlaybackMode,
                  ),
                  IconButton(
                    tooltip: '上一首',
                    onPressed: canControl ? controller.playPrevious : null,
                    icon: Icon(
                      Icons.skip_previous_rounded,
                      color: controlColor,
                      size: 38,
                    ),
                  ),
                  _PlayButton(
                    color: ink,
                    playing: vm.playing,
                    showSpinner: vm.loading || vm.buffering,
                    ended: vm.ended,
                    canControl: canControl,
                    controller: controller,
                  ),
                  IconButton(
                    tooltip: '下一首',
                    onPressed: canControl ? controller.playNext : null,
                    icon: Icon(
                      Icons.skip_next_rounded,
                      color: controlColor,
                      size: 38,
                    ),
                  ),
                  PlaybackQueueButton(
                    color: ink,
                    count: vm.queueCount,
                    enabled: vm.hasTrack,
                    onPressed: () => showPlaybackQueueSheet(context),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  TextStyle _timeStyle(BuildContext context) {
    return TextStyle(
      color: playerMuted(context),
      fontSize: 15,
      fontWeight: FontWeight.w500,
    );
  }

  String _formatDuration(Duration value) {
    final safe = value.isNegative ? Duration.zero : value;
    final hours = safe.inHours;
    final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _PlaybackModeButton extends StatelessWidget {
  const _PlaybackModeButton({
    required this.color,
    required this.mode,
    required this.enabled,
    required this.onPressed,
  });

  final PlayerPlaybackMode mode;
  final Color color;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final iconColor = enabled ? color : playerMuted(context);
    return IconButton(
      tooltip: mode.label,
      onPressed: enabled ? onPressed : null,
      style: IconButton.styleFrom(fixedSize: const Size.square(48)),
      icon: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppMotion.medium,
        switchInCurve: AppMotion.emphasizedDecelerate,
        switchOutCurve: AppMotion.emphasizedAccelerate,
        transitionBuilder: (child, animation) {
          final turns = Tween<double>(begin: -0.08, end: 0).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.82, end: 1).animate(animation),
              child: RotationTransition(turns: turns, child: child),
            ),
          );
        },
        child: Icon(
          _playbackModeIcon(mode),
          key: ValueKey(mode),
          color: iconColor,
          size: 25,
        ),
      ),
    );
  }
}

IconData _playbackModeIcon(PlayerPlaybackMode mode) {
  return switch (mode) {
    PlayerPlaybackMode.sequence => Icons.format_list_numbered_rounded,
    PlayerPlaybackMode.shuffle => Icons.shuffle_rounded,
    PlayerPlaybackMode.repeatOne => Icons.repeat_one_rounded,
  };
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.color,
    required this.playing,
    required this.showSpinner,
    required this.ended,
    required this.canControl,
    required this.controller,
  });

  final bool playing;
  final Color color;
  final bool showSpinner;
  final bool ended;
  final bool canControl;
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: canControl
            ? (ended ? controller.replay : controller.toggle)
            : null,
        child: SizedBox(
          width: 72,
          height: 72,
          child: Center(
            child: showSpinner
                ? SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: color,
                    ),
                  )
                : Icon(
                    ended
                        ? Icons.replay_rounded
                        : playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 56,
                    color: canControl ? color : color.withValues(alpha: 0.22),
                  ),
          ),
        ),
      ),
    );
  }
}
