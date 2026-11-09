import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/context.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/metrics.dart';
import 'package:prism_ui/models.dart';
import 'package:prism_ui/surface.dart';
import 'package:prism_ui/theme_data.dart';
import 'package:prism_ui/typography.dart';
import 'package:prism_ui/view_scope.dart';

import 'button.dart';
import 'common_button.dart';
import 'inherited.dart';
import 'loading.dart';
import 'sheet.dart';
import 'sheet_header.dart';
import 'bar_item_presence.dart';

class ScaffoldSurface {
  const ScaffoldSurface._({
    required this.provider,
    required this.isModal,
    required this.isCompact,
    required this.hasDragHandle,
  });

  factory ScaffoldSurface.of(BuildContext context) {
    final provider = SheetProvider.of(context);
    return ScaffoldSurface._(
      provider: provider,
      isModal: provider != null && provider.type != SheetType.page,
      isCompact: provider?.type.isCompact ?? false,
      hasDragHandle: provider?.type == SheetType.bottomSheet,
    );
  }

  final SheetProvider? provider;
  final bool isModal;
  final bool isCompact;
  final bool hasDragHandle;
}

/// A page's or a sheet's layout, which knows nothing of what fills its slots.
class PrismScaffold extends StatelessWidget {
  const PrismScaffold({
    super.key,
    required this.bar,
    required this.body,
    this.headerListenable,
    this.headerBuilder,
    this.foot,
    this.footHidden = false,
    this.footInset = 0,
    this.footActions,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
  });

  final PreferredSizeWidget bar;
  final Widget body;

  final Listenable? headerListenable;

  /// Under the bar, which the body then no longer runs under; null for none.
  final Widget? Function(BuildContext context)? headerBuilder;
  final Widget? foot;

  /// Takes [foot] out of sight without moving the body in the tree.
  final bool footHidden;

  final double footInset;

  final Widget? footActions;
  final Color? backgroundColor;
  final bool? resizeToAvoidBottomInset;

  static final _noChange = Listenable.merge(const []);

  @override
  Widget build(BuildContext context) {
    final surface = ScaffoldSurface.of(context);
    final isCompact = surface.isCompact;
    final bottomInset = BottomInsetScope.of(context);
    // A detent sheet fills the height its detent gives it and clips its own
    // corners; any other bottom sheet sizes to its content and brings both.
    final hugsContent = isCompact && !SheetOverhangScope.fillsDetentOf(context);
    // The page's bar floats over its body, which finds the bar's height in
    // its MediaQuery top padding.
    final barFloats = !isCompact;
    final bodyLayer = SafeArea(
      top: !barFloats,
      bottom: false,
      child: ListenableBuilder(
        listenable: headerListenable ?? _noChange,
        builder: (context, _) {
          final header = headerBuilder?.call(context);
          final hasHeader = header != null;
          final barInset = MediaQuery.paddingOf(context).top;
          final overlap = barFloats
              ? barInset
              : isCompact
              ? sheetAppBarHeight
              : 0.0;
          // A wrapper toggled with the header would remount the body.
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: hugsContent ? MainAxisSize.min : MainAxisSize.max,
            children: [
              if (hasHeader)
                Padding(
                  padding: EdgeInsets.only(top: overlap),
                  child: header,
                ),
              Flexible(
                fit: hugsContent ? FlexFit.loose : FlexFit.tight,
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: hasHeader,
                  child: FloatingBarScope(
                    inset: hasHeader ? 0 : overlap,
                    child: body,
                  ),
                ),
              ),
            ],
          );
          return TopInsetScope(
            inset: hasHeader ? 0 : TopInsetScope.of(context),
            child: FloatingBarScope(
              inset: overlap,
              child: overlap > 0
                  ? _FocusClearOfBar(inset: overlap, child: content)
                  : content,
            ),
          );
        },
      ),
    );
    final foot = this.foot;
    final content = foot != null
        ? BottomInsetScope(inset: bottomInset + footInset, child: bodyLayer)
        : bodyLayer;
    if (!isCompact) {
      return _ScaffoldFrame(
        bar: bar,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        backgroundColor: backgroundColor,
        body: _BodyScope(
          child: foot == null
              ? content
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    content,
                    if (!footHidden)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: BarItemPresence.foot(child: foot),
                      ),
                  ],
                ),
        ),
      );
    }
    final sheetBody = FloatingHeaderBody(
      backgroundColor:
          backgroundColor ?? SurfaceLevel.page.colorOf(context.colorScheme),
      header: SheetToolBar(appBar: bar, dragHandle: surface.hasDragHandle),
      footer: foot == null || footHidden
          ? null
          : BarItemPresence.foot(child: foot),
      body: content,
    );
    final footActions = this.footActions;
    final footed = footActions != null
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                fit: hugsContent ? FlexFit.loose : FlexFit.tight,
                child: sheetBody,
              ),
              footActions,
            ],
          )
        : sheetBody;
    if (!hugsContent) {
      return _ScaffoldFrame(
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        backgroundColor: backgroundColor,
        body: footed,
      );
    }
    final hugging = Column(
      mainAxisSize: MainAxisSize.min,
      children: [Flexible(child: footed)],
    );
    return surface.hasDragHandle
        ? ClipRSuperellipse(
            borderRadius: bottomSheetRadiusOf(context),
            child: hugging,
          )
        : hugging;
  }
}

