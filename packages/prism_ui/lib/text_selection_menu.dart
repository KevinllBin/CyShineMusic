import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import 'package:prism_ui/edit_menu.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/l10n.dart';
import 'package:prism_ui/popup.dart';
import 'package:prism_ui/surface.dart';
import 'package:prism_ui/text_selection_controls.dart';

/// The selection menu of every text widget in place of the toolbar each
/// platform draws its own way: iOS's edit menu by touch, a [PopupMenu] by
/// pointer. The text widget still decides when it shows; this only mirrors
/// that into a route.
class TextSelectionMenu extends StatefulWidget {
  const TextSelectionMenu({
    super.key,
    required this.owner,
    required this.anchors,
    required this.buttonItems,
  });

  static Widget editableText(BuildContext context, EditableTextState state) {
    final value = state.textEditingValue;
    final selection = value.selection;
    final field = state.widget;
    // Apple platforms drop select all once text is selected, macOS always.
    final canSelectAll =
        field.enableInteractiveSelection &&
        !(field.readOnly && field.obscureText) &&
        value.text.isNotEmpty &&
        !(selection.start == 0 && selection.end == value.text.length);
    return TextSelectionMenu(
      owner: state.context,
      anchors: state.contextMenuAnchors,
      buttonItems: [
        for (final item in state.contextMenuButtonItems)
          if (item.type != ContextMenuButtonType.selectAll) item,
        if (!isDesktopPlatform &&
            selection.isCollapsed &&
            canSelectAll &&
            !field.obscureText)
          ContextMenuButtonItem(
            label: UiLocalizations.of(context).select,
            onPressed: () => _selectWord(state),
          ),
        if (canSelectAll)
          ContextMenuButtonItem(
            type: ContextMenuButtonType.selectAll,
            onPressed: () => state.selectAll(SelectionChangedCause.toolbar),
          ),
      ],
    );
  }

  static void _selectWord(EditableTextState state) {
    final value = state.textEditingValue;
    final word = state.renderEditable.getWordBoundary(value.selection.base);
    state.userUpdateTextEditingValue(
      value.copyWith(
        selection: TextSelection(
          baseOffset: word.start,
          extentOffset: word.end,
        ),
      ),
      SelectionChangedCause.toolbar,
    );
  }

  static Widget selectableRegion(
    BuildContext context,
    SelectableRegionState state,
  ) {
    return TextSelectionMenu(
      owner: state.context,
      anchors: state.contextMenuAnchors,
      buttonItems: state.contextMenuButtonItems,
    );
  }

  final BuildContext owner;
  final TextSelectionToolbarAnchors anchors;
  final List<ContextMenuButtonItem> buttonItems;

  @override
  State<TextSelectionMenu> createState() => _TextSelectionMenuState();
}

class _TextSelectionMenuState extends State<TextSelectionMenu> {
  PopupRoute<void>? _route;
  final _selection = ValueNotifier<Rect>(Rect.zero);
  final _items = ValueNotifier<List<PopupMenuItem>>(const []);

  @override
  void initState() {
    super.initState();
    _scheduleOpen();
  }

