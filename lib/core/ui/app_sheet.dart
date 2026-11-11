import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import '../../theme/app_theme.dart';
import 'widgets/app_navigation_button.dart';

/// All app sheets share Prism's scrolling, drag gestures and stacked motion.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useRootNavigator = true,
  bool showDragHandle = true,
  Color? backgroundColor,
  double heightFraction = 0.62,
  double maxHeight = 620,
  List<double>? detents,
  bool fitsContent = false,

  /// 一级 Sheet 贴住屏幕边缘；从已有 Sheet 继续打开的二级 Sheet
  /// 需要在调用处显式传入 `floating: true`，保留层叠留白。
  bool floating = false,
  bool neutralSurface = false,
}) {
  assert(heightFraction > 0 && heightFraction <= 1);
  final navigator = useRootNavigator
      ? Navigator.of(context, rootNavigator: true)
      : prism.sheetNavigatorOf(context);
  final host = navigator.context;
  final available =
      MediaQuery.sizeOf(host).height - MediaQuery.viewPaddingOf(host).top;
  final fraction = detents != null && detents.isNotEmpty
      ? detents.first
      : heightFraction;
  final detent = math.min(fraction, maxHeight / available).clamp(0.1, 1.0);

  Widget content(BuildContext sheetContext) {
    final theme = prism.Theme.of(sheetContext);
    final neutral = AppTheme.neutralSurfaces(
      Theme.of(sheetContext).colorScheme,
    );
    final colors = neutralSurface
        ? theme.colorScheme.copyWith(
            surface: neutral.surface,
            surfaceBright: neutral.surfaceBright,
            surfaceContainerLowest: neutral.surfaceContainerLowest,
            surfaceContainerLow: neutral.surfaceContainerLow,
            surfaceContainer: neutral.surfaceContainer,
            surfaceContainerHigh: neutral.surfaceContainerHigh,
            surfaceContainerHighest: neutral.surfaceContainerHighest,
            onSurface: neutral.onSurface,
            onSurfaceVariant: neutral.onSurfaceVariant,
            outline: neutral.outline,
            outlineVariant: neutral.outlineVariant,
          )
        : theme.colorScheme;
    return prism.Theme(
      data: theme.copyWith(colorScheme: colors),
      child: prism.SurfaceScope(
        level: prism.SurfaceLevel.page,
        child: Material(
          color: backgroundColor ?? prism.SurfaceLevel.page.colorOf(colors),
          child: Column(
            mainAxisSize: fitsContent ? MainAxisSize.min : MainAxisSize.max,
            children: [
              if (showDragHandle) const prism.SheetDragHandle(),
              Flexible(
                fit: fitsContent ? FlexFit.loose : FlexFit.tight,
                child: builder(sheetContext),
              ),
            ],
          ),
        ),
      ),
    );
  }

  if (prism.ViewScope.isMobileOf(host)) {
    return navigator.push<T>(
      prism.SnapSheetRoute<T>(
        detents: detents ?? [detent],
        fitsContent: fitsContent,
        floating: floating,
        backgroundColor:
            backgroundColor ??
            (neutralSurface
                ? AppTheme.neutralSurfaces(
                    Theme.of(host).colorScheme,
                  ).surfaceContainer
                : null),
        sheetBarrierColor: prism.Theme.of(host).colorScheme.modalScrim,
        barrierLabel: '关闭',
        builder: (sheetContext, controller) => PrimaryScrollController(
          controller: controller!,
          automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
          child: content(sheetContext),
        ),
      ),
    );
  }
  return prism.showSheet<T>(
    context: host,
    props: prism.SheetProps(backgroundColor: backgroundColor),
    builder: (context) => SizedBox(
      height: math.min(maxHeight, available * fraction),
      child: content(context),
    ),
  );
}

/// Shared heading, scrollable body and optional fixed actions.
class AppSheetLayout extends StatelessWidget {
  const AppSheetLayout({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    this.actions = const [],
    this.trailing,
    this.leading,
    this.onClose,
    this.centerTitle = false,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onClose;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    final fitsContent =
        context
            .dependOnInheritedWidgetOfExactType<prism.SheetOverhangScope>()
            ?.fitsContent ??
        false;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: fitsContent ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (centerTitle) ...[
            prism.AppBar(
              leading: AppNavigationButton.close(
                onPressed: onClose ?? () => Navigator.of(context).maybePop(),
                size: prism.TonalButtonSize.section,
              ),
              title: Text(title),
              centerTitle: true,
              toolbarHeight: prism.sheetToolbarHeight,
              titleTextStyle: prism.AppTextStyle.headline.of(
                context,
                emphasized: true,
              ),
              actions: [?trailing],
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: prism.AppTextStyle.footnote
                      .of(context)
                      .copyWith(
                        color: prism.Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 12),
              child: Row(
                children: [
                  ?leading,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: prism.AppTextStyle.title3.of(
                            context,
                            emphasized: true,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: prism.AppTextStyle.caption1
                                .of(context)
                                .copyWith(
                                  color: prism.Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ?trailing,
                  AppNavigationButton.close(
                    onPressed:
                        onClose ?? () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
          Flexible(
            fit: fitsContent ? FlexFit.loose : FlexFit.tight,
            child: body,
          ),
          if (actions.isNotEmpty)
            prism.SheetOverhangLift(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  spacing: 12,
                  children: [
                    for (final action in actions) Expanded(child: action),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
