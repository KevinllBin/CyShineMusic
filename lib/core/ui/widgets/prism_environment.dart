import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

import '../../../theme/app_theme.dart';
import '../../../theme/liquid_glass_mode.dart';

/// Supplies Prism UI library alongside the app's Material music screens.
class PrismEnvironment extends StatelessWidget {
  const PrismEnvironment({
    super.key,
    required this.child,
    this.mode = LiquidGlassMode.standard,
  });

  final Widget child;
  final LiquidGlassMode mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    return prism.Theme(
      data: prism.ThemeData(
        colorScheme: prism.ColorScheme(
          brightness: scheme.brightness,
          primary: scheme.primary,
          onPrimary: scheme.onPrimary,
          primaryContainer: scheme.primaryContainer,
          onPrimaryContainer: scheme.onPrimaryContainer,
          secondary: scheme.secondary,
          onSecondary: scheme.onSecondary,
          secondaryContainer: scheme.secondaryContainer,
          onSecondaryContainer: scheme.onSecondaryContainer,
          tertiary: scheme.tertiary,
          onTertiary: scheme.onTertiary,
          tertiaryContainer: scheme.tertiaryContainer,
          onTertiaryContainer: scheme.onTertiaryContainer,
          error: scheme.error,
          onError: scheme.onError,
          surface: scheme.surface,
          onSurface: scheme.onSurface,
          surfaceBright: scheme.surfaceBright,
          surfaceContainerLowest: scheme.surfaceContainerLowest,
          surfaceContainerLow: scheme.surfaceContainerLow,
          surfaceContainer: scheme.surfaceContainer,
          surfaceContainerHigh: scheme.surfaceContainerHigh,
          surfaceContainerHighest: scheme.surfaceContainerHighest,
          onSurfaceVariant: scheme.onSurfaceVariant,
          outline: scheme.outline,
          outlineVariant: scheme.outlineVariant,
          shadow: scheme.shadow,
          scrim: scheme.scrim,
        ),
        fontFamilyFallback: AppTheme.fontFallback,
      ),
      child: Builder(
        builder: (context) => prism.MeasureScope(
          measure: prism.Measure.of(
            context,
            MediaQuery.textScalerOf(context).scale(1),
          ),
          child: prism.ViewScope(
            size: size,
            isMobile: size.width < 600,
            child: prism.LiquidGlassScope(
              enabled: mode != LiquidGlassMode.none,
              quality: mode == LiquidGlassMode.ultra
                  ? prism.LiquidGlassQuality.ultra
                  : prism.LiquidGlassQuality.standard,
              child: prism.LiquidGlassHost(
                enabled: mode != LiquidGlassMode.none,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PrismChineseStrings extends prism.UiLocalizations {
  static const delegate = _PrismStringsDelegate();

  @override
  String get back => '返回';
  @override
  String get cancel => '取消';
  @override
  String get clearSearch => '清除搜索';
  @override
  String get close => '关闭';
  @override
  String get copy => '复制';
  @override
  String get cut => '剪切';
  @override
  String get dialog => '对话框';
  @override
  String get hidePassword => '隐藏密码';
  @override
  String get more => '更多';
  @override
  String get noSearchResults => '没有搜索结果';
  @override
  String get paste => '粘贴';
  @override
  String get reset => '重置';
  @override
  String get select => '选择';
  @override
  String get search => '搜索';
  @override
  String get selectAll => '全选';
  @override
  String get showLess => '收起';
  @override
  String get showMore => '展开';
  @override
  String get showPassword => '显示密码';
  @override
  String get sort => '排序';
  @override
  String get submit => '完成';
}

class _PrismStringsDelegate
    extends LocalizationsDelegate<prism.UiLocalizations> {
  const _PrismStringsDelegate();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<prism.UiLocalizations> load(Locale locale) =>
      SynchronousFuture(PrismChineseStrings());
  @override
  bool shouldReload(_PrismStringsDelegate old) => false;
}
