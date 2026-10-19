import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

class GlassChoiceOption {
  const GlassChoiceOption({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;
}

/// A lazily loaded choice menu whose title capsule becomes the options panel.
class GlassChoiceMenu extends StatefulWidget {
  const GlassChoiceMenu({
    super.key,
    required this.optionsBuilder,
    required this.anchorBuilder,
    this.maximumWidth = 240,
    this.maximumHeight = 300,
  });

  final List<GlassChoiceOption> Function() optionsBuilder;
  final Widget Function(bool expanded, VoidCallback onPressed) anchorBuilder;
  final double maximumWidth;
  final double maximumHeight;

  @override
  State<GlassChoiceMenu> createState() => _GlassChoiceMenuState();
}

class _GlassChoiceMenuState extends State<GlassChoiceMenu> {
  final _portal = OverlayPortalController()..show();
  List<GlassChoiceOption> _options = const [];
  LocalHistoryEntry? _history;
  bool _open = false;
  bool _wide = false;

  @override
  void didUpdateWidget(covariant GlassChoiceMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_open) _options = widget.optionsBuilder();
  }

  void _show() {
    if (_open) return;
    setState(() {
      _options = widget.optionsBuilder();
      _open = true;
      _wide = true;
    });
    final route = ModalRoute.of(context);
    if (route == null) return;
    late final LocalHistoryEntry entry;
    entry = LocalHistoryEntry(
      onRemove: () {
        if (!identical(_history, entry)) return;
        _history = null;
        _close();
      },
    );
    _history = entry;
    route.addLocalHistoryEntry(entry);
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    final entry = _history;
    _history = null;
    entry?.remove();
  }

  void _select(GlassChoiceOption option) {
    if (!_open || !option.enabled) return;
    _close();
    option.onSelected();
  }

  @override
  void dispose() {
    final entry = _history;
    _history = null;
    entry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final anchorChild = widget.anchorBuilder(_open, _show);
    final rowHeight = math.max(48.0, media.textScaler.scale(14) * 1.25 + 24);
    final portal = OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayLocation: OverlayChildLocation.rootOverlay,
      child: IgnorePointer(child: Opacity(opacity: 0, child: anchorChild)),
      overlayChildBuilder: (context, info) {
        final anchor = MatrixUtils.transformRect(
          info.childPaintTransform,
          Offset.zero & info.childSize,
        );
        final menuWidth = math.max(
          anchor.width,
          math.min(
            widget.maximumWidth,
            info.overlaySize.width - anchor.left - 12,
          ),
        );
        final menuHeight = math.max(
          anchor.height,
          math.min(
            _options.length * rowHeight + 12,
            math.min(
              widget.maximumHeight,
              info.overlaySize.height -
                  anchor.top -
                  media.viewPadding.bottom -
                  12,
            ),
          ),
        );
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            if (_open)
              Positioned.fill(
                key: const ValueKey('glass-choice-barrier'),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _close,
                ),
              ),
            Positioned(
              key: const ValueKey('glass-choice-position'),
              left: anchor.left,
              top: anchor.top,
              width: _wide ? menuWidth : anchor.width,
              height: _wide ? menuHeight : anchor.height,
              child: LiquidGlassMorph(
                alignment: Alignment.topLeft,
                motion: LiquidGlassMorphMotion.fluid,
                smoothness: 28,
                style: LiquidGlassStyle(
                  shape: LiquidGlassShape.continuousRoundedRectangle(
                    cornerRadius: _open ? 24 : anchor.height / 2,
                  ),
                  color: scheme.surfaceContainerHigh.withValues(alpha: 0.32),
                  blur: 4,
                ),
                onEnd: () {
                  if (!_open && _wide) setState(() => _wide = false);
                },
                child: _open
                    ? SizedBox(
                        key: const ValueKey('glass-choice-open'),
                        width: menuWidth,
                        height: menuHeight,
                        child: Material(
                          type: MaterialType.transparency,
                          child: ListView(
                            padding: const EdgeInsets.all(6),
                            children: [
                              for (final option in _options)
                                Semantics(
                                  selected: option.selected,
                                  child: TextButton.icon(
                                    style: TextButton.styleFrom(
                                      alignment: Alignment.centerLeft,
                                      foregroundColor: option.selected
                                          ? scheme.primary
                                          : scheme.onSurface,
                                      minimumSize: Size(0, rowHeight),
                                    ),
                                    onPressed: option.enabled
                                        ? () => _select(option)
                                        : null,
                                    icon: Icon(
                                      option.selected
                                          ? Icons.check_circle_rounded
                                          : Icons
                                                .radio_button_unchecked_rounded,
                                      size: 20,
                                    ),
                                    label: Text(
                                      option.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      )
                    : SizedBox(
                        key: const ValueKey('glass-choice-closed'),
                        width: anchor.width,
                        height: anchor.height,
                        child: anchorChild,
                      ),
              ),
            ),
          ],
        );
      },
    );
    if (Router.maybeOf(context)?.backButtonDispatcher == null) return portal;
    return BackButtonListener(
      onBackButtonPressed: () async {
        if (!_open) return false;
        _close();
        return true;
      },
      child: portal,
    );
  }
}