/// The bar a [PrismScaffold] lays out: what [builder] draws, floating over a
/// page and clear of the window's controls, above a loading line.
class ScaffoldBar extends StatelessWidget implements PreferredSizeWidget {
  const ScaffoldBar({
    super.key,
    required this.isCompact,
    required this.listenable,
    required this.builder,
    required this.loading,
    this.backgroundColor,
  });

  final bool isCompact;

  final Listenable listenable;
  final WidgetBuilder builder;
  final ValueListenable<bool> loading;
  final Color? backgroundColor;

  @override
  Size get preferredSize =>
      Size.fromHeight(isCompact ? sheetToolbarHeight : pageToolbarHeight);

  Widget _floating(BuildContext context, Widget bar) {
    final top = MediaQuery.paddingOf(context).top;
    return FloatingHeader(
      backgroundColor:
          backgroundColor ?? SurfaceLevel.page.colorOf(context.colorScheme),
      fadeStart: top / (top + pageToolbarHeight),
      overhang: _headerOverhang,
      child: _WindowControlsClearance(child: bar),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: [
        ListenableBuilder(
          listenable: listenable,
          builder: (context, _) {
            final bar = builder(context);
            return isCompact ? bar : _floating(context, bar);
          },
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: -LoadingBar.extent,
          height: LoadingBar.extent,
          child: ValueListenableBuilder(
            valueListenable: loading,
            builder: (_, value, _) => LoadingBar(active: value),
          ),
        ),
      ],
    );
  }
}

class AppBarClearance extends StatelessWidget {
  const AppBarClearance({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: context.appBarInset),
      child: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: FloatingBarScope(inset: 0, child: child),
      ),
    );
  }
}

/// Keeps rebuilds in the body to its own layer (.agents/architecture.md).
class _BodyScope extends StatelessWidget {
  const _BodyScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _BodyBoundary(child: LayoutBuilder(builder: (_, _) => child));
  }
}

class _BodyBoundary extends SingleChildRenderObjectWidget {
  const _BodyBoundary({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBodyBoundary();
}

class _RenderBodyBoundary extends RenderProxyBox {
  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    child?.layout(constraints);
  }
}

/// Flutter reveals a focused control against the viewport alone, which runs
/// under a floating bar, so keyboard and remote traversal would park it there.
class _FocusClearOfBar extends StatefulWidget {
  const _FocusClearOfBar({required this.inset, required this.child});

  final double inset;
  final Widget child;

