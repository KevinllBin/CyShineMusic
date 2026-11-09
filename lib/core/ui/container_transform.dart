import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import '../../theme/app_motion.dart';

/// Material 3 container transform 的起点：被点击的卡片在承载目标路由的
/// Navigator 坐标系内的矩形、圆角与底色。
///
/// 在点击回调里、`context.push` 之前用 [capture] 采集，装进
/// [ContainerTransformExtra] 随路由 extra 传给目标路由；目标路由的
/// `transitionsBuilder` 再交给 [ContainerTransformTransition] 驱动展开与收回。
///
/// 卡片被滚动视口裁掉一部分时，容器从可见部分展开；详情盖住列表后再把卡片
/// 滚到完整可见（[revealSource]），返回时实时测量卡片，收回到完整的卡片上。
/// 卡片里的封面 Hero 会一并记下（[cover]），详情滚动后返回时用它收回。
@immutable
class ContainerTransformOrigin {
  const ContainerTransformOrigin({
    required this.rect,
    this.borderRadius = BorderRadius.zero,
    this.color,
    this.visibleRect,
    this.cover,
  }) : _source = null,
       _revealPadding = EdgeInsets.zero;

  const ContainerTransformOrigin._({
    required this.rect,
    required this.borderRadius,
    required this.color,
    required this.visibleRect,
    required this.cover,
    required BuildContext source,
    required EdgeInsets revealPadding,
  }) : _source = source,
       _revealPadding = revealPadding;

  /// 卡片矩形，Navigator 坐标系（路由过渡就在这个坐标系里绘制）。
  final Rect rect;

  /// 卡片圆角，展开过程中过渡到直角。
  final BorderRadius borderRadius;

  /// 卡片底色：第一帧容器就是这个颜色，随展开过渡到页面 surface。
  final Color? color;

  /// 卡片在外层滚动视口内实际可见的部分；null 表示完整可见。
  final Rect? visibleRect;

  /// 卡片里的封面 Hero：Navigator 坐标系矩形、在卡片里的圆角与内容。
  final ({Rect rect, BorderRadius borderRadius, Widget child})? cover;

  final BuildContext? _source;
  final EdgeInsets _revealPadding;

  /// 容器起点：卡片可见部分，被裁掉的边没有圆角。
  Rect get startRect => visibleRect ?? rect;

  BorderRadius get startBorderRadius {
    final visible = visibleRect;
    if (visible == null) return borderRadius;
    final top = visible.top > rect.top + 0.5;
    final bottom = visible.bottom < rect.bottom - 0.5;
    final left = visible.left > rect.left + 0.5;
    final right = visible.right < rect.right - 0.5;
    return borderRadius.copyWith(
      topLeft: top || left ? Radius.zero : null,
      topRight: top || right ? Radius.zero : null,
      bottomLeft: bottom || left ? Radius.zero : null,
      bottomRight: bottom || right ? Radius.zero : null,
    );
  }

  /// 采集时记录了卡片、但卡片已经卸载（列表重建、滚出缓存区）。
  bool get sourceLost => _source != null && !_source.mounted;

  /// 采集 [context] 所属卡片的起点。卡片尚未布局、不在 Navigator 内时返回
  /// null，此时路由退化为整页淡入。
  ///
  /// [revealPadding] 是视口边缘被悬浮控件（底栏等）遮住、[revealSource]
  /// 需要让开的距离。
  static ContainerTransformOrigin? capture(
    BuildContext context, {
    BorderRadius borderRadius = BorderRadius.zero,
    Color? color,
    EdgeInsets revealPadding = EdgeInsets.zero,
  }) {
    final navigatorBox = Navigator.maybeOf(context)?.context.findRenderObject();
    if (navigatorBox is! RenderBox) return null;
    final geometry = _measure(context, ancestor: navigatorBox);
    if (geometry == null) return null;
    return ContainerTransformOrigin._(
      rect: geometry.rect,
      borderRadius: borderRadius,
      color: color,
      visibleRect: geometry.visible == geometry.rect ? null : geometry.visible,
      cover: _measureCover(context, ancestor: navigatorBox),
      source: context,
      revealPadding: revealPadding,
    );
  }

