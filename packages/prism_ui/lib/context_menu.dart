import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/l10n.dart';

import 'focus.dart';
import 'popup.dart';
import 'sortable.dart';
import 'surface.dart';

const _touchDevices = {
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
};

/// A touch long press, the menu key and, on a remote, a held select key keep
/// the menu clear of the row, which a finger or the focus highlight would
/// otherwise leave covered.
class ContextMenuRegion extends StatefulWidget {
  final List<PopupMenuItem>? menuItems;
  final Widget child;

  const ContextMenuRegion({super.key, this.menuItems, required this.child});

  @override
  State<ContextMenuRegion> createState() => _ContextMenuRegionState();
}

class _ContextMenuRegionState extends State<ContextMenuRegion> {
  Timer? _holdTimer;
  LogicalKeyboardKey? _heldKey;
  AnchoredPopupRoute<void>? _menu;

  bool get _enabled {
    final items = widget.menuItems;
    return items != null &&
        items.isNotEmpty &&
        !SortableItem.isSorting(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _closeUnlessEnabled();
  }

  @override
  void didUpdateWidget(ContextMenuRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _closeUnlessEnabled();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _closeMenu();
    super.dispose();
  }

  /// A row withdraws its menu while its item updates, which the open menu
  /// would otherwise still act on.
  void _closeUnlessEnabled() {
    if (_enabled) {
      return;
    }
    _holdTimer?.cancel();
    _heldKey = null;
    _closeMenu();
  }

  void _closeMenu() {
    final menu = _menu;
    if (menu == null) {
      return;
    }
    _menu = null;
    // This runs while the tree builds or unmounts, when nothing may pop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (menu.isCurrent) {
        menu.navigator!.pop();
      }
    });
  }

  void _open(Offset globalPosition, {bool avoid = false}) {
    final items = widget.menuItems;
    final navigator = Navigator.maybeOf(context);
    final navigatorBox = navigator?.context.findRenderObject();
    final box = context.findRenderObject();
    if (items == null ||
        items.isEmpty ||
        navigator == null ||
        navigatorBox is! RenderBox ||
        box is! RenderBox ||
        !box.hasSize) {
      return;
    }
    final point = navigatorBox.globalToLocal(globalPosition);
    final rowRect = MatrixUtils.transformRect(
      box.getTransformTo(navigatorBox),
      Offset.zero & box.size,
    );
    final menu = _menu = AnchoredPopupRoute<void>(
      barrierLabel: UiLocalizations.of(context).close,
      placement: PopupPlacement.belowPoint,
      elevated: ElevatedSurfaceTheme.isIn(context),
      anchorOf: () => point & Size.zero,
      avoid: avoid ? rowRect : null,
      builder: (_) => PopupMenu(items: items),
    );
    unawaited(
      navigator.push(menu).whenComplete(() {
        if (identical(_menu, menu)) {
          _menu = null;
        }
      }),
    );
  }

  void _openAtRow() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return;
    }
    _open(box.localToGlobal(box.size.bottomLeft(Offset.zero)), avoid: true);
  }

  // Swallows the rest of the hold, which would otherwise repeat into the menu
  // as presses of its first item.
  void _handleHold() {
    final key = _heldKey;
    _heldKey = null;
    KeyEventResult swallow(KeyEvent event) {
      if (event.logicalKey != key) {
        return KeyEventResult.ignored;
      }
      if (event is KeyUpEvent) {
        FocusManager.instance.removeEarlyKeyEventHandler(swallow);
      }
      return KeyEventResult.handled;
    }

    FocusManager.instance.addEarlyKeyEventHandler(swallow);
    _openAtRow();
  }

  KeyEventResult _handleRemoteSelect(KeyEvent event) {
    final key = event.logicalKey;
    switch (event) {
      case KeyDownEvent():
        _heldKey = key;
        _holdTimer?.cancel();
        _holdTimer = Timer(kLongPressTimeout, _handleHold);
      case KeyRepeatEvent():
        if (key != _heldKey) {
          return KeyEventResult.ignored;
        }
      case KeyUpEvent():
        if (key != _heldKey) {
          return KeyEventResult.ignored;
        }
        _heldKey = null;
        _holdTimer?.cancel();
        final focused = FocusManager.instance.primaryFocus?.context;
        if (focused != null) {
          Actions.maybeInvoke(focused, const ActivateIntent());
        }
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _handleKey(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.contextMenu ||
        (key == LogicalKeyboardKey.f10 &&
            HardwareKeyboard.instance.isShiftPressed)) {
      if (event is KeyDownEvent) {
        _openAtRow();
      }
      return KeyEventResult.handled;
    }
    if (remoteSelectKeys.contains(key) &&
        RemoteFocusAdapter.isEnabledOf(context)) {
      return _handleRemoteSelect(event);
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: enabled ? (_, event) => _handleKey(event) : null,
      child: RawGestureDetector(
        gestures: {
          if (enabled) ...{
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  () => TapGestureRecognizer(debugOwner: this),
                  (recognizer) =>
                      recognizer.onSecondaryTapUp = (details) =>
                          _open(details.globalPosition),
                ),
            LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  LongPressGestureRecognizer
                >(
                  () => LongPressGestureRecognizer(
                    debugOwner: this,
                    supportedDevices: _touchDevices,
                  ),
                  (recognizer) => recognizer.onLongPressStart = (details) {
                    Feedback.forLongPress(context);
                    _open(details.globalPosition, avoid: true);
                  },
                ),
          },
        },
        child: widget.child,
      ),
    );
  }
}
