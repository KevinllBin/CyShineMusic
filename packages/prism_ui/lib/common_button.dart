import 'dart:math' as math;
import 'dart:ui' show clampDouble, lerpDouble;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/card_surface.dart';
import 'package:prism_ui/press_surface.dart';
import 'package:prism_ui/shape.dart';
import 'package:prism_ui/theme_data.dart';
import 'package:prism_ui/tooltip.dart';
import 'package:prism_ui/typography.dart';

/// Builds what stands behind a button's padded content and fills the button.
typedef ButtonLayerBuilder =
    Widget Function(
      BuildContext context,
      Set<WidgetState> states,
      Widget? child,
    );

/// How a button looks: each property comes from the button's own style, then
/// [ButtonTheme], then the defaults, as on a Material button.
@immutable
class ButtonStyle {
  const ButtonStyle({
    this.foregroundColor,
    this.backgroundColor,
    this.overlayColor,
    this.textStyle,
    this.side,
    this.shape,
    this.padding,
    this.minimumSize,
    this.fixedSize,
    this.maximumSize,
    this.iconSize,
    this.visualDensity,
    this.tapTargetSize,
    this.backgroundBuilder,
    this.pressLook,
    this.ringStandsOff,
  });

  /// Leaves an unset disabled color to the theme and the defaults.
  factory ButtonStyle.from({
    Color? foregroundColor,
    Color? disabledForegroundColor,
    Color? backgroundColor,
    Color? disabledBackgroundColor,
    TextStyle? textStyle,
    OutlinedBorder? shape,
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    Size? fixedSize,
    Size? maximumSize,
    double? iconSize,
    VisualDensity? visualDensity,
    TapTargetSize? tapTargetSize,
    ButtonLayerBuilder? backgroundBuilder,
    PressLook? pressLook,
    bool? ringStandsOff,
  }) => ButtonStyle(
    foregroundColor: _byEnabled(foregroundColor, disabledForegroundColor),
    backgroundColor: _byEnabled(backgroundColor, disabledBackgroundColor),
    textStyle: textStyle,
    shape: shape,
    padding: padding,
    minimumSize: minimumSize,
    fixedSize: fixedSize,
    maximumSize: maximumSize,
    iconSize: iconSize,
    visualDensity: visualDensity,
    tapTargetSize: tapTargetSize,
    backgroundBuilder: backgroundBuilder,
    pressLook: pressLook,
    ringStandsOff: ringStandsOff,
  );

  static WidgetStateProperty<Color?>? _byEnabled(
    Color? enabled,
    Color? disabled,
  ) {
    if ((enabled ?? disabled) == null) {
      return null;
    }
    return WidgetStateProperty<Color?>.fromMap({
      WidgetState.disabled: disabled,
      WidgetState.any: enabled,
    });
  }

  final WidgetStateProperty<Color?>? foregroundColor;
  final WidgetStateProperty<Color?>? backgroundColor;

  /// Laid over the background; a hover it resolves replaces the surface's.
  final WidgetStateProperty<Color?>? overlayColor;

  /// Takes [foregroundColor] for its color.
  final TextStyle? textStyle;
  final WidgetStateProperty<BorderSide?>? side;
  final OutlinedBorder? shape;
  final EdgeInsetsGeometry? padding;
  final Size? minimumSize;
  final Size? fixedSize;
  final Size? maximumSize;
  final double? iconSize;
  final VisualDensity? visualDensity;
  final TapTargetSize? tapTargetSize;
  final ButtonLayerBuilder? backgroundBuilder;
  final PressLook? pressLook;
  final bool? ringStandsOff;

  /// This style, taking from [other] what it leaves unset.
  ButtonStyle merge(ButtonStyle? other) {
    if (other == null) {
      return this;
    }
    return ButtonStyle(
      foregroundColor: foregroundColor ?? other.foregroundColor,
      backgroundColor: backgroundColor ?? other.backgroundColor,
      overlayColor: overlayColor ?? other.overlayColor,
      textStyle: textStyle ?? other.textStyle,
      side: side ?? other.side,
      shape: shape ?? other.shape,
      padding: padding ?? other.padding,
      minimumSize: minimumSize ?? other.minimumSize,
      fixedSize: fixedSize ?? other.fixedSize,
      maximumSize: maximumSize ?? other.maximumSize,
      iconSize: iconSize ?? other.iconSize,
      visualDensity: visualDensity ?? other.visualDensity,
      tapTargetSize: tapTargetSize ?? other.tapTargetSize,
      backgroundBuilder: backgroundBuilder ?? other.backgroundBuilder,
      pressLook: pressLook ?? other.pressLook,
      ringStandsOff: ringStandsOff ?? other.ringStandsOff,
    );
  }
}

