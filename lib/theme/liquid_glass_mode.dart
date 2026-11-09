enum LiquidGlassMode {
  none('none', '关闭'),
  standard('standard', '标准'),
  ultra('ultra', '增强');

  const LiquidGlassMode(this.code, this.label);

  final String code;
  final String label;

  static LiquidGlassMode fromCode(String? code) =>
      values.firstWhere((mode) => mode.code == code, orElse: () => standard);
}