  @override
  void didUpdateWidget(TextSelectionMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateSelection();
      }
    });
    if (_route == null ||
        listEquals(
          _keysOf(widget.buttonItems),
          _keysOf(oldWidget.buttonItems),
        )) {
      return;
    }
    if (_route is EditMenuRoute) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _updateItems();
        }
      });
      return;
    }
    _close();
    _scheduleOpen();
  }

  @override
  void dispose() {
    _close();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selection.dispose();
      _items.dispose();
    });
    super.dispose();
  }

  static List<Object?> _keysOf(List<ContextMenuButtonItem> items) => [
    for (final item in items) (item.type, item.label),
  ];

  // This runs while the tree builds or unmounts, when nothing may push or pop.
  void _scheduleOpen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _route == null) {
        _open();
      }
    });
  }

  void _close() {
    final route = _route;
    if (route == null) {
      return;
    }
    _route = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isCurrent) {
        route.navigator!.pop();
      } else if (route.isActive) {
        route.navigator!.removeRoute(route);
      }
    });
  }

  void _updateItems() {
    final items = _menuItems();
    if (items.isEmpty) {
      _close();
    } else {
      _items.value = items;
    }
  }

  List<PopupMenuItem> _menuItems() {
    final localizations = UiLocalizations.of(widget.owner);
    PopupMenuItem item(Glyph glyph, String label, VoidCallback onPressed) {
      return PopupMenuItem(glyph: glyph, label: label, onPressed: onPressed);
    }

    // Look up, search, share and Live Text exist on some platforms only.
    return [
      for (final button in widget.buttonItems)
        if (button.onPressed case final onPressed?)
          ?switch (button.type) {
            ContextMenuButtonType.cut => item(
              Glyphs.cut,
              localizations.cut,
              onPressed,
            ),
            ContextMenuButtonType.copy => item(
              Glyphs.copy,
              localizations.copy,
              onPressed,
            ),
            ContextMenuButtonType.paste => item(
              Glyphs.paste,
              localizations.paste,
              onPressed,
            ),
            ContextMenuButtonType.selectAll => item(
              Glyphs.selectAll,
              localizations.selectAll,
              onPressed,
            ),
            ContextMenuButtonType.custom
                when button.label == localizations.select =>
              item(Glyphs.selectAll, button.label!, onPressed),
            _ => null,
          },
    ];
  }

  void _open() {
    final owner = widget.owner;
    if (!owner.mounted) {
      return;
    }
    final items = _menuItems();
    final navigator = Navigator.maybeOf(owner);
    final navigatorBox = navigator?.context.findRenderObject();
    if (items.isEmpty || navigator == null || navigatorBox is! RenderBox) {
      return;
    }
    final route = _route = isDesktopPlatform
        ? _popupRoute(navigatorBox, items)
        : _editMenuRoute(navigatorBox, items);
    unawaited(navigator.push(route).whenComplete(() => _handlePopped(route)));
  }

  PopupRoute<void> _editMenuRoute(
    RenderBox navigatorBox,
    List<PopupMenuItem> items,
  ) {
    _updateSelection();
    _items.value = items;
    return EditMenuRoute(
      barrierLabel: UiLocalizations.of(widget.owner).close,
      elevated: ElevatedSurfaceTheme.isIn(widget.owner),
      items: _items,
      selection: _selection,
    );
  }

  void _updateSelection() {
    final box = Navigator.maybeOf(widget.owner)?.context.findRenderObject();
    if (box is! RenderBox || !box.attached) {
      return;
    }
    final anchors = widget.anchors;
    _selection.value = Rect.fromPoints(
      box.globalToLocal(anchors.primaryAnchor),
      box.globalToLocal(anchors.secondaryAnchor ?? anchors.primaryAnchor),
    );
  }

  PopupRoute<void> _popupRoute(
    RenderBox navigatorBox,
    List<PopupMenuItem> items,
  ) {
    Rect anchor() {
      return navigatorBox.globalToLocal(widget.anchors.primaryAnchor) &
          Size.zero;
    }

    final secondary = widget.anchors.secondaryAnchor;
    return AnchoredPopupRoute<void>(
      barrierLabel: UiLocalizations.of(widget.owner).close,
      placement: PopupPlacement.belowPoint,
      modal: false,
      elevated: ElevatedSurfaceTheme.isIn(widget.owner),
      anchorOf: anchor,
      avoid: secondary == null
          ? null
          : Rect.fromPoints(
              anchor().topLeft,
              navigatorBox.globalToLocal(secondary),
            ),
      // Otherwise a tap on an item reads as a tap outside, and the text
      // drops its focus and selection before the item runs.
      builder: (_) => TapRegion(
        groupId: SelectableRegion,
        child: TextFieldTapRegion(child: PopupMenu(items: items)),
      ),
    );
  }

  void _handlePopped(PopupRoute<void> route) {
    if (!identical(_route, route) || !mounted) {
      return;
    }
    _route = null;
    ContextMenuController.removeAny();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