  /// 按卡片当前的布局重新测量；卡片已卸载或滚出视口时返回 null。
  ContainerTransformOrigin? remeasure() {
    final source = _source;
    if (source == null || !source.mounted) return null;
    return capture(
      source,
      borderRadius: borderRadius,
      color: color,
      revealPadding: _revealPadding,
    );
  }

  /// 详情完全盖住列表后调用：把卡片滚到完整可见，返回时收回到整张卡片。
  /// 每层滚动只沿自己的轴移动最小距离，卡片比视口还高时让顶部对齐。
  void revealSource() {
    final source = _source;
    if (source == null || !source.mounted) return;
    final box = source.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    for (
      var scrollable = Scrollable.maybeOf(source);
      scrollable != null;
      scrollable = Scrollable.maybeOf(scrollable.context)
    ) {
      final viewport = scrollable.context.findRenderObject();
      if (viewport is! RenderBox || !viewport.attached || !viewport.hasSize) {
        continue;
      }
      if (!_isAncestor(viewport, of: box)) continue;
      final position = scrollable.position;
      if (!position.hasContentDimensions || !position.hasPixels) continue;
      final card =
          box.localToGlobal(Offset.zero, ancestor: viewport) & box.size;
      final vertical = position.axis == Axis.vertical;
      final start = vertical ? card.top : card.left;
      final end = vertical ? card.bottom : card.right;
      final min = vertical ? _revealPadding.top : _revealPadding.left;
      final max = vertical
          ? viewport.size.height - _revealPadding.bottom
          : viewport.size.width - _revealPadding.right;
      var delta = 0.0;
      if (start < min) {
        delta = start - min;
      } else if (end > max) {
        delta = math.min(end - max, start - min);
      }
      if (delta.abs() < 0.5) continue;
      // 列表反向排布时屏幕方向与滚动偏移相反。
      if (axisDirectionIsReversed(position.axisDirection)) delta = -delta;
      final target = (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (target != position.pixels) position.jumpTo(target);
    }
  }

  static ({Rect rect, Rect visible})? _measure(
    BuildContext context, {
    RenderObject? ancestor,
  }) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    if (ancestor != null &&
        (!ancestor.attached || !_isAncestor(ancestor, of: box))) {
      return null;
    }
    final rect = box.localToGlobal(Offset.zero, ancestor: ancestor) & box.size;
    var visible = rect;
    for (
      var scrollable = Scrollable.maybeOf(context);
      scrollable != null;
      scrollable = Scrollable.maybeOf(scrollable.context)
    ) {
      final viewport = scrollable.context.findRenderObject();
      if (viewport is! RenderBox || !viewport.attached || !viewport.hasSize) {
        continue;
      }
      // 只考虑 Navigator 之内的滚动视口；外层的不影响路由坐标系。
      if (ancestor != null && !_isAncestor(ancestor, of: viewport)) break;
      visible = visible.intersect(
        viewport.localToGlobal(Offset.zero, ancestor: ancestor) & viewport.size,
      );
    }
    if (visible.width <= 0 || visible.height <= 0) return null;
    return (rect: rect, visible: visible);
  }