  @override
  State<_FocusClearOfBar> createState() => _FocusClearOfBarState();
}

class _FocusClearOfBarState extends State<_FocusClearOfBar> {
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    final manager = FocusManager.instance;
    final focused = manager.primaryFocus?.context;
    if (manager.highlightMode != FocusHighlightMode.traditional ||
        focused == null ||
        focused.findAncestorStateOfType<_FocusClearOfBarState>() != this) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(focused));
  }

  void _reveal(BuildContext focused) {
    if (!mounted || !focused.mounted) {
      return;
    }
    var scrollable = Scrollable.maybeOf(focused);
    while (scrollable != null && scrollable.position.axis != Axis.vertical) {
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    final body = context.findRenderObject();
    final target = focused.findRenderObject();
    final viewport = scrollable?.context.findRenderObject();
    if (scrollable == null ||
        body is! RenderBox ||
        target is! RenderBox ||
        viewport is! RenderBox) {
      return;
    }
    final barBottom = body.localToGlobal(Offset.zero).dy + widget.inset;
    final covered = barBottom - target.localToGlobal(Offset.zero).dy;
    if (covered <= 0 || viewport.localToGlobal(Offset.zero).dy >= barBottom) {
      return;
    }
    final position = scrollable.position;
    final delta = axisDirectionIsReversed(position.axisDirection)
        ? covered
        : -covered;
    position.jumpTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// An app bar action from [IconButtonData], standing in a spinner while the
/// action runs.
class AppBarActionButton extends StatelessWidget {
  const AppBarActionButton({super.key, required this.data, this.icon});

  final IconButtonData data;

  /// Stands in for the glyph of [data].
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return IconButton(
      tooltip: data.tooltip,
      isSelected: data.isSelected,
      style: data.isSelected == true
          ? ButtonStyle.from(
              backgroundColor: TonalButtonTheme.glassOf(context)
                  ? null
                  : colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            )
          : null,
      onPressed: data.isLoading ? null : data.onPressed,
      icon: data.isLoading
          ? ActivityIndicator(size: TonalButtonSize.bar.icon)
          : BarItemGlyph(child: icon ?? GlyphIcon(data.glyph)),
    );
  }
}

const double appBarActionSpace = 4;

const double barButtonGap = 8;
const double _headerOverhang = 16;
const double _iconButtonTapPadding = 4;

/// Where a filled button sits from the app bar edge, leading included: the
/// layout margin iOS gives a compact and a regular width.
double appBarActionInset(bool compact) => compact ? 16 : 20;

double _iconActionInset(bool isMobileView) => isMobileView ? 4 : 8;

double appBarLeadingWidth(bool compact) =>
    TonalButtonSize.bar.button + appBarActionInset(compact) * 2;

/// A phone view or a sheet: an iOS compact width.
bool isCompactBar(BuildContext context, bool isMobileView) {
  final sheet = SheetProvider.of(context)?.type;
  return isMobileView || (sheet != null && sheet != SheetType.page);
}

enum AppBarActionEdge {
  icon,
  container;

  double spaceOf(BuildContext context, bool isMobileView) => switch (this) {
    icon => _iconActionInset(isMobileView) - _tapPaddingOf(context),
    container => appBarActionInset(isCompactBar(context, isMobileView)),
  };

  double get gap => switch (this) {
    icon => appBarActionSpace,
    container => barButtonGap,
  };
}

/// Only the touch platforms ask for the 48 dp target that pads the container out.
double _tapPaddingOf(BuildContext context) =>
    Theme.of(context).tapTargetSize == TapTargetSize.padded
    ? _iconButtonTapPadding
    : 0;

List<Widget> genActions(
  List<Widget> actions, {
  required AppBarActionEdge edge,
}) {
  return <Widget>[
    ...separatedBy(actions, SizedBox(width: edge.gap)),
    ActionEdgeGap(edge),
  ];
}

class ActionEdgeGap extends StatelessWidget {
  const ActionEdgeGap(this.edge, {super.key});

  final AppBarActionEdge edge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: edge.spaceOf(context, ViewScope.isMobileOf(context)),
    );
  }
}

/// The surface a page or a sheet lays out on, with [bar] over the top of
/// [body], which runs under it with the bar's height as its top padding.
class _ScaffoldFrame extends StatelessWidget {
  const _ScaffoldFrame({
    this.bar,
    required this.resizeToAvoidBottomInset,
    required this.backgroundColor,
    required this.body,
  });