/// A style for each kind of button: [IconButton], [TextButton],
/// [FilledButton] and [OutlinedButton].
@immutable
class ButtonThemeData {
  const ButtonThemeData({this.icon, this.text, this.filled, this.outlined});

  final ButtonStyle? icon;
  final ButtonStyle? text;
  final ButtonStyle? filled;
  final ButtonStyle? outlined;

  ButtonThemeData copyWith({
    ButtonStyle? icon,
    ButtonStyle? text,
    ButtonStyle? filled,
    ButtonStyle? outlined,
  }) => ButtonThemeData(
    icon: icon ?? this.icon,
    text: text ?? this.text,
    filled: filled ?? this.filled,
    outlined: outlined ?? this.outlined,
  );

  /// These styles, each taking from [other]'s what it leaves unset.
  ButtonThemeData merge(ButtonThemeData other) => ButtonThemeData(
    icon: icon?.merge(other.icon) ?? other.icon,
    text: text?.merge(other.text) ?? other.text,
    filled: filled?.merge(other.filled) ?? other.filled,
    outlined: outlined?.merge(other.outlined) ?? other.outlined,
  );
}

/// Styles the buttons below.
class ButtonTheme extends InheritedWidget {
  const ButtonTheme({super.key, required this.data, required super.child});

  final ButtonThemeData data;

  static ButtonThemeData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ButtonTheme>()?.data ??
      const ButtonThemeData();

  /// Lays [data] over the theme around [child].
  static Widget merge({required ButtonThemeData data, required Widget child}) =>
      _MergedButtonTheme(data: data, child: child);

  @override
  bool updateShouldNotify(ButtonTheme oldWidget) => data != oldWidget.data;
}

class _MergedButtonTheme extends StatelessWidget {
  const _MergedButtonTheme({required this.data, required this.child});

  final ButtonThemeData data;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ButtonTheme(data: data.merge(ButtonTheme.of(context)), child: child);
  }
}

// Rounds alpha as Color.withOpacity, which the Material defaults use, does.
Color _faded(Color color, double opacity) =>
    color.withAlpha((255 * opacity).round());

/// An icon button pressed as iOS 27 presses one: no ripple, a tint while
/// held. See Press in `.agents/surfaces.md`.
class IconButton extends StatelessWidget {
  const IconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.selectedIcon,
    this.isSelected,
    this.tooltip,
    this.iconSize,
    this.padding,
    this.style,
  }) : _filled = false;

  const IconButton.filled({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.iconSize,
    this.padding,
    this.style,
  }) : selectedIcon = null,
       isSelected = null,
       _filled = true;

  final VoidCallback? onPressed;
  final Widget icon;
  final Widget? selectedIcon;
  final bool? isSelected;
  final String? tooltip;
  final double? iconSize;
  final EdgeInsetsGeometry? padding;
  final ButtonStyle? style;
  final bool _filled;

  // As IconButton does, an icon theme around the button colors and sizes it
  // under the button theme.
  static ButtonStyle _themeStyleOf(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final defaultColor = switch (Theme.brightnessOf(context)) {
      Brightness.light => const Color(0xDD000000),
      Brightness.dark => Colors.white,
    };
    final ambient = ButtonStyle.from(
      foregroundColor: identical(iconTheme.color, defaultColor)
          ? null
          : iconTheme.color,
      iconSize: iconTheme.size == const IconThemeData.fallback().size
          ? null
          : iconTheme.size,
    );
    return ButtonTheme.of(context).icon?.merge(ambient) ?? ambient;
  }

  // The Material 3 defaults of IconButton and IconButton.filled.
  ButtonStyle _defaultsOf(ThemeData theme) {
    final colors = theme.colorScheme;
    return ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return _faded(colors.onSurface, 0.38);
        }
        if (_filled) {
          return colors.onPrimary;
        }
        return states.contains(WidgetState.selected)
            ? colors.primary
            : colors.onSurfaceVariant;
      }),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (!_filled) {
          return Colors.transparent;
        }
        return states.contains(WidgetState.disabled)
            ? _faded(colors.onSurface, 0.12)
            : colors.primary;
      }),
      shape: AppShape.full,
      padding: const EdgeInsets.all(8),
      minimumSize: const Size.square(40),
      maximumSize: Size.infinite,
      iconSize: 24,
      visualDensity: VisualDensity.standard,
      tapTargetSize: theme.tapTargetSize,
      pressLook: PressLook.tint,
      ringStandsOff: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = iconSize == null && padding == null
        ? this.style
        : (this.style ?? const ButtonStyle()).merge(
            ButtonStyle(iconSize: iconSize, padding: padding),
          );
    final selectedIcon = this.selectedIcon;
    return _StyledButton(
      style: style,
      themeStyle: _themeStyleOf(context),
      defaults: _defaultsOf(Theme.of(context)),
      onPressed: onPressed,
      selected: isSelected ?? false,
      tooltip: tooltip,
      child: isSelected == true && selectedIcon != null ? selectedIcon : icon,
    );
  }
}

