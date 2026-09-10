import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// Material 3 container transform 的起点：被点击的卡片在承载目标路由的
/// Navigator 坐标系内的矩形、圆角与底色。
///
/// 在点击回调里、`context.push` 之前用 [capture] 采集，装进
/// [ContainerTransformExtra] 随路由 extra 传给目标路由；目标路由的
/// `transitionsBuilder` 再交给 [ContainerTransformTransition] 驱动展开与收回。
@immutable
class ContainerTransformOrigin {
  const ContainerTransformOrigin({
    required this.rect,
    this.borderRadius = BorderRadius.zero,
    this.color,
  });

  /// 卡片矩形，Navigator 坐标系（路由过渡就在这个坐标系里绘制）。
  final Rect rect;

  /// 卡片圆角，展开过程中过渡到直角。
  final BorderRadius borderRadius;

  /// 卡片底色：第一帧容器就是这个颜色，随展开过渡到页面 surface。
  final Color? color;

  /// 采集 [context] 所属卡片的起点。卡片尚未布局、不在 Navigator 内时返回
  /// null，此时路由退化为整页淡入。
  static ContainerTransformOrigin? capture(
    BuildContext context, {
    BorderRadius borderRadius = BorderRadius.zero,
    Color? color,
  }) {
    final box = context.findRenderObject();
    final navigatorBox = Navigator.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox || navigatorBox is! RenderBox) return null;
    if (!box.hasSize || !box.attached || !navigatorBox.attached) return null;
    if (!_isAncestor(navigatorBox, of: box)) return null;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: navigatorBox);
    return ContainerTransformOrigin(
      rect: topLeft & box.size,
      borderRadius: borderRadius,
      color: color,
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

/// 页面内容不透明度（M3 fade-through）：容器展开不到三成时保持透明，
/// 之后随展开线性淡入；收回时先淡出、再由容器独自缩回卡片。
double containerTransformContentOpacity(double progress) {
  return ((progress - 0.3) / 0.7).clamp(0.0, 1.0);
}

/// 容器底色、描边、阴影的不透明度：只在贴合卡片的最后 8% 行程内淡出。
/// 收回落地时卡片文字从容器下透出而不是硬切；展开时这段只占一两帧。
double containerTransformFillOpacity(double progress) {
  return (progress / 0.08).clamp(0.0, 1.0);
}

/// 路由 `transitionsBuilder`：页面从 [origin] 卡片矩形展开成整页，返回时
/// 原路收回。圆角、底色、描边与浮起阴影一起过渡；页面内容按 fitWidth 从
/// 卡片宽度放大到整页，并按 fade-through 在容器展开后淡入。
///
/// 稳定态所有包装层都退化为恒等参数（不裁剪、不缩放、不透明、无装饰），
/// 页面没有额外合成开销；包装层本身始终存在、不做增删，避免子树重挂载。
///
/// [origin] 为 null（深链、无卡片入口）时退化为整页淡入 + 轻微放大。
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

  @override
  State<ContainerTransformTransition> createState() =>
      _ContainerTransformTransitionState();
}

class _ContainerTransformTransitionState
    extends State<ContainerTransformTransition> {
  late CurvedAnimation _progress = _curve(widget.animation);

  static CurvedAnimation _curve(Animation<double> parent) {
    return CurvedAnimation(
      parent: parent,
      curve: AppMotion.emphasized,
      reverseCurve: AppMotion.emphasized.flipped,
    );
  }

  @override
  void didUpdateWidget(covariant ContainerTransformTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.animation, widget.animation)) {
      _progress.dispose();
      _progress = _curve(widget.animation);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
    ContainerTransformOrigin origin,
    Rect full,
    ColorScheme scheme,
    Widget child,
  ) {
    final t = _progress.value.clamp(0.0, 1.0);
    final settled = t >= 1;
    final rect = settled ? full : Rect.lerp(origin.rect, full, t)!;
    final radius = BorderRadius.lerp(
      origin.borderRadius,
      BorderRadius.zero,
      t,
    )!;
    final scale = full.width > 0 ? rect.width / full.width : 1.0;
    final fill = containerTransformFillOpacity(t);
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
              clipBehavior: settled ? Clip.none : Clip.antiAlias,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: full.width,
                maxWidth: full.width,
                minHeight: full.height,
                maxHeight: full.height,
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.topLeft,
                  child: Opacity(
                    opacity: containerTransformContentOpacity(t),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 封面 Hero 的 [Hero.createRectTween]。Hero 内部固定用 fastOutSlowIn 驱动
/// 飞行，这里把它重映射为 [AppMotion.emphasized]，让封面与容器沿同一条曲线
/// 运动，飞行全程贴合容器的左上角。
///
/// Hero 只看目标端的 createRectTween（push 看页面端、pop 看卡片端），
/// 所以两端都要挂上。
Tween<Rect?> containerTransformHeroRectTween(Rect? begin, Rect? end) {
  return _EmphasizedHeroRectTween(begin: begin, end: end);
}

class _EmphasizedHeroRectTween extends RectTween {
  _EmphasizedHeroRectTween({super.begin, super.end});

  @override
  Rect? lerp(double t) => Rect.lerp(begin, end, emphasizedHeroProgress(t));
}

/// 把 Hero 传入的 fastOutSlowIn 进度换算成 emphasized 进度。
double emphasizedHeroProgress(double t) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  return AppMotion.emphasized.transform(_invertCurve(Curves.fastOutSlowIn, t));
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
/// * 卡片端封面打底，页面端封面在前半程淡入——两端图源不同（榜单渐变
///   占位 → 真实封面）时不再硬切；
/// * [overlay]（头图 scrim、顶栏）在落地前淡入，飞行结束时不再突然出现。
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
  return _ArtworkHeroShuttle(
    card: HeroArtworkShape.resolve(cardContext),
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

class _ArtworkHeroShuttle extends StatelessWidget {
  const _ArtworkHeroShuttle({
    required this.card,
    required this.page,
    required this.cardSize,
    required this.pageSize,
    required this.animation,
    required this.overlay,
  });

  static const Key shuttleKey = ValueKey('artwork-hero-shuttle');

  final ({BorderRadius borderRadius, Widget child}) card;
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
          final pageOpacity = ((progress - 0.15) / 0.35).clamp(0.0, 1.0);
          final overlayOpacity = ((progress - 0.55) / 0.45).clamp(0.0, 1.0);
          return ClipRRect(
            key: shuttleKey,
            borderRadius: radius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                card.child,
                Opacity(opacity: pageOpacity, child: page.child),
                if (overlay case final overlay?)
                  IgnorePointer(
                    child: Opacity(opacity: overlayOpacity, child: overlay),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
