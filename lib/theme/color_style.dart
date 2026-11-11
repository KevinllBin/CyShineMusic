import 'package:flutter/material.dart';

/// 配色风格：决定种子色如何展开成完整的 Material 3 配色。
///
/// 同一个种子色在不同风格下差异很大，因为各 variant 对彩度（HCT chroma）
/// 的处理完全不同：`tonalSpot` 会把任意种子色归一化到 chroma≈36，
/// 而 `fidelity` / `vibrant` 会保留种子色本身的鲜艳度。
enum AppColorStyle {
  soft('soft', '柔和', '低饱和，接近系统默认', DynamicSchemeVariant.tonalSpot),
  vivid('vivid', '鲜明', '保留色相并提高彩度', DynamicSchemeVariant.vibrant),
  faithful('faithful', '忠实', '尽量还原所选颜色', DynamicSchemeVariant.fidelity),
  creative('creative', '创意', '偏移色相，配色更跳', DynamicSchemeVariant.expressive);

  const AppColorStyle(this.code, this.label, this.description, this.variant);

  final String code;
  final String label;
  final String description;
  final DynamicSchemeVariant variant;

  static const AppColorStyle fallback = AppColorStyle.soft;

  static AppColorStyle fromCode(String? code) {
    if (code == null) return fallback;
    for (final style in AppColorStyle.values) {
      if (style.code == code) return style;
    }
    return fallback;
  }

  static bool isKnownCode(String code) {
    for (final style in AppColorStyle.values) {
      if (style.code == code) return true;
    }
    return false;
  }
}
