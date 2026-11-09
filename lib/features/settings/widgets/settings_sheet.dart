import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

/// Uses the same detents, stacked-sheet motion and rubber band as Prism UI.
Future<T?> showSettingsSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useRootNavigator = true,
  bool showDragHandle = true,
  Color? backgroundColor,
  double heightFraction = 0.5,
  double maxHeight = 480,
  List<double>? detents,
}) {
  assert(heightFraction > 0 && heightFraction <= 1);
  final host = useRootNavigator
      ? Navigator.of(context, rootNavigator: true).context
      : context;
  final available =
      MediaQuery.sizeOf(host).height - MediaQuery.viewPaddingOf(host).top;
  final effectiveFraction =
      detents != null && detents.isNotEmpty ? detents.first : heightFraction;
  final detent = math
      .min(effectiveFraction, maxHeight / available)
      .clamp(0.1, 1.0);
  Widget content(BuildContext sheetContext) => Material(
    color:
        backgroundColor ??
        prism.SurfaceLevel.page.colorOf(
          prism.Theme.of(sheetContext).colorScheme,
        ),
    child: Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        if (showDragHandle)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(sheetContext).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        Expanded(child: builder(sheetContext)),
      ],
    ),
  );
  if (prism.ViewScope.isMobileOf(host)) {
    return Navigator.of(host).push<T>(
      prism.SnapSheetRoute<T>(
        detents: detents ?? [detent],
        fitsContent: false,
        floating: false,
        sheetBarrierColor: Theme.of(
          host,
        ).colorScheme.scrim.withValues(alpha: 0.36),
        barrierLabel: '关闭',
        builder: (sheetContext, controller) => PrimaryScrollController(
          controller: controller!,
          child: content(sheetContext),
        ),
      ),
    );
  }
  return prism.showSheet<T>(
    context: host,
    builder: (context) => SizedBox(
      height: math.min(maxHeight, available * effectiveFraction),
      child: content(context),
    ),
  );
}

/// A scrollable body and an action area that stays above the bottom safe inset.
class SettingsSheetLayout extends StatelessWidget {
  const SettingsSheetLayout({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Text(
            title,
            style: prism.AppTextStyle.title3.of(context, emphasized: true),
          ),
        ),
        Expanded(child: body),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Row(
            spacing: 12,
            children: [for (final action in actions) Expanded(child: action)],
          ),
        ),
      ],
    ),
  );
}

Future<T?> showSettingsDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useRootNavigator = true,
  bool barrierDismissible = true,
}) => prism.showFloatingDialog<T>(
  context: useRootNavigator
      ? Navigator.of(context, rootNavigator: true).context
      : context,
  dismissible: barrierDismissible,
  child: Builder(builder: builder),
);
