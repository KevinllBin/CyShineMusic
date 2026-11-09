import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/icons.dart' as prism_glyph;

import '../../../core/ui/music_action_glyphs.dart';
import '../../../theme/app_motion.dart';

class PlaylistBatchDownloadBar extends StatelessWidget {
  const PlaylistBatchDownloadBar({
    super.key,
    required this.selectedCount,
    required this.downloadableCount,
    required this.submitting,
    required this.onRemove,
    required this.onDownload,
    required this.onPlaySelected,
  });

  final int selectedCount;
  final int downloadableCount;
  final bool submitting;
  final VoidCallback? onRemove;
  final VoidCallback? onDownload;
  final VoidCallback? onPlaySelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      key: const ValueKey('playlist-batch-bottom-bar'),
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: prism.GooSurface(
          color: scheme.surfaceContainer,
          glass: prism.LiquidGlassScope.of(context)
              ? prism.LiquidGlassStyle.pill(prism.Theme.of(context).colorScheme)
              : null,
          child: prism.GooPane(
            child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  Expanded(
                    child: _PlaylistBatchAction(
                      icon: MusicActionGlyphs.playlistRemove,
                      label: selectedCount == 0
                          ? '移出歌单'
                          : '移出 $selectedCount 首',
                      onPressed: submitting ? null : onRemove,
                      enabledColor: scheme.error,
                    ),
                  ),
                  Expanded(
                    child: _PlaylistBatchAction(
                      icon: MusicActionGlyphs.download,
                      label: submitting
                          ? '下载中...'
                          : downloadableCount == 0
                          ? '下载选中'
                          : '下载 $downloadableCount 首',
                      onPressed: submitting ? null : onDownload,
                    ),
                  ),
                  Expanded(
                    child: _PlaylistBatchAction(
                      icon: MusicActionGlyphs.playNext,
                      label: selectedCount == 0
                          ? '播放选中'
                          : '播放 $selectedCount 首',
                      onPressed: submitting ? null : onPlaySelected,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistBatchAction extends StatelessWidget {
  const _PlaylistBatchAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabledColor,
  });

  final prism_glyph.Glyph icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? enabledColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final color = enabled
        ? enabledColor ?? scheme.onSurfaceVariant
        : scheme.onSurface.withValues(alpha: 0.34);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          child: AnimatedOpacity(
            duration: AppMotion.short,
            opacity: enabled ? 1 : 0.72,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                prism_glyph.GlyphIcon(icon, size: 21, fill: 0, color: color),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
