import 'package:flutter/widgets.dart';

/// 路由过渡结束前把 [callback] 推迟到动画完成后执行一次；路由已稳定时
/// 返回 false，由调用方立即执行。
///
/// 整页从骨架换成真实内容、主题插值这类重活如果落在容器变换中途，会和
/// 过渡抢帧，还会卸载正在飞行的封面 Hero；等过渡结束再做。返回途中不会
/// 触发——路由即将销毁。
bool deferUntilRouteSettled(BuildContext context, VoidCallback callback) {
  final animation = ModalRoute.of(context)?.animation;
  if (animation == null || animation.status == AnimationStatus.completed) {
    return false;
  }
  void listener(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      animation.removeStatusListener(listener);
      callback();
    } else if (status == AnimationStatus.dismissed) {
      animation.removeStatusListener(listener);
    }
  }

  animation.addStatusListener(listener);
  return true;
}
