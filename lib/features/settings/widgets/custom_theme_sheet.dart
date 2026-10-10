import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/color_style.dart';
import '../../../theme/custom_theme.dart';
import 'color_picker_sheet.dart';

Future<CustomTheme?> showCustomThemeSheet(
  BuildContext context,
  CustomTheme initial, {
  required Color seed,
  required AppColorStyle style,
}) {
  final app = context.findAncestorWidgetOfExactType<MaterialApp>();
  final light =
      app?.theme?.extension<AppThemeBase>()?.scheme ??
      AppTheme.schemeFor(seed, Brightness.light, style);
  final dark =
      app?.darkTheme?.extension<AppThemeBase>()?.scheme ??
      AppTheme.schemeFor(seed, Brightness.dark, style);
  return showModalBottomSheet<CustomTheme>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: _CustomThemeSheet(
        initial: initial,
        brightness: Theme.of(context).brightness,
        light: light,
        dark: dark,
        style: style,
      ),
    ),
  );
}

class _CustomThemeSheet extends StatefulWidget {
  const _CustomThemeSheet({
    required this.initial,
    required this.brightness,
    required this.light,
    required this.dark,
    required this.style,
  });

  final CustomTheme initial;
  final Brightness brightness;
  final ColorScheme light;
  final ColorScheme dark;
  final AppColorStyle style;

  @override
  State<_CustomThemeSheet> createState() => _CustomThemeSheetState();
}

class _CustomThemeSheetState extends State<_CustomThemeSheet> {
  late CustomTheme _draft = widget.initial;
  late Brightness _brightness = widget.brightness;

  CustomThemeColors get _colors => _draft.colorsFor(_brightness);
  ColorScheme get _base =>
      _brightness == Brightness.dark ? widget.dark : widget.light;

  ThemeData _themeFor(CustomThemeColors colors) => AppTheme.fromScheme(
    _base,
    colors: _draft.enabled ? colors : null,
    style: widget.style,
  );

  void _setColors(CustomThemeColors colors) {
    setState(() {
      _draft = _brightness == Brightness.dark
          ? _draft.copyWith(dark: colors)
          : _draft.copyWith(light: colors);
    });
  }

  Color _effectiveColor(ThemeData theme, ThemeColorRole role) => switch (role) {
    ThemeColorRole.accent => theme.colorScheme.primary,
    ThemeColorRole.background => theme.scaffoldBackgroundColor,
    ThemeColorRole.container => theme.colorScheme.surfaceContainerLow,
    ThemeColorRole.text => theme.colorScheme.onSurface,
    ThemeColorRole.secondaryText => theme.colorScheme.onSurfaceVariant,
  };

  String _colorLabel(Color? color) => color == null
      ? '跟随基础主题 / 自动匹配'
      : '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Future<void> _pickColor(ThemeColorRole role) async {
    final colors = _colors;
    final theme = _themeFor(colors);
    final selected = await showColorPickerSheet(
      context,
      colors.colorFor(role) ??
          Color.alphaBlend(
            _effectiveColor(theme, role),
            theme.colorScheme.surfaceContainerLow,
          ),
      allowAlpha: false,
      title: '${_brightness == Brightness.dark ? '深色' : '浅色'} · ${role.label}',
      previewBuilder: (color) =>
          _ThemePreview(theme: _themeFor(colors.withColor(role, color))),
    );
    if (selected != null && mounted) {
      _setColors(colors.withColor(role, selected));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _themeFor(_colors);
    final scheme = theme.colorScheme;
    final surfaces = [
      theme.scaffoldBackgroundColor,
      scheme.surfaceContainerLow,
    ];
    final lowContrast = surfaces.any(
      (background) =>
          colorContrast(scheme.onSurface, background) < 4.5 ||
          colorContrast(scheme.onSurfaceVariant, background) < 4.5,
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('自定义主题', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用自定义配色'),
              subtitle: const Text('未设置的颜色跟随基础主题，文字默认自动匹配'),
              value: _draft.enabled,
              onChanged: (enabled) =>
                  setState(() => _draft = _draft.copyWith(enabled: enabled)),
            ),
            const SizedBox(height: 8),
            SegmentedButton<Brightness>(
              segments: const [
                ButtonSegment(
                  value: Brightness.light,
                  label: Text('浅色主题'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: Brightness.dark,
                  label: Text('深色主题'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: {_brightness},
              onSelectionChanged: (selection) =>
                  setState(() => _brightness = selection.single),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  _ThemePreview(theme: theme),
                  if (lowContrast) ...[
                    const SizedBox(height: 8),
                    const Text('部分文字与背景对比度较低，建议调整文字或背景颜色。'),
                  ],
                  const SizedBox(height: 8),
                  for (final role in ThemeColorRole.values)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      enabled: _draft.enabled,
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _effectiveColor(theme, role),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                      title: Text(role.label),
                      subtitle: Text(_colorLabel(_colors.colorFor(role))),
                      trailing: _colors.colorFor(role) != null
                          ? IconButton(
                              tooltip: '重置${role.label}',
                              icon: const Icon(Icons.restart_alt),
                              onPressed: _draft.enabled
                                  ? () => _setColors(
                                      _colors.withColor(role, null),
                                    )
                                  : null,
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: _draft.enabled ? () => _pickColor(role) : null,
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _draft.enabled
                          ? () => _setColors(const CustomThemeColors())
                          : null,
                      child: const Text('重置此模式的配色'),
                    ),
                  ),
                  const Text('启用自定义主题时会关闭歌单详情动态配色，可在外观设置中重新开启。'),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_draft),
                  child: const Text('应用'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    return Theme(
      data: theme,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('主题预览', style: TextStyle(color: scheme.onSurface)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.music_note_rounded, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('歌曲名称', style: TextStyle(color: scheme.onSurface)),
                        Text(
                          '歌手 · 专辑',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.play_arrow, color: scheme.onPrimary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