  final PreferredSizeWidget? bar;
  final bool? resizeToAvoidBottomInset;
  final Color? backgroundColor;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final resize = resizeToAvoidBottomInset ?? true;
    final bar = this.bar;
    final barHeight = bar == null
        ? 0.0
        : mediaQuery.padding.top + bar.preferredSize.height;
    var bodyData = mediaQuery.removePadding(removeTop: bar != null);
    if (resize) {
      bodyData = bodyData.removeViewInsets(removeBottom: true);
    }
    if (bar != null) {
      bodyData = bodyData.copyWith(
        padding: bodyData.padding.copyWith(top: barHeight),
      );
    }
    return Surface(
      color: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            bottom: resize ? mediaQuery.viewInsets.bottom : 0,
            child: Align(
              alignment: Alignment.topLeft,
              child: MediaQuery(data: bodyData, child: body),
            ),
          ),
          if (bar != null)
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: barHeight),
                child: MediaQuery(
                  data: mediaQuery.removePadding(removeBottom: true),
                  child: bar,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A page's or a sheet's bar: the toolbar Material 3's app bar lays out, on
/// no surface of its own. Below the top padding it is [toolbarHeight] tall,
/// a page's bar by default.
class AppBar extends StatelessWidget {
  const AppBar({
    super.key,
    this.leading,
    this.title,
    this.actions = const [],
    this.centerTitle = false,
    this.titleSpacing,
    this.toolbarHeight,
    this.titleTextStyle,
    this.systemOverlayStyle,
    this.clipBehavior = Clip.hardEdge,
  });

  static const _maxTitleTextScale = 1.34;

  final Widget? leading;
  final Widget? title;
  final List<Widget> actions;
  final bool centerTitle;
  final double? titleSpacing;
  final double? toolbarHeight;
  final TextStyle? titleTextStyle;

  /// The status bar over the bar; by default the one that reads on the
  /// page's surface.
  final SystemUiOverlayStyle? systemOverlayStyle;
  final Clip clipBehavior;

  static SystemUiOverlayStyle _overlayStyleOn(Color color) {
    final luminance = color.computeLuminance();
    final style = (luminance + 0.05) * (luminance + 0.05) > 0.15
        ? SystemUiOverlayStyle.dark
        : SystemUiOverlayStyle.light;
    return SystemUiOverlayStyle(
      statusBarColor: const Color(0x00000000),
      statusBarBrightness: style.statusBarBrightness,
      statusBarIconBrightness: style.statusBarIconBrightness,
      systemStatusBarContrastEnforced: style.systemStatusBarContrastEnforced,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final compact = isCompactBar(context, ViewScope.isMobileOf(context));
    final leading = this.leading;
    Widget? title = this.title;
    if (title != null) {
      title = MediaQuery.withClampedTextScaling(
        maxScaleFactor: _maxTitleTextScale,
        child: DefaultTextStyle(
          style:
              titleTextStyle ??
              AppTextStyle.title3
                  .of(context)
                  .copyWith(color: colorScheme.onSurface),
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          child: Semantics(
            namesRoute: switch (defaultTargetPlatform) {
              TargetPlatform.iOS || TargetPlatform.macOS => null,
              _ => true,
            },
            header: true,
            child: _AppBarTitleBox(child: title),
          ),
        ),
      );
    }
    final toolbar = NavigationToolbar(
      leading: leading == null
          ? null
          : ConstrainedBox(
              constraints: BoxConstraints.tightFor(
                width: appBarLeadingWidth(compact),
              ),
              child: leading,
            ),
      middle: title,
      trailing: actions.isEmpty
          ? null
          : IconTheme.merge(
              data: IconThemeData(
                color: colorScheme.onSurfaceVariant,
                size: 24,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: actions),
            ),
      centerMiddle: centerTitle,
      middleSpacing: titleSpacing ?? NavigationToolbar.kMiddleSpacing,
    );
    return Semantics(
      container: true,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemOverlayStyle ?? _overlayStyleOn(colorScheme.surface),
        // The ink of a control in the bar, which would fall under the
        // header's fade on the page's own surface.
        child: Surface.transparent(
          child: Semantics(
            explicitChildNodes: true,
            child: Align(
              alignment: Alignment.topCenter,
              child: SafeArea(
                bottom: false,
                child: ClipRect(
                  clipBehavior: clipBehavior,
                  child: CustomSingleChildLayout(
                    delegate: _ToolbarLayout(
                      toolbarHeight ?? pageToolbarHeight,
                    ),
                    child: IconTheme.merge(
                      data: IconThemeData(
                        color: colorScheme.onSurface,
                        size: 24,
                      ),
                      child: DefaultTextStyle(
                        style: AppTextStyle.subheadline
                            .of(context)
                            .copyWith(color: colorScheme.onSurface),
                        child: toolbar,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays the toolbar out at the foot of a bar that may be cut short.
class _ToolbarLayout extends SingleChildLayoutDelegate {
  const _ToolbarLayout(this.toolbarHeight);

  final double toolbarHeight;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.tighten(height: toolbarHeight);

  @override
  Size getSize(BoxConstraints constraints) =>
      Size(constraints.maxWidth, toolbarHeight);

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      Offset(0, size.height - childSize.height);

  @override
  bool shouldRelayout(_ToolbarLayout oldDelegate) =>
      toolbarHeight != oldDelegate.toolbarHeight;
}

/// Centres the title in its slot without capping its height.
class _AppBarTitleBox extends SingleChildRenderObjectWidget {
  const _AppBarTitleBox({required Widget super.child});

  @override
  _RenderAppBarTitleBox createRenderObject(BuildContext context) =>
      _RenderAppBarTitleBox(textDirection: Directionality.of(context));

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAppBarTitleBox renderObject,
  ) {
    renderObject.textDirection = Directionality.of(context);
  }
}

class _RenderAppBarTitleBox extends RenderAligningShiftedBox {
  _RenderAppBarTitleBox({super.textDirection})
    : super(alignment: Alignment.center);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final inner = constraints.copyWith(maxHeight: double.infinity);
    return constraints.constrain(child!.getDryLayout(inner));
  }

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final inner = constraints.copyWith(maxHeight: double.infinity);
    final child = this.child;
    if (child == null) {
      return null;
    }
    final result = child.getDryBaseline(inner, baseline);
    if (result == null) {
      return null;
    }
    final childSize = child.getDryLayout(inner);
    return result +
        resolvedAlignment
            .alongOffset(getDryLayout(constraints) - childSize as Offset)
            .dy;
  }

  @override
  void performLayout() {
    child!.layout(
      constraints.copyWith(maxHeight: double.infinity),
      parentUsesSize: true,
    );
    size = constraints.constrain(child!.size);
    alignChild();
  }
}

class _WindowControlsClearance extends StatelessWidget {
  const _WindowControlsClearance({required this.child});

  final Widget child;

  static bool _fillsWindow(BuildContext context) {
    final route = ModalRoute.of(context);
    return route != null &&
        route.opaque &&
        !route.isFirst &&
        route.navigator == Navigator.maybeOf(context, rootNavigator: true);
  }

  @override
  Widget build(BuildContext context) {
    final controls = ViewScope.windowControlsOf(context);
    if (controls.isEmpty || !_fillsWindow(context)) {
      return child;
    }
    final mediaQuery = MediaQuery.of(context);
    final padding = mediaQuery.padding;
    return MediaQuery(
      data: mediaQuery.copyWith(
        padding: padding.copyWith(left: math.max(padding.left, controls.width)),
      ),
      child: child,
    );
  }
}

Iterable<Widget> separatedBy(Iterable<Widget> items, Widget separator) sync* {
  final iterator = items.iterator;
  if (!iterator.moveNext()) {
    return;
  }
  yield iterator.current;
  while (iterator.moveNext()) {
    yield separator;
    yield iterator.current;
  }
}
