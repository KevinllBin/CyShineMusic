import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../storage/settings_store.dart';

bool liquidGlassEnabledOf(BuildContext context) => ProviderScope.containerOf(
  context,
  listen: false,
).read(settingsProvider).liquidGlassEnabled;

Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  String? barrierLabel,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
}) {
  if (!liquidGlassEnabledOf(context)) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      backgroundColor: backgroundColor,
      elevation: elevation,
      shape: shape,
      clipBehavior: clipBehavior,
      constraints: constraints,
      barrierColor: barrierColor,
      barrierLabel: barrierLabel,
      isScrollControlled: isScrollControlled,
      useRootNavigator: useRootNavigator,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      useSafeArea: useSafeArea,
      routeSettings: routeSettings,
    );
  }
  final theme = Theme.of(context);
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    clipBehavior: Clip.none,
    // Only the glass sheet draws the requested handle. Material otherwise
    // inherits showDragHandle from the app theme and adds a second bar.
    showDragHandle: false,
    builder: (sheetContext) => LiquidGlassSheet(
      anchor: LiquidGlassSheetAnchor.attached,
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      foregroundColor: theme.colorScheme.onSurface,
      style: LiquidGlassSheet.defaultStyle.copyWith(
        color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.30),
      ),
      grabber: showDragHandle ?? theme.bottomSheetTheme.showDragHandle ?? false,
      child: MediaQuery.removePadding(
        context: sheetContext,
        removeBottom: true,
        child: Builder(builder: builder),
      ),
    ),
    constraints: constraints,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
  );
}

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
}) {
  if (liquidGlassEnabledOf(context)) {
    return showLiquidGlassDialog<T>(
      context: context,
      builder: builder,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor ?? Colors.black54,
      barrierLabel: barrierLabel,
      useSafeArea: useSafeArea,
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
      anchorPoint: anchorPoint,
    );
  }
  return showDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
  );
}

class AppAlertDialog extends ConsumerWidget {
  const AppAlertDialog({
    super.key,
    this.icon,
    this.title,
    this.content,
    this.actions,
    this.scrollable = false,
    this.contentPadding,
    this.actionsPadding,
  });

  final Widget? icon;
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final bool scrollable;
  final EdgeInsetsGeometry? contentPadding;
  final EdgeInsetsGeometry? actionsPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glass = ref.watch(
      settingsProvider.select((settings) => settings.liquidGlassEnabled),
    );
    if (!glass) {
      return AlertDialog(
        icon: icon,
        title: title,
        content: content,
        contentPadding: contentPadding,
        actionsPadding: actionsPadding,
        actions: actions,
        scrollable: scrollable,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: MediaQuery.viewInsetsOf(context) + const EdgeInsets.all(24),
      child: LiquidGlassAlertDialog(
        icon: icon,
        iconColor: scheme.primary,
        title: title,
        titleTextStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        content: content,
        contentTextStyle: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        actions: actions,
        scrollable: true,
        contentPadding: contentPadding ?? const EdgeInsets.only(bottom: 24),
        actionsPadding: actionsPadding ?? EdgeInsets.zero,
        width: 560,
        style: LiquidGlassDialog.defaultStyle.copyWith(
          color: scheme.surfaceContainerHigh.withValues(alpha: 0.34),
        ),
      ),
    );
  }
}

/// For panels whose DraggableScrollableSheet/FractionallySizedBox owns sizing.
class AppSheetSurface extends ConsumerWidget {
  const AppSheetSurface({
    super.key,
    required this.color,
    required this.child,
    this.grabber = false,
    this.borderRadius = const BorderRadius.vertical(top: Radius.circular(30)),
  });

  final Color color;
  final BorderRadius borderRadius;
  final Widget child;
  final bool grabber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glass = ref.watch(
      settingsProvider.select((settings) => settings.liquidGlassEnabled),
    );
    if (!glass) {
      return Material(
        color: color,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: child,
      );
    }
    return LiquidGlassSheet(
      // The existing inner panel owns its SafeArea and keyboard handling.
      safeArea: false,
      anchor: LiquidGlassSheetAnchor.attached,
      grabber: grabber,
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      style: LiquidGlassSheet.defaultStyle.copyWith(
        color: color.withValues(alpha: 0.30),
        shape: LiquidGlassShape.continuousRoundedRectangle(
          cornerRadius: borderRadius.topLeft.x,
        ),
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}