  static ({Rect rect, BorderRadius borderRadius, Widget child})? _measureCover(
    BuildContext context, {
    required RenderObject ancestor,
  }) {
    Element? hero;
    void visit(Element element) {
      if (hero != null) return;
      if (element.widget is Hero) {
        hero = element;
        return;
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    final box = hero?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final shape = HeroArtworkShape.resolve(hero!);
    return (
      rect: box.localToGlobal(Offset.zero, ancestor: ancestor) & box.size,
      borderRadius: shape.borderRadius,
      child: shape.child,
    );
  }

  static bool _isAncestor(RenderObject ancestor, {required RenderObject of}) {
    for (RenderObject? node = of; node != null; node = node.parent) {
      if (identical(node, ancestor)) return true;
    }
    return false;
  }
}

/// 带容器变换起点的路由 extra：业务载荷 + 可选起点。
@immutable
class ContainerTransformExtra<T extends Object> {
  const ContainerTransformExtra(this.payload, {this.origin});

  final T payload;
  final ContainerTransformOrigin? origin;
}

/// 会带走详情封面的滚动区域；在首次布局前恢复过渡选择，避免 Hero 先飞行。
/// 从卡片打开的页面总是从顶部开始，不读取上次保存的选择。
class ContainerTransformScrollRegion extends StatefulWidget {
  const ContainerTransformScrollRegion({
    super.key,
    this.storageId,
    this.persistScrollOrigin = true,
    required this.child,
  });

  final Object? storageId;

  /// 加载/错误占位仍跟踪当前滚动，但不能用自己的短列表覆盖保存的位置。
  final bool persistScrollOrigin;
  final Widget child;

  @override
  State<ContainerTransformScrollRegion> createState() =>
      _ContainerTransformScrollRegionState();
}

class _ContainerTransformScrollRegionState
    extends State<ContainerTransformScrollRegion> {
  _ContainerTransformTransitionState? _transition;
  bool _atScrollOrigin = true;
  bool? _savedScrollOrigin;
  bool _restored = false;

  Object? get _storageKey => widget.storageId == null
      ? null
      : (ContainerTransformScrollRegion, widget.storageId);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _transition = context
        .findAncestorStateOfType<_ContainerTransformTransitionState>();
    if (_restored) return;
    _restored = true;
    final openedFromCard = _transition?.widget.origin != null;
    if (_storageKey case final key? when !openedFromCard) {
      _savedScrollOrigin =
          PageStorage.maybeOf(context)?.readState(context, identifier: key)
              as bool?;
      _atScrollOrigin = _savedScrollOrigin ?? true;
    }
    // 这里只初始化字段，不在子树构建期间请求祖先重建。
    // 区域内的 HeroMode 会立即生效，容器在首个动画帧读取相同选择。
    _transition?._restoreScrollOrigin(_atScrollOrigin);
  }

  void _updateScrollOrigin(ScrollMetrics metrics, int depth) {
    if (depth != 0 || metrics.axis != Axis.vertical) return;
    final atOrigin = (metrics.pixels - metrics.minScrollExtent).abs() <= 1;
    _transition?._updateScrollOrigin(atOrigin);
    if (widget.persistScrollOrigin &&
        _storageKey != null &&
        _savedScrollOrigin != atOrigin) {
      PageStorage.maybeOf(
        context,
      )?.writeState(context, atOrigin, identifier: _storageKey);
      _savedScrollOrigin = atOrigin;
    }
    if (_atScrollOrigin == atOrigin) return;
    setState(() => _atScrollOrigin = atOrigin);
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          _updateScrollOrigin(notification.metrics, notification.depth);
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            _updateScrollOrigin(notification.metrics, notification.depth);
            return false;
          },
          child: AnimatedBuilder(
            animation:
                _transition?.widget.animation ?? kAlwaysCompleteAnimation,
            builder: (context, child) => HeroMode(
              enabled: _transition?._heroEnabled ?? _atScrollOrigin,
              child: child!,
            ),
            child: widget.child,
          ),
        ),
      );
}

/// 页面内容随容器全程柔和淡入/淡出，不在收回中途突然变成空壳。
double containerTransformContentOpacity(double progress) {
  return _smoothOpacity(progress);
}

/// 底色与内容重叠淡出，让搜索结果在封面收回途中逐渐透出。
/// 只在靠近整页时保持实色，避免返回后半段只剩一个遮挡列表的矩形。
double containerTransformFillOpacity(double progress) {
  return _smoothOpacity(progress / 0.85);
}