typedef _LabelColors = ({
  WidgetStateProperty<Color?> foreground,
  WidgetStateProperty<Color?> background,
  WidgetStateProperty<BorderSide?>? side,
  bool ringStandsOff,
});

/// A labelled button, with [icon] before the label when given, laid out and
/// colored by the Material 3 defaults of the button it stands for.
abstract class _LabelButton extends StatelessWidget {
  const _LabelButton({
    super.key,
    required this.onPressed,
    this.style,
    required this.child,
  }) : icon = null;

  const _LabelButton.icon({
    super.key,
    required this.onPressed,
    this.style,
    required Widget this.icon,
    required Widget label,
  }) : child = label;

  final VoidCallback? onPressed;
  final ButtonStyle? style;
  final Widget? icon;
  final Widget child;

  ButtonStyle? _themeStyleOf(ButtonThemeData theme);

  _LabelColors _colorsOf(ColorScheme colors);

  EdgeInsetsGeometry _paddingOf(double textScale);

  ButtonStyle _defaultsOf(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = AppTextStyle.subheadline.of(context, emphasized: true);
    final textScale =
        MediaQuery.textScalerOf(context).scale(textStyle.fontSize ?? 14) / 14;
    final colors = _colorsOf(theme.colorScheme);
    return ButtonStyle(
      foregroundColor: colors.foreground,
      backgroundColor: colors.background,
      textStyle: textStyle,
      side: colors.side,
      shape: AppShape.full,
      padding: _paddingOf(textScale),
      minimumSize: const Size(64, 40),
      maximumSize: Size.infinite,
      iconSize: 18,
      visualDensity: theme.visualDensity,
      tapTargetSize: theme.tapTargetSize,
      pressLook: PressLook.tint,
      ringStandsOff: colors.ringStandsOff,
    );
  }

  @override
  Widget build(BuildContext context) {
    var content = child;
    if (icon case final icon?) {
      final scale =
          clampDouble(
            MediaQuery.textScalerOf(
                  context,
                ).scale(style?.textStyle?.fontSize ?? 14) /
                14,
            1,
            2,
          ) -
          1;
      content = Row(
        mainAxisSize: MainAxisSize.min,
        spacing: lerpDouble(8, 4, scale)!,
        children: [
          icon,
          Flexible(child: child),
        ],
      );
    }
    return _StyledButton(
      style: style,
      themeStyle: _themeStyleOf(ButtonTheme.of(context)),
      defaults: _defaultsOf(context),
      onPressed: onPressed,
      selected: false,
      tooltip: null,
      child: content,
    );
  }
}

EdgeInsetsGeometry _scaledPadding(
  EdgeInsetsGeometry geometry1x,
  EdgeInsetsGeometry geometry2x,
  EdgeInsetsGeometry geometry3x,
  double textScale,
) => switch (textScale) {
  <= 1 => geometry1x,
  < 2 => EdgeInsetsGeometry.lerp(geometry1x, geometry2x, textScale - 1)!,
  < 3 => EdgeInsetsGeometry.lerp(geometry2x, geometry3x, textScale - 2)!,
  _ => geometry3x,
};

WidgetStateProperty<Color?> _disabledOr(ColorScheme colors, Color enabled) =>
    WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? _faded(colors.onSurface, 0.38)
          : enabled,
    );

/// Laid out as a Material 3 text button, pressed as [IconButton] is.
class TextButton extends _LabelButton {
  const TextButton({
    super.key,
    required super.onPressed,
    super.style,
    required super.child,
  });

