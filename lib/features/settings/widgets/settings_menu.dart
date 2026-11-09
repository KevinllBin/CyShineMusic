import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;
import 'package:prism_ui/icons/icons.dart' as glyph;

import '../../../core/ui/radio_menu.dart';
import 'settings_action.dart';

class SettingsMenuOption extends RadioMenuOption {
  const SettingsMenuOption({
    required super.id,
    required super.label,
    required super.selected,
    required super.onSelected,
    super.enabled,
  });
}

class SettingsMenuAction extends StatefulWidget {
  const SettingsMenuAction({
    super.key,
    required this.menuId,
    required this.icon,
    required this.title,
    this.subtitle = '',
    required this.options,
    this.multiSelect = false,
    this.showSubtitle = true,
    this.showIcon = true,
    this.applyImmediately = true,
  });

  final String menuId;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<SettingsMenuOption> options;
  final bool multiSelect;
  final bool showSubtitle;
  final bool showIcon;
  final bool applyImmediately;

  @override
  State<SettingsMenuAction> createState() => _SettingsMenuActionState();
}

class _SettingsMenuActionState extends State<SettingsMenuAction> {
  late final _options = ValueNotifier(widget.options);

  @override
  void didUpdateWidget(covariant SettingsMenuAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _options.value = widget.options;
    });
  }

  @override
  void dispose() {
    _options.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.options.where((option) => option.selected).toList();
    final label = widget.multiSelect
        ? '已启用 ${selected.length} 项'
        : selected.isEmpty
        ? ''
        : selected.first.label;
    VoidCallback? openMenu;
    return SettingsAction(
      interactionKey: ValueKey('${widget.menuId}-anchor'),
      icon: widget.icon,
      showIcon: widget.showIcon,
      title: widget.title,
      onTap: () => openMenu?.call(),
      trailingWidget: prism.PopupAnchor(
        key: ValueKey(widget.menuId),
        targetBuilder: (open) {
          openMenu = open;
          return prism.TextButton(
            onPressed: open,
            style: prism.ButtonStyle.from(
              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.32,
                  ),
                  child: prism.PopupValueText(
                    label,
                    alignment: AlignmentDirectional.centerEnd,
                  ),
                ),
                const glyph.GlyphIcon(glyph.Glyphs.picker, size: 16),
              ],
            ),
          );
        },
        popupBuilder: (_) => ValueListenableBuilder(
          valueListenable: _options,
          builder: (_, options, _) => prism.PopupMenu(
            items: [
              for (final option in options)
                prism.PopupMenuItem(
                  label: option.label,
                  checked: option.selected,
                  keepsOpen: widget.multiSelect,
                  executeImmediately: widget.applyImmediately,
                  onPressed: option.enabled ? option.onSelected : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