/// 详情已滚离顶部时的返回：页面内容在收回前半程淡出，让位给卡片封面。
double containerTransformCoverContentOpacity(double progress) {
  return _smoothOpacity((progress - 0.4) / 0.6);
}

/// 同上，卡片封面在返回一开始就淡入，随容器一起收回到卡片里。
double containerTransformCoverOpacity(double progress) {
  return _smoothOpacity((1 - progress) / 0.3);
}

double _smoothOpacity(double progress) {
  final t = progress.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// 路由 `transitionsBuilder`：页面从 [origin] 卡片矩形展开成整页，返回时
/// 原路收回。圆角、底色、描边与浮起阴影一起过渡；页面内容按 fitWidth 从
/// 卡片宽度放大到整页，与背景重叠淡入、淡出。
///
/// 稳定态所有包装层都退化为恒等参数（不裁剪、不缩放、不透明、无装饰），
/// 页面没有额外合成开销；包装层本身始终存在、不做增删，避免子树重挂载。
///
/// [origin] 为 null（深链、无卡片入口）时退化为整页淡入 + 轻微放大。
/// 详情已滚离顶部时返回：页面头图早已滚走，封面 Hero 无从起飞，改为页面
/// 内容淡出、卡片封面淡入，随容器一起收回到卡片（[ContainerTransformOrigin.cover]）。
/// 卡片已卸载或没有封面时，返回退化为整页轻微缩放与淡变。
class ContainerTransformTransition extends StatefulWidget {
  const ContainerTransformTransition({
    super.key,
    required this.animation,
    required this.origin,
    required this.child,
  });

  final Animation<double> animation;
  final ContainerTransformOrigin? origin;
  final Widget child;

  /// 容器裁剪层的 key，测试用来读取当前容器矩形。
  static const Key surfaceKey = ValueKey('container-transform-surface');

  /// 滚动后返回时收回的卡片封面层。
  static const Key coverKey = ValueKey('container-transform-cover');

  /// [context] 所在页面是否从卡片打开（带容器变换起点）。这样打开的详情
  /// 总是从顶部开始，见 [ContainerTransformScrollController]。
  static bool openedFromCard(BuildContext context) =>
      context
          .findAncestorStateOfType<_ContainerTransformTransitionState>()
          ?.widget
          .origin !=
      null;

  @override
  State<ContainerTransformTransition> createState() =>
      _ContainerTransformTransitionState();
}

class _ContainerTransformTransitionState
    extends State<ContainerTransformTransition> {
  late CurvedAnimation _progress = _curve(widget.animation);
  late AnimationStatus _status = widget.animation.status;
  bool _atScrollOrigin = true;
  bool _restoredScrollOrigin = false;
  _TransformStyle _style = _TransformStyle.container;

  bool get _heroEnabled => _status == AnimationStatus.completed
      ? _atScrollOrigin
      : _style == _TransformStyle.container;

  void _restoreScrollOrigin(bool atOrigin) {
    if (_restoredScrollOrigin) return;
    _restoredScrollOrigin = true;
    _atScrollOrigin = atOrigin;
    _style = atOrigin ? _TransformStyle.container : _TransformStyle.fade;
  }

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_handleStatus);
  }

  void _handleStatus(AnimationStatus status) {
    // 详情已完全盖住列表：此时把卡片滚到完整可见不会被看到，返回时
    // 容器与封面都收回到整张卡片上。
    if (status == AnimationStatus.completed &&
        _status == AnimationStatus.forward) {
      widget.origin?.revealSource();
    }
    setState(() {
      // 只在完整展开后选择退场方式；进入途中立即返回仍沿原轨迹倒放。
      // 返回中锁定选择，避免惯性滚动/手势取消导致两种几何轨迹跳变。
      if (status == AnimationStatus.reverse &&
          _status == AnimationStatus.completed) {
        final origin = widget.origin;
        _style = origin == null || origin.sourceLost
            ? _TransformStyle.fade
            : _atScrollOrigin
            ? _TransformStyle.container
            : origin.cover != null
            ? _TransformStyle.cover
            : _TransformStyle.fade;
      } else if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _style = _TransformStyle.container;
      }
      _status = status;
    });
  }

  void _updateScrollOrigin(bool atOrigin) {
    if (_atScrollOrigin == atOrigin) return;
    // 只在离开/回到起点时重建 HeroMode，不随每个滚动像素重建页面。
    if (_status == AnimationStatus.completed) {
      setState(() => _atScrollOrigin = atOrigin);
    } else {
      _atScrollOrigin = atOrigin;
    }
  }

  static CurvedAnimation _curve(Animation<double> parent) {
    return CurvedAnimation(
      parent: parent,
      curve: AppMotion.containerTransform,
      reverseCurve: AppMotion.containerTransform.flipped,
    );
  }

  @override
  void didUpdateWidget(covariant ContainerTransformTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.animation, widget.animation)) {
      oldWidget.animation.removeStatusListener(_handleStatus);
      _progress.dispose();
      _progress = _curve(widget.animation);
      _status = widget.animation.status;
      widget.animation.addStatusListener(_handleStatus);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_handleStatus);
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 页面每帧缩放、淡变，玻璃按钮若实时取背景就要逐帧重拍、重新模糊；
    // 过渡这么短，用静态磨砂代替，落地后再恢复实时玻璃。
    return HeroMode(
      enabled: _heroEnabled,
      child: prism.LiquidGlassFlat(
        flat: _status.isAnimating,
        child: _buildTransition(context),
      ),
    );
  }

  Widget _buildTransition(BuildContext context) {
    final origin = widget.origin;
    if (origin == null) {
      return FadeTransition(
        opacity: _progress,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(_progress),
          child: widget.child,
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final full = Offset.zero & constraints.biggest;
        return AnimatedBuilder(
          animation: _progress,
          child: widget.child,
          builder: (context, child) =>
              _buildFrame(origin, full, scheme, child!),
        );
      },
    );
  }

  Widget _buildFrame(
    ContainerTransformOrigin captured,
    Rect full,
    ColorScheme scheme,
    Widget child,
  ) {
    final t = _progress.value.clamp(0.0, 1.0);
    final settled = t >= 1;
    final fade = _style == _TransformStyle.fade;
    // 返回时卡片可能已被滚到完整可见：逐帧按卡片当前布局收回。
    final origin = _status == AnimationStatus.reverse && !fade
        ? captured.remeasure() ?? captured
        : captured;
    // 沿用同一棵包装子树，退场切换不重挂载页面，也不把列表滚回顶部。
    final start = fade
        ? Rect.fromCenter(
            center: full.center,
            width: full.width * 0.985,
            height: full.height * 0.985,
          )
        : origin.startRect;
    final rect = settled ? full : Rect.lerp(start, full, t)!;
    final radius = fade
        ? BorderRadius.zero
        : BorderRadius.lerp(origin.startBorderRadius, BorderRadius.zero, t)!;
    final scale = full.width > 0 ? rect.width / full.width : 1.0;
    final fill = fade ? 0.0 : containerTransformFillOpacity(t);
    final cover = _style == _TransformStyle.cover && !settled
        ? origin.cover
        : null;
    final lift = (1 - t) * fill;
    final surface = Color.lerp(
      origin.color ?? scheme.surface,
      scheme.surface,
      t,
    )!;
    return Stack(
      children: [
        Positioned.fromRect(
          rect: rect,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: settled
                  ? null
                  : surface.withValues(alpha: surface.a * fill),
              borderRadius: radius,
              border: lift <= 0
                  ? null
                  : Border.all(
                      color: scheme.outlineVariant.withValues(
                        alpha: 0.24 * lift,
                      ),
                    ),
              boxShadow: lift <= 0
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22 * lift),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
            ),
            child: ClipRRect(
              key: ContainerTransformTransition.surfaceKey,
              borderRadius: radius,
              clipBehavior: settled || fade ? Clip.none : Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: full.width,
                    maxWidth: full.width,
                    minHeight: full.height,
                    maxHeight: full.height,
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment.topLeft,
                      child: Opacity(
                        opacity: cover == null
                            ? containerTransformContentOpacity(t)
                            : containerTransformCoverContentOpacity(t),
                        child: child,
                      ),
                    ),
                  ),
                  if (cover != null) _buildCover(cover, rect, full, t),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 卡片封面层：起点是页面顶部、整宽、保持卡片封面比例，随容器收回到卡片
/// 封面的位置；圆角从直角过渡到卡片里的圆角。
Widget _buildCover(
  ({Rect rect, BorderRadius borderRadius, Widget child}) cover,
  Rect container,
  Rect full,
  double t,
) {
  final aspect = cover.rect.width > 0
      ? cover.rect.height / cover.rect.width
      : 1.0;
  final page = Rect.fromLTWH(
    full.left,
    full.top,
    full.width,
    full.width * aspect,
  );
  final rect = Rect.lerp(cover.rect, page, t)!.shift(-container.topLeft);
  return Positioned.fromRect(
    key: ContainerTransformTransition.coverKey,
    rect: rect,
    child: IgnorePointer(
      child: Opacity(
        opacity: containerTransformCoverOpacity(t),
        child: ClipRRect(
          borderRadius: BorderRadius.lerp(
            cover.borderRadius,
            BorderRadius.zero,
            t,
          )!,
          child: cover.child,
        ),
      ),
    ),
  );
}

/// 返回方式：容器收回 + 封面 Hero（详情在顶部）、容器收回 + 卡片封面淡入
/// （详情已滚动）、整页淡出（找不到卡片）。
enum _TransformStyle { container, cover, fade }

/// 从卡片打开的详情页总是从顶部开始：本次打开后第一次建立滚动位置时不恢复
/// 上次离开时保存的偏移，并把保存值重置为顶部；之后切换布局、切回 tab
/// 重建列表时照常恢复本次的位置。不是从卡片打开（切回 tab、深链）时照常恢复。
class ContainerTransformScrollController extends ScrollController {
  ContainerTransformScrollController({super.debugLabel});

  bool _positioned = false;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    final startFresh =
        !_positioned &&
        oldPosition == null &&
        ContainerTransformTransition.openedFromCard(context.storageContext);
    _positioned = true;
    return _FreshStartScrollPosition(
      startFresh: startFresh,
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _FreshStartScrollPosition extends ScrollPositionWithSingleContext {
  _FreshStartScrollPosition({
    required this.startFresh,
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  }) : _initialPixels = initialPixels ?? 0;

  final bool startFresh;
  final double _initialPixels;

  @override
  void restoreScrollOffset() {
    if (!startFresh) {
      super.restoreScrollOffset();
      return;
    }
    // 覆盖上次离开时保存的偏移，本次重建列表时不会再跳回旧位置。
    PageStorage.maybeOf(
      context.storageContext,
    )?.writeState(context.storageContext, _initialPixels);
  }
}

/// 封面 Hero 的 [Hero.createRectTween]。Hero 内部固定用 fastOutSlowIn 驱动
/// 飞行，这里把它重映射为 [AppMotion.containerTransform]，让封面与容器
/// 沿同一条曲线运动，共同柔和起步、减速落地。
///
/// Hero 只看目标端的 createRectTween（push 看页面端、pop 看卡片端），
/// 所以两端都要挂上。
Tween<Rect?> containerTransformHeroRectTween(Rect? begin, Rect? end) {
  return _ContainerTransformHeroRectTween(begin: begin, end: end);
}

class _ContainerTransformHeroRectTween extends RectTween {
  _ContainerTransformHeroRectTween({super.begin, super.end});

  @override
  Rect? lerp(double t) =>
      Rect.lerp(begin, end, containerTransformHeroProgress(t));
}

/// 把 Hero 传入的 fastOutSlowIn 进度换算成容器进度，正反向共用。
double containerTransformHeroProgress(double t) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  return AppMotion.containerTransform.transform(
    _invertCurve(Curves.fastOutSlowIn, t),
  );
}

/// 单调曲线求逆：二分 24 次。
double _invertCurve(Curve curve, double value) {
  var low = 0.0;
  var high = 1.0;
  for (var i = 0; i < 24; i++) {
    final mid = (low + high) / 2;
    if (curve.transform(mid) < value) {
      low = mid;
    } else {
      high = mid;
    }
  }
  return (low + high) / 2;
}

/// 声明 Hero 封面在所在卡片/头图内的圆角。放在 [Hero.child] 最外层，
/// [buildArtworkHeroFlightShuttle] 据此在飞行中把两端圆角插值过渡。
class HeroArtworkShape extends StatelessWidget {
  const HeroArtworkShape({
    super.key,
    this.borderRadius = BorderRadius.zero,
    required this.child,
  });

  final BorderRadius borderRadius;
  final Widget child;

  /// 解析某端 Hero 的圆角与内容；没用 [HeroArtworkShape] 包裹时视为直角。
  static ({BorderRadius borderRadius, Widget child}) resolve(
    BuildContext heroContext,
  ) {
    final child = (heroContext.widget as Hero).child;
    if (child is HeroArtworkShape) {
      return (borderRadius: child.borderRadius, child: child.child);
    }
    return (borderRadius: BorderRadius.zero, child: child);
  }

  @override
  Widget build(BuildContext context) {
    if (borderRadius == BorderRadius.zero) return child;
    return ClipRRect(borderRadius: borderRadius, child: child);
  }
}

/// 封面 Hero 的 [Hero.flightShuttleBuilder]。只需挂在页面端 Hero 上：push 时
/// 页面端是目标端；pop 时卡片端没有 builder，Hero 会回落到页面端的，两个
/// 方向因此一致。
///
/// * 圆角在卡片端与页面端之间插值（两端用 [HeroArtworkShape] 声明）；
/// * 卡片端封面打底，页面端封面随尺寸柔和淡入——两端图源不同（榜单渐变
///   占位 → 真实封面）时不再硬切；
/// * [overlay]（头图 scrim、顶栏）在落地前淡入，飞行结束时不再突然出现；
/// * 卡片端封面被滚动视口裁掉一部分时，从可见部分起步再逐渐露出全貌，
///   不会在第一帧整张盖到视口外的标签栏上。
///
/// 进度按 shuttle 当前尺寸在两端尺寸之间的位置计算，天然与飞行矩形同步；
/// 不依赖飞行曲线，飞行被中途反向也不会跳变。
Widget buildArtworkHeroFlightShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext, {
  Widget? overlay,
}) {
  final push = direction == HeroFlightDirection.push;
  final cardContext = push ? fromHeroContext : toHeroContext;
  final pageContext = push ? toHeroContext : fromHeroContext;
  final card = HeroArtworkShape.resolve(cardContext);
  final cardClip = _heroVisibleFraction(cardContext);
  return _ArtworkHeroShuttle(
    card: (
      borderRadius: _zeroClippedCorners(card.borderRadius, cardClip),
      child: card.child,
    ),
    cardClip: cardClip,
    page: HeroArtworkShape.resolve(pageContext),
    cardSize: _heroSize(cardContext),
    pageSize: _heroSize(pageContext),
    animation: animation,
    overlay: overlay,
  );
}

Size? _heroSize(BuildContext heroContext) {
  final box = heroContext.findRenderObject();
  return box is RenderBox && box.hasSize ? box.size : null;
}

/// 卡片端 Hero 被外层滚动视口裁掉的部分，按自身尺寸的比例表示。
EdgeInsets _heroVisibleFraction(BuildContext heroContext) {
  final geometry = ContainerTransformOrigin._measure(heroContext);
  if (geometry == null) return EdgeInsets.zero;
  final (:rect, :visible) = geometry;
  if (rect.width <= 0 || rect.height <= 0) return EdgeInsets.zero;
  return EdgeInsets.fromLTRB(
    (visible.left - rect.left) / rect.width,
    (visible.top - rect.top) / rect.height,
    (rect.right - visible.right) / rect.width,
    (rect.bottom - visible.bottom) / rect.height,
  );
}

BorderRadius _zeroClippedCorners(BorderRadius radius, EdgeInsets clip) {
  if (clip == EdgeInsets.zero) return radius;
  return radius.copyWith(
    topLeft: clip.top > 0 || clip.left > 0 ? Radius.zero : null,
    topRight: clip.top > 0 || clip.right > 0 ? Radius.zero : null,
    bottomLeft: clip.bottom > 0 || clip.left > 0 ? Radius.zero : null,
    bottomRight: clip.bottom > 0 || clip.right > 0 ? Radius.zero : null,
  );
}

class _ArtworkHeroShuttle extends StatelessWidget {
  const _ArtworkHeroShuttle({
    required this.card,
    required this.cardClip,
    required this.page,
    required this.cardSize,
    required this.pageSize,
    required this.animation,
    required this.overlay,
  });

  static const Key shuttleKey = ValueKey('artwork-hero-shuttle');

  final ({BorderRadius borderRadius, Widget child}) card;
  final EdgeInsets cardClip;
  final ({BorderRadius borderRadius, Widget child}) page;
  final Size? cardSize;
  final Size? pageSize;
  final Animation<double> animation;
  final Widget? overlay;

  double _progressFor(Size size) {
    final from = cardSize;
    final to = pageSize;
    if (from != null && to != null) {
      final horizontal = to.width - from.width;
      if (horizontal.abs() > 1) {
        return ((size.width - from.width) / horizontal).clamp(0.0, 1.0);
      }
      final vertical = to.height - from.height;
      if (vertical.abs() > 1) {
        return ((size.height - from.height) / vertical).clamp(0.0, 1.0);
      }
    }
    return animation.value.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final progress = _progressFor(constraints.biggest);
          final radius = BorderRadius.lerp(
            card.borderRadius,
            page.borderRadius,
            progress,
          )!;
          final pageOpacity = _smoothOpacity(progress);
          final overlayOpacity = _smoothOpacity((progress - 0.15) / 0.85);
          return ClipRRect(
            key: shuttleKey,
            clipper: _FractionalRRectClipper(
              inset: cardClip * (1 - progress),
              borderRadius: radius,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                card.child,
                Opacity(opacity: pageOpacity, child: page.child),
                if (overlay case final overlay?)
                  IgnorePointer(
                    child: Opacity(
                      opacity: overlayOpacity,
                      // 飞行中的顶栏副本同样不实时取背景。
                      child: prism.LiquidGlassFlat(flat: true, child: overlay),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 按比例内缩后的圆角裁剪：封面从卡片可见部分逐渐露出全貌。
class _FractionalRRectClipper extends CustomClipper<RRect> {
  const _FractionalRRectClipper({
    required this.inset,
    required this.borderRadius,
  });

  final EdgeInsets inset;
  final BorderRadius borderRadius;

  @override
  RRect getClip(Size size) => borderRadius.toRRect(
    Rect.fromLTRB(
      size.width * inset.left,
      size.height * inset.top,
      size.width * (1 - inset.right),
      size.height * (1 - inset.bottom),
    ),
  );

  @override
  bool shouldReclip(_FractionalRRectClipper oldClipper) =>
      oldClipper.inset != inset || oldClipper.borderRadius != borderRadius;
}