  const TextButton.icon({
    super.key,
    required super.onPressed,
    super.style,
    required super.icon,
    required super.label,
  }) : super.icon();

  @override
  ButtonStyle? _themeStyleOf(ButtonThemeData theme) => theme.text;

  @override
  _LabelColors _colorsOf(ColorScheme colors) => (
    foreground: _disabledOr(colors, colors.primary),
    background: const WidgetStatePropertyAll(Colors.transparent),
    side: null,
    ringStandsOff: false,
  );

  @override
  EdgeInsetsGeometry _paddingOf(double textScale) => icon == null
      ? _scaledPadding(
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          const EdgeInsets.symmetric(horizontal: 8),
          const EdgeInsets.symmetric(horizontal: 4),
          textScale,
        )
      : _scaledPadding(
          const EdgeInsetsDirectional.fromSTEB(12, 8, 16, 8),
          const EdgeInsets.symmetric(horizontal: 4),
          const EdgeInsets.symmetric(horizontal: 4),
          textScale,
        );
}

EdgeInsetsGeometry _filledPaddingOf(bool withIcon, double textScale) => withIcon
    ? _scaledPadding(
        const EdgeInsetsDirectional.fromSTEB(16, 0, 24, 0),
        const EdgeInsetsDirectional.fromSTEB(8, 0, 12, 0),
        const EdgeInsetsDirectional.fromSTEB(4, 0, 6, 0),
        textScale,
      )
    : _scaledPadding(
        const EdgeInsets.symmetric(horizontal: 24),
        const EdgeInsets.symmetric(horizontal: 12),
        const EdgeInsets.symmetric(horizontal: 6),
        textScale,
      );

/// Laid out as a Material 3 filled button, pressed as [IconButton] is.
class FilledButton extends _LabelButton {
  const FilledButton({
    super.key,
    required super.onPressed,
    super.style,
    required super.child,
  });

  const FilledButton.icon({
    super.key,
    required super.onPressed,
    super.style,
    required super.icon,
    required super.label,
  }) : super.icon();

  @override
  ButtonStyle? _themeStyleOf(ButtonThemeData theme) => theme.filled;

  @override
  _LabelColors _colorsOf(ColorScheme colors) => (
    foreground: _disabledOr(colors, colors.onPrimary),
    background: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? _faded(colors.onSurface, 0.12)
          : colors.primary,
    ),
    side: null,
    ringStandsOff: true,
  );

  @override
  EdgeInsetsGeometry _paddingOf(double textScale) =>
      _filledPaddingOf(icon != null, textScale);
}

/// Laid out as a Material 3 outlined button, pressed as [IconButton]
/// is.
class OutlinedButton extends _LabelButton {
  const OutlinedButton({
    super.key,
    required super.onPressed,
    super.style,
    required super.child,
  });

  const OutlinedButton.icon({
    super.key,
    required super.onPressed,
    super.style,
    required super.icon,
    required super.label,
  }) : super.icon();

  @override
  ButtonStyle? _themeStyleOf(ButtonThemeData theme) => theme.outlined;

  @override
  _LabelColors _colorsOf(ColorScheme colors) => (
    foreground: _disabledOr(colors, colors.primary),
    background: const WidgetStatePropertyAll(Colors.transparent),
    side: WidgetStateProperty.resolveWith(
      (states) => BorderSide(
        color: states.contains(WidgetState.disabled)
            ? _faded(colors.onSurface, 0.12)
            : colors.outline,
      ),
    ),
    ringStandsOff: false,
  );

  @override
  EdgeInsetsGeometry _paddingOf(double textScale) =>
      _filledPaddingOf(icon != null, textScale);
}

/// A [PressSurface] laid out and colored by a resolved [ButtonStyle].
class _StyledButton extends StatefulWidget {
  const _StyledButton({
    required this.style,
    required this.themeStyle,
    required this.defaults,
    required this.onPressed,
    required this.selected,
    required this.tooltip,
    required this.child,
  });

  final ButtonStyle? style;
  final ButtonStyle? themeStyle;

  final ButtonStyle defaults;
  final VoidCallback? onPressed;
  final bool selected;
  final String? tooltip;
  final Widget child;

  @override
  State<_StyledButton> createState() => _StyledButtonState();
}

class _StyledButtonState extends State<_StyledButton> {
  final _states = WidgetStatesController();

  @override
  void initState() {
    super.initState();
    _syncStates();
    _states.addListener(_handleStates);
  }

