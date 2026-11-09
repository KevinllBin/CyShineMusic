import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/icons.dart' as glyph;

import 'settings_style.dart';
import '../../../core/ui/widgets/settings_route_page.dart';

class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    this.title,
    required this.children,
    this.insetContent = false,
  });

  final String? title;
  final List<Widget> children;
  final bool insetContent;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (title != null && title!.isNotEmpty) prism.ListHeader(title: title!),
      SettingsGroup(
        children: insetContent
            ? [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ]
            : children.where((child) => child is! SizedBox).toList(),
      ),
    ],
  );
}

/// The section owns its corners, including rows with separate action buttons
/// and footers that do not paint a DecorationListItem background of their own.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ClipRSuperellipse(
    borderRadius: prism.AppRadius.xl,
    child: ColoredBox(
      color: prism.SurfaceLevel.card.colorOf(
        prism.Theme.of(context).colorScheme,
      ),
      child: prism.generateGroup(children),
    ),
  );
}

Widget _positionedRow(BuildContext context, Widget row) =>
    prism.ItemPositionProvider.of(context) != null
    ? row
    : prism.ItemPositionProvider(
        position: prism.ItemPosition.startAndEnd,
        child: row,
      );

class SettingsAction extends StatelessWidget {
  const SettingsAction({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle = '',
    this.onTap,
    this.destination,
    this.value,
    this.trailing,
    this.trailingWidget,
    this.interactionKey,
    this.onTapDown,
    this.showIcon = true,
  }) : assert(onTap != null || destination != null);

  final IconData icon;
  final String title;
  final String subtitle;
  final String? value;
  final VoidCallback? onTap;
  final String? destination;
  final IconData? trailing;
  final Widget? trailingWidget;
  final Key? interactionKey;
  final GestureTapDownCallback? onTapDown;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget? tail =
        trailingWidget ??
        (trailing == null
            ? null
            : trailing == Icons.chevron_right ||
                  trailing == Icons.chevron_right_rounded ||
                  trailing == Symbols.chevron_right
            ? const glyph.GlyphIcon(glyph.Glyphs.chevronForward, size: 16)
            : Icon(trailing, size: 18, color: scheme.onSurfaceVariant));
    if (value case final value? when value.isNotEmpty) {
      tail = Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.3,
            ),
            child: Tooltip(
              message: value,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
              ),
            ),
          ),
          ?tail,
        ],
      );
    }
    Widget row(VoidCallback? action) => prism.DecorationListItem(
      key: interactionKey,
      leading: showIcon ? SettingsSymbolBubble(icon: icon) : null,
      title: Text(title, maxLines: 2),
      horizontalTitleGap: 12,
      trailing: tail,
      onPressed: action,
    );
    if (destination case final location?) {
      final position =
          prism.ItemPositionProvider.of(context)?.position ??
          prism.ItemPosition.startAndEnd;
      return prism.OpenContainer<void>(
        transition: prism.OpenContainerTransition.zoom,
        clipBehavior: Clip.none,
        closedShape: prism.AppShape.of(prism.listItemRadiusOf(position)),
        closedBuilder: (_, open) =>
            prism.ItemPositionProvider(position: position, child: row(open)),
        // The destination is supplied by router.dart, the owner of page imports.
        onOpen: (createRoute) {
          // A native-tab tap can replace this route with `go('/settings')`
          // instead of popping it. Do not keep OpenContainer's opening lock
          // waiting for the push future, which only completes after a pop.
          unawaited(
            context.push<void>(
              location,
              extra: SettingsContainerOrigin(createRoute),
            ),
          );
        },
      );
    }
    return _positionedRow(context, row(onTap));
  }
}

class SettingsSwitchAction extends StatelessWidget {
  const SettingsSwitchAction({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle = '',
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => _positionedRow(
    context,
    prism.DecorationListItem(
      leading: SettingsSymbolBubble(icon: icon),
      title: Text(title, maxLines: 2),
      horizontalTitleGap: 12,
      onPressed: () => onChanged(!value),
      trailing: prism.Switch(value: value, onChanged: onChanged),
    ),
  );
}

class DebugModeRow extends StatelessWidget {
  const DebugModeRow({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SettingsSwitchAction(
    icon: Icons.bug_report_outlined,
    title: '调试模式',
    value: value,
    onChanged: onChanged,
  );
}
