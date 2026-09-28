import 'package:flutter/material.dart';

/// 路由退场时按需跳过反向动画：[animation] 开始反向的那一刻询问
/// [skipExit]，返回 true 则页面立即隐藏，不再播放收回/淡出。
///
/// 用于「页面被整体替换」而非「返回上一页」的场景——例如在详情页直接切到
/// 另一个底部 tab 时，GoRouter 会把详情页当作 pop 处理并播放退场动画，
/// 叠在新 tab 上显得像返回。
///
/// 包装层（[Offstage]）始终存在，稳定态不改变子树结构。
class SkippableExitTransition extends StatefulWidget {
  const SkippableExitTransition({
    super.key,
    required this.animation,
    required this.skipExit,
    required this.child,
  });

  final Animation<double> animation;
  final bool Function(BuildContext context) skipExit;
  final Widget child;

  @override
  State<SkippableExitTransition> createState() =>
      _SkippableExitTransitionState();
}

class _SkippableExitTransitionState extends State<SkippableExitTransition> {
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_handleStatus);
  }

  @override
  void didUpdateWidget(covariant SkippableExitTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.animation, widget.animation)) {
      oldWidget.animation.removeStatusListener(_handleStatus);
      widget.animation.addStatusListener(_handleStatus);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_handleStatus);
    super.dispose();
  }

  void _handleStatus(AnimationStatus status) {
    if (!mounted) return;
    final hidden = switch (status) {
      AnimationStatus.reverse => widget.skipExit(context),
      AnimationStatus.forward || AnimationStatus.completed => false,
      // 退场结束后路由即将销毁，保持隐藏，避免最后一帧闪现。
      AnimationStatus.dismissed => _hidden,
    };
    if (hidden != _hidden) setState(() => _hidden = hidden);
  }

  @override
  Widget build(BuildContext context) {
    return Offstage(offstage: _hidden, child: widget.child);
  }
}