  @override
  void didUpdateWidget(_StyledButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncStates();
  }

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  void _syncStates() {
    _states
      ..update(WidgetState.disabled, widget.onPressed == null)
      ..update(WidgetState.selected, widget.selected);
  }

  void _handleStates() => setState(() {});

  T? _resolve<T>(T? Function(ButtonStyle? style) property) =>
      property(widget.style) ??
      property(widget.themeStyle) ??
      property(widget.defaults);

  T? _resolveFor<T>(
    WidgetStateProperty<T?>? Function(ButtonStyle? style) property,
  ) {
    final states = _states.value;
    return property(widget.style)?.resolve(states) ??
        property(widget.themeStyle)?.resolve(states) ??
        property(widget.defaults)?.resolve(states);
  }

  bool get _stylesHover {
    final hovered = {..._states.value, WidgetState.hovered};
    final overlay =
        widget.style?.overlayColor?.resolve(hovered) ??
        widget.themeStyle?.overlayColor?.resolve(hovered) ??
        widget.defaults.overlayColor?.resolve(hovered);
    return overlay != null && overlay.a > 0;
  }

  BoxConstraints _constraintsOf(VisualDensity density) {
    final minimum = _resolve((style) => style?.minimumSize)!;
    final maximum = _resolve((style) => style?.maximumSize)!;
    var constraints = density.effectiveConstraints(
      BoxConstraints(
        minWidth: minimum.width,
        minHeight: minimum.height,
        maxWidth: maximum.width,
        maxHeight: maximum.height,
      ),
    );
    if (_resolve((style) => style?.fixedSize) case final fixed?) {
      final size = constraints.constrain(fixed);
      if (size.width.isFinite) {
        constraints = constraints.copyWith(
          minWidth: size.width,
          maxWidth: size.width,
        );
      }
      if (size.height.isFinite) {
        constraints = constraints.copyWith(
          minHeight: size.height,
          maxHeight: size.height,
        );
      }
    }
    return constraints;
  }

  @override
  Widget build(BuildContext context) {
    final density = _resolve((style) => style?.visualDensity)!;
    final adjustment = density.baseSizeAdjustment;
    // A density may shorten a button but never narrow its padding.
    final dx = math.max(0.0, adjustment.dx);
    final padding = _resolve((style) => style?.padding)!
        .add(EdgeInsets.fromLTRB(dx, adjustment.dy, dx, adjustment.dy))
        .clamp(EdgeInsets.zero, EdgeInsetsGeometry.infinity)
        .resolve(Directionality.of(context));
    final tapTarget = switch (_resolve((style) => style?.tapTargetSize)!) {
      TapTargetSize.padded => Size(
        kMinInteractiveDimension + adjustment.dx,
        kMinInteractiveDimension + adjustment.dy,
      ),
      TapTargetSize.shrinkWrap => Size.zero,
    };
    final background = _resolveFor((style) => style?.backgroundColor);
    final overlay = _resolveFor((style) => style?.overlayColor);
    final fill = overlay == null || overlay.a == 0
        ? background ?? Colors.transparent
        : Color.alphaBlend(overlay, background ?? Colors.transparent);
    final backgroundBuilder = _resolve((style) => style?.backgroundBuilder);
    // Laid out inside the surface as a Material button lays it out inside its
    // ink, so a background and the tooltip's hover span the button.
    Widget content = Padding(
      padding: padding,
      child: Align(widthFactor: 1, heightFactor: 1, child: widget.child),
    );
    if (backgroundBuilder != null) {
      content = backgroundBuilder(context, _states.value, content);
    }
    if (widget.tooltip case final tooltip?) {
      content = Tooltip(message: tooltip, child: content);
    }
    return PressSurface(
      fill: fill,
      shape: _resolve((style) => style?.shape)!,
      look: _resolve((style) => style?.pressLook)!,
      side: _resolveFor((style) => style?.side) ?? BorderSide.none,
      ringStandsOff: _resolve((style) => style?.ringStandsOff)!,
      foreground: _resolveFor((style) => style?.foregroundColor),
      iconSize: _resolve((style) => style?.iconSize),
      textStyle: _resolve((style) => style?.textStyle),
      minimum: _constraintsOf(density),
      tapTarget: tapTarget,
      onPressed: widget.onPressed,
      selected: widget.selected,
      statesController: _states,
      reportsHover: true,
      showsHover: !_stylesHover,
      childFills: true,
      clipsChild: backgroundBuilder != null,
      child: content,
    );
  }
}
