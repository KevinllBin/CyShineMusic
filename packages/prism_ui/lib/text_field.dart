import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart'
    show DragStartBehavior, PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/context.dart';
import 'package:prism_ui/input_border.dart';
import 'package:prism_ui/navigation_dock.dart';
import 'package:prism_ui/shape.dart';
import 'package:prism_ui/text_loupe.dart';
import 'package:prism_ui/text_selection_controls.dart';
import 'package:prism_ui/text_selection_menu.dart';
import 'package:prism_ui/theme_data.dart';
import 'package:prism_ui/typography.dart';

export 'package:prism_ui/input_border.dart';

const _minFieldHeight = 48.0;
const _inputGap = 4.0;
const _subtextGap = 4.0;
const _iconToInputGap = 4.0;
const _borderDuration = Duration(milliseconds: 167);
const _hintFade = Duration(milliseconds: 20);

typedef InputCounterWidgetBuilder =
    Widget? Function(
      BuildContext context, {
      required int currentLength,
      required int? maxLength,
      required bool isFocused,
    });

class InputDecoration {
  const InputDecoration({
    this.hint,
    this.hintText,
    this.hintStyle,
    this.hintMaxLines,
    this.helperText,
    this.error,
    this.errorText,
    this.errorStyle,
    this.errorMaxLines,
    this.counter,
    this.counterText,
    this.counterStyle,
    this.prefix,
    this.prefixText,
    this.prefixStyle,
    this.suffix,
    this.suffixText,
    this.suffixStyle,
    this.prefixIcon,
    this.suffixIcon,
    this.prefixIconConstraints,
    this.suffixIconConstraints,
    this.constraints,
    this.contentPadding,
    this.isDense,
    this.isCollapsed,
    this.filled,
    this.fillColor,
    this.hoverColor,
    this.border,
    this.enabledBorder,
    this.disabledBorder,
    this.focusedBorder,
    this.errorBorder,
    this.focusedErrorBorder,
    this.enabled = true,
  });

  const InputDecoration.collapsed({
    required this.hintText,
    this.hint,
    this.hintStyle,
    this.hintMaxLines,
    this.filled,
    this.fillColor,
    this.hoverColor,
    this.border = const NoInputBorder(),
    this.enabled = true,
  }) : helperText = null,
       error = null,
       errorText = null,
       errorStyle = null,
       errorMaxLines = null,
       counter = null,
       counterText = null,
       counterStyle = null,
       prefix = null,
       prefixText = null,
       prefixStyle = null,
       suffix = null,
       suffixText = null,
       suffixStyle = null,
       prefixIcon = null,
       suffixIcon = null,
       prefixIconConstraints = null,
       suffixIconConstraints = null,
       constraints = null,
       contentPadding = EdgeInsets.zero,
       isDense = false,
       isCollapsed = true,
       enabledBorder = null,
       disabledBorder = null,
       focusedBorder = null,
       errorBorder = null,
       focusedErrorBorder = null;

  final Widget? hint;
  final String? hintText;
  final TextStyle? hintStyle;
  final int? hintMaxLines;
  final String? helperText;
  final Widget? error;
  final String? errorText;
  final TextStyle? errorStyle;
  final int? errorMaxLines;
  final Widget? counter;
  final String? counterText;
  final TextStyle? counterStyle;
  final Widget? prefix;
  final String? prefixText;
  final TextStyle? prefixStyle;
  final Widget? suffix;
  final String? suffixText;
  final TextStyle? suffixStyle;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final BoxConstraints? prefixIconConstraints;
  final BoxConstraints? suffixIconConstraints;

  /// Bounds the field along with its error and counter lines.
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? contentPadding;
  final bool? isDense;
  final bool? isCollapsed;
  final bool? filled;
  final Color? fillColor;
  final Color? hoverColor;
  final InputBorder? border;
  final InputBorder? enabledBorder;
  final InputBorder? disabledBorder;
  final InputBorder? focusedBorder;
  final InputBorder? errorBorder;
  final InputBorder? focusedErrorBorder;
  final bool enabled;

  InputDecoration copyWith({
    Widget? hint,
    String? hintText,
    TextStyle? hintStyle,
    int? hintMaxLines,
    String? helperText,
    Widget? error,
    String? errorText,
    TextStyle? errorStyle,
    int? errorMaxLines,
    Widget? counter,
    String? counterText,
    TextStyle? counterStyle,
    Widget? prefix,
    String? prefixText,
    TextStyle? prefixStyle,
    Widget? suffix,
    String? suffixText,
    TextStyle? suffixStyle,
    Widget? prefixIcon,
    Widget? suffixIcon,
    BoxConstraints? prefixIconConstraints,
    BoxConstraints? suffixIconConstraints,
    BoxConstraints? constraints,
    EdgeInsetsGeometry? contentPadding,
    bool? isDense,
    bool? isCollapsed,
    bool? filled,
    Color? fillColor,
    Color? hoverColor,
    InputBorder? border,
    InputBorder? enabledBorder,
    InputBorder? disabledBorder,
    InputBorder? focusedBorder,
    InputBorder? errorBorder,
    InputBorder? focusedErrorBorder,
    bool? enabled,
  }) {
    return InputDecoration(
      hint: hint ?? this.hint,
      hintText: hintText ?? this.hintText,
      hintStyle: hintStyle ?? this.hintStyle,
      hintMaxLines: hintMaxLines ?? this.hintMaxLines,
      helperText: helperText ?? this.helperText,
      error: error ?? this.error,
      errorText: errorText ?? this.errorText,
      errorStyle: errorStyle ?? this.errorStyle,
      errorMaxLines: errorMaxLines ?? this.errorMaxLines,
      counter: counter ?? this.counter,
      counterText: counterText ?? this.counterText,
      counterStyle: counterStyle ?? this.counterStyle,
      prefix: prefix ?? this.prefix,
      prefixText: prefixText ?? this.prefixText,
      prefixStyle: prefixStyle ?? this.prefixStyle,
      suffix: suffix ?? this.suffix,
      suffixText: suffixText ?? this.suffixText,
      suffixStyle: suffixStyle ?? this.suffixStyle,
      prefixIcon: prefixIcon ?? this.prefixIcon,
      suffixIcon: suffixIcon ?? this.suffixIcon,
      prefixIconConstraints:
          prefixIconConstraints ?? this.prefixIconConstraints,
      suffixIconConstraints:
          suffixIconConstraints ?? this.suffixIconConstraints,
      constraints: constraints ?? this.constraints,
      contentPadding: contentPadding ?? this.contentPadding,
      isDense: isDense ?? this.isDense,
      isCollapsed: isCollapsed ?? this.isCollapsed,
      filled: filled ?? this.filled,
      fillColor: fillColor ?? this.fillColor,
      hoverColor: hoverColor ?? this.hoverColor,
      border: border ?? this.border,
      enabledBorder: enabledBorder ?? this.enabledBorder,
      disabledBorder: disabledBorder ?? this.disabledBorder,
      focusedBorder: focusedBorder ?? this.focusedBorder,
      errorBorder: errorBorder ?? this.errorBorder,
      focusedErrorBorder: focusedErrorBorder ?? this.focusedErrorBorder,
      enabled: enabled ?? this.enabled,
    );
  }

  InputDecoration applyDefaults(InputDecorationThemeData theme) {
    return copyWith(
      contentPadding: contentPadding ?? theme.contentPadding,
      isDense: isDense ?? theme.isDense,
      isCollapsed: isCollapsed ?? theme.isCollapsed,
      filled: filled ?? theme.filled,
      fillColor: fillColor ?? theme.fillColor,
      hoverColor: hoverColor ?? theme.hoverColor,
      border: border ?? theme.border,
      enabledBorder: enabledBorder ?? theme.enabledBorder,
      disabledBorder: disabledBorder ?? theme.disabledBorder,
      focusedBorder: focusedBorder ?? theme.focusedBorder,
      errorBorder: errorBorder ?? theme.errorBorder,
      focusedErrorBorder: focusedErrorBorder ?? theme.focusedErrorBorder,
    );
  }
}

class InputDecorationThemeData {
  const InputDecorationThemeData({
    this.contentPadding,
    this.isDense = false,
    this.isCollapsed = false,
    this.filled = false,
    this.fillColor,
    this.hoverColor,
    this.border = AppShape.input,
    this.enabledBorder,
    this.disabledBorder,
    this.focusedBorder,
    this.errorBorder,
    this.focusedErrorBorder,
  });

  final EdgeInsetsGeometry? contentPadding;
  final bool isDense;
  final bool isCollapsed;
  final bool filled;
  final Color? fillColor;
  final Color? hoverColor;
  final InputBorder? border;
  final InputBorder? enabledBorder;
  final InputBorder? disabledBorder;
  final InputBorder? focusedBorder;
  final InputBorder? errorBorder;
  final InputBorder? focusedErrorBorder;

  InputDecorationThemeData copyWith({
    EdgeInsetsGeometry? contentPadding,
    bool? isDense,
    bool? isCollapsed,
    bool? filled,
    Color? fillColor,
    Color? hoverColor,
    InputBorder? border,
    InputBorder? enabledBorder,
    InputBorder? disabledBorder,
    InputBorder? focusedBorder,
    InputBorder? errorBorder,
    InputBorder? focusedErrorBorder,
  }) {
    return InputDecorationThemeData(
      contentPadding: contentPadding ?? this.contentPadding,
      isDense: isDense ?? this.isDense,
      isCollapsed: isCollapsed ?? this.isCollapsed,
      filled: filled ?? this.filled,
      fillColor: fillColor ?? this.fillColor,
      hoverColor: hoverColor ?? this.hoverColor,
      border: border ?? this.border,
      enabledBorder: enabledBorder ?? this.enabledBorder,
      disabledBorder: disabledBorder ?? this.disabledBorder,
      focusedBorder: focusedBorder ?? this.focusedBorder,
      errorBorder: errorBorder ?? this.errorBorder,
      focusedErrorBorder: focusedErrorBorder ?? this.focusedErrorBorder,
    );
  }
}

class InputDecorationTheme extends InheritedWidget {
  const InputDecorationTheme({
    super.key,
    required this.data,
    required super.child,
  });

  final InputDecorationThemeData data;

  static InputDecorationThemeData of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<InputDecorationTheme>()
          ?.data ??
      const InputDecorationThemeData();

  @override
  bool updateShouldNotify(InputDecorationTheme oldWidget) =>
      oldWidget.data != data;
}

/// Lays a field out inside its fill, border, icons and error and counter lines.
class InputDecorator extends StatelessWidget {
  const InputDecorator({
    super.key,
    required this.decoration,
    this.baseStyle,
    this.textAlign,
    this.textAlignVertical,
    this.isFocused = false,
    this.isHovering = false,
    this.expands = false,
    this.isEmpty = false,
    this.child,
  });

  final InputDecoration decoration;
  final TextStyle? baseStyle;
  final TextAlign? textAlign;
  final TextAlignVertical? textAlignVertical;
  final bool isFocused;
  final bool isHovering;
  final bool expands;
  final bool isEmpty;
  final Widget? child;

  bool get _hasError =>
      decoration.errorText != null || decoration.error != null;

  InputBorder _border(BuildContext context, InputDecoration decoration) {
    final specific = !decoration.enabled
        ? (_hasError ? decoration.errorBorder : decoration.disabledBorder)
        : isFocused
        ? (_hasError ? decoration.focusedErrorBorder : decoration.focusedBorder)
        : (_hasError ? decoration.errorBorder : decoration.enabledBorder);
    if (specific != null) {
      return specific;
    }
    final border = decoration.border ?? AppShape.input;
    if (border.borderSide == BorderSide.none) {
      return border;
    }
    final colorScheme = context.colorScheme;
    final focused = isFocused && decoration.enabled;
    final color = !decoration.enabled
        ? colorScheme.onSurface.withValues(
            alpha: decoration.filled == true ? 0.38 : 0.12,
          )
        : _hasError
        ? (isHovering && !focused
              ? colorScheme.onErrorContainer
              : colorScheme.error)
        : focused
        ? colorScheme.primary
        : isHovering
        ? colorScheme.onSurface
        : decoration.filled == true
        ? colorScheme.onSurfaceVariant
        : colorScheme.outline;
    return border.copyWith(
      borderSide: BorderSide(color: color, width: focused ? 2 : 1),
    );
  }

  Color _iconColor(BuildContext context, InputDecoration decoration) {
    final colorScheme = context.colorScheme;
    return !decoration.enabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : colorScheme.onSurfaceVariant;
  }

  Widget _icon(
    BuildContext context,
    InputDecoration decoration,
    Widget icon,
    BoxConstraints? constraints,
    Color color,
  ) {
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: MouseRegion(
        cursor: SystemMouseCursors.basic,
        child: ConstrainedBox(
          constraints:
              constraints ??
              Theme.of(context).visualDensity.effectiveConstraints(
                const BoxConstraints(
                  minWidth: _minFieldHeight,
                  minHeight: _minFieldHeight,
                ),
              ),
          child: IconTheme.merge(
            data: IconThemeData(color: color, size: 24),
            child: Semantics(child: icon),
          ),
        ),
      ),
    );
  }

  Widget? _affix(Widget? widget, String? text, TextStyle style) {
    final content = widget ?? (text == null ? null : Text(text, style: style));
    if (content == null) {
      return null;
    }
    return AnimatedOpacity(
      opacity: isEmpty ? 0 : 1,
      duration: _borderDuration,
      curve: Curves.fastOutSlowIn,
      child: DefaultTextStyle.merge(style: style, child: content),
    );
  }

  @override
  Widget build(BuildContext context) {
    final decoration = this.decoration.applyDefaults(
      InputDecorationTheme.of(context),
    );
    final colorScheme = context.colorScheme;
    final direction = Directionality.of(context);
    final collapsed = decoration.isCollapsed == true;
    final filled = decoration.filled == true;
    final border = _border(context, decoration);
    final hasGap = !collapsed && (border.isOutline || filled);
    final inputGap = hasGap ? _inputGap : 0.0;
    final padding =
        (decoration.contentPadding ??
                _defaultPadding(
                  collapsed: collapsed,
                  outline: border.isOutline,
                  filled: filled,
                  dense: decoration.isDense == true,
                ))
            .resolve(direction);
    final density = collapsed
        ? 0.0
        : Theme.of(context).visualDensity.baseSizeAdjustment.dy;
    final align =
        textAlignVertical ??
        (border.isOutline ? TextAlignVertical.center : TextAlignVertical.top);
    final vertical = padding.top + padding.bottom + density;
    final top = align.y == 0 ? vertical / 2 : padding.top + density / 2;
    final bottom = align.y == 0 ? vertical / 2 : padding.bottom + density / 2;

    final input = _input(context, decoration);
    final prefixIcon = decoration.prefixIcon;
    final suffixIcon = decoration.suffixIcon;
    final iconColor = _iconColor(context, decoration);
    final field = _Container(
      border: border,
      fill: filled
          ? decoration.fillColor ?? colorScheme.surfaceContainerHighest
          : null,
      hover: filled && isHovering && decoration.enabled
          ? decoration.hoverColor ??
                colorScheme.onSurface.withValues(alpha: 0.08)
          : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: collapsed || decoration.isDense == true || expands
              ? 0
              : _minFieldHeight,
        ),
        child: Row(
          crossAxisAlignment: expands
              ? CrossAxisAlignment.stretch
              : CrossAxisAlignment.center,
          children: [
            if (prefixIcon != null)
              _icon(
                context,
                decoration,
                prefixIcon,
                decoration.prefixIconConstraints,
                iconColor,
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start: prefixIcon != null
                      ? _iconToInputGap
                      : (direction == TextDirection.ltr
                                ? padding.left
                                : padding.right) +
                            inputGap,
                  end: suffixIcon != null
                      ? _iconToInputGap
                      : (direction == TextDirection.ltr
                                ? padding.right
                                : padding.left) +
                            inputGap,
                  top: top < 0 ? 0 : top,
                  bottom: bottom < 0 ? 0 : bottom,
                ),
                child: input,
              ),
            ),
            if (suffixIcon != null)
              _icon(
                context,
                decoration,
                suffixIcon,
                decoration.suffixIconConstraints,
                _hasError && decoration.enabled ? colorScheme.error : iconColor,
              ),
          ],
        ),
      ),
    );

    final subtext = _subtext(context, decoration, padding, inputGap, direction);
    final constraints = decoration.constraints;
    final body = subtext == null
        ? field
        : Column(
            mainAxisSize: expands ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (expands) Expanded(child: field) else Flexible(child: field),
              subtext,
            ],
          );
    return constraints == null
        ? body
        : ConstrainedBox(constraints: constraints, child: body);
  }

  Widget _input(BuildContext context, InputDecoration decoration) {
    final colorScheme = context.colorScheme;
    final style = AppTextStyle.body.of(context).merge(baseStyle);
    final variant = style.copyWith(
      color: decoration.enabled
          ? colorScheme.onSurfaceVariant
          : colorScheme.onSurface.withValues(alpha: 0.38),
    );
    final hintWidget =
        decoration.hint ??
        (decoration.hintText == null
            ? null
            : Text(
                decoration.hintText!,
                style: variant.merge(decoration.hintStyle),
                textAlign: textAlign,
                maxLines: decoration.hintMaxLines,
                overflow: TextOverflow.ellipsis,
              ));
    final prefix = _affix(
      decoration.prefix,
      decoration.prefixText,
      variant.merge(decoration.prefixStyle),
    );
    final suffix = _affix(
      decoration.suffix,
      decoration.suffixText,
      variant.merge(decoration.suffixStyle),
    );
    final content = hintWidget == null
        ? child ?? const SizedBox.shrink()
        : Stack(
            fit: StackFit.passthrough,
            children: [
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: isEmpty ? 1 : 0,
                  duration: _hintFade,
                  child: hintWidget,
                ),
              ),
              ?child,
            ],
          );
    if (prefix == null && suffix == null) {
      return content;
    }
    return Row(
      crossAxisAlignment: expands
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        ?prefix,
        Expanded(child: content),
        ?suffix,
      ],
    );
  }

  Widget? _subtext(
    BuildContext context,
    InputDecoration decoration,
    EdgeInsets padding,
    double inputGap,
    TextDirection direction,
  ) {
    final colorScheme = context.colorScheme;
    final small = AppTextStyle.footnote.of(context);
    final variant = small.copyWith(
      color: decoration.enabled
          ? colorScheme.onSurfaceVariant
          : colorScheme.onSurface.withValues(alpha: 0.38),
    );
    final errorStyle = small
        .copyWith(color: colorScheme.error)
        .merge(decoration.errorStyle);
    final helper = decoration.error != null
        ? DefaultTextStyle.merge(style: errorStyle, child: decoration.error!)
        : decoration.errorText != null
        ? _FadeIn(
            child: Text(
              decoration.errorText!,
              style: errorStyle,
              textAlign: textAlign,
              overflow: TextOverflow.ellipsis,
              maxLines: decoration.errorMaxLines,
            ),
          )
        : decoration.helperText != null
        ? Text(
            decoration.helperText!,
            style: variant,
            textAlign: textAlign,
            overflow: TextOverflow.ellipsis,
          )
        : null;
    final counter =
        decoration.counter ??
        (decoration.counterText == null || decoration.counterText!.isEmpty
            ? null
            : Text(
                decoration.counterText!,
                style: variant.merge(decoration.counterStyle),
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
              ));
    if (helper == null && counter == null) {
      return null;
    }
    final (start, end) = direction == TextDirection.ltr
        ? (padding.left, padding.right)
        : (padding.right, padding.left);
    return Padding(
      padding: EdgeInsetsDirectional.only(
        top: _subtextGap,
        start: start + inputGap,
        end: end + inputGap,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: helper ?? const SizedBox.shrink()),
          if (counter != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 16),
              child: counter,
            ),
        ],
      ),
    );
  }

  static EdgeInsetsGeometry _defaultPadding({
    required bool collapsed,
    required bool outline,
    required bool filled,
    required bool dense,
  }) {
    if (collapsed) {
      return EdgeInsetsDirectional.zero;
    }
    if (outline) {
      return EdgeInsetsDirectional.fromSTEB(
        12,
        dense ? 16 : 20,
        12,
        dense ? 8 : 12,
      );
    }
    final vertical = dense ? 4.0 : 8.0;
    return EdgeInsetsDirectional.symmetric(
      horizontal: filled ? 12 : 0,
      vertical: vertical,
    );
  }
}

class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: context.motionDuration(_borderDuration),
      curve: Curves.fastOutSlowIn,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: FractionalTranslation(
          translation: Offset(0, -0.25 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _BorderTween extends Tween<ShapeBorder?> {
  _BorderTween({super.end});

  @override
  ShapeBorder? lerp(double t) => ShapeBorder.lerp(begin, end, t);
}

class _Container extends StatelessWidget {
  const _Container({
    required this.border,
    required this.fill,
    required this.hover,
    required this.child,
  });

  final InputBorder border;
  final Color? fill;
  final Color? hover;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<ShapeBorder?>(
      tween: _BorderTween(end: border),
      duration: context.motionDuration(_borderDuration),
      curve: Curves.fastOutSlowIn,
      builder: (context, value, child) => CustomPaint(
        painter: _ContainerPainter(
          border: value ?? border,
          fill: fill,
          hover: hover,
          textDirection: Directionality.of(context),
        ),
        child: child,
      ),
      child: child,
    );
  }
}

class _ContainerPainter extends CustomPainter {
  const _ContainerPainter({
    required this.border,
    required this.fill,
    required this.hover,
    required this.textDirection,
  });

  final ShapeBorder border;
  final Color? fill;
  final Color? hover;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final fill = this.fill;
    if (fill != null) {
      final color = hover == null ? fill : Color.alphaBlend(hover!, fill);
      border.paintInterior(
        canvas,
        rect,
        Paint()..color = color,
        textDirection: textDirection,
      );
    }
    border.paint(canvas, rect, textDirection: textDirection);
  }

  @override
  bool shouldRepaint(_ContainerPainter oldDelegate) =>
      oldDelegate.border != border ||
      oldDelegate.fill != fill ||
      oldDelegate.hover != hover ||
      oldDelegate.textDirection != textDirection;
}

class _SelectionGestures extends TextSelectionGestureDetectorBuilder {
  _SelectionGestures(this._state) : super(delegate: _state);

  final _TextFieldState _state;

  @override
  bool get onUserTapAlwaysCalled => _state.widget.onTapAlwaysCalled;

  @override
  void onUserTap() => _state.widget.onTap?.call();

  // The press would keep moving the field and its glass under the loupe.
  @override
  void onSingleLongTapStart(LongPressStartDetails details) {
    super.onSingleLongTapStart(details);
    ElasticPress.maybeOf(_state.context)?.release();
  }
}

class TextField extends StatefulWidget {
  const TextField({
    super.key,
    this.controller,
    this.focusNode,
    this.undoController,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.style,
    this.strutStyle,
    this.textAlign = TextAlign.start,
    this.textAlignVertical,
    this.textDirection,
    this.readOnly = false,
    this.showCursor,
    this.autofocus = false,
    this.obscuringCharacter = '•',
    this.obscureText = false,
    this.autocorrect = true,
    this.smartDashesType,
    this.smartQuotesType,
    this.enableSuggestions = true,
    this.maxLines = 1,
    this.minLines,
    this.expands = false,
    this.maxLength,
    this.maxLengthEnforcement,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.inputFormatters,
    this.enabled,
    this.cursorWidth = 2,
    this.cursorHeight,
    this.cursorRadius,
    this.cursorColor,
    this.keyboardAppearance,
    this.scrollPadding = const EdgeInsets.all(20),
    this.dragStartBehavior = DragStartBehavior.start,
    this.enableInteractiveSelection = true,
    this.onTap,
    this.onTapAlwaysCalled = false,
    this.onTapOutside,
    this.mouseCursor,
    this.buildCounter,
    this.scrollController,
    this.scrollPhysics,
    this.autofillHints = const <String>[],
    this.clipBehavior = Clip.hardEdge,
    this.contextMenuBuilder = TextSelectionMenu.editableText,
    this.canRequestFocus = true,
    this.enableIMEPersonalizedLearning = true,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final UndoHistoryController? undoController;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign textAlign;
  final TextAlignVertical? textAlignVertical;
  final TextDirection? textDirection;
  final bool readOnly;
  final bool? showCursor;
  final bool autofocus;
  final String obscuringCharacter;
  final bool obscureText;
  final bool autocorrect;
  final SmartDashesType? smartDashesType;
  final SmartQuotesType? smartQuotesType;
  final bool enableSuggestions;
  final int? maxLines;
  final int? minLines;
  final bool expands;
  final int? maxLength;
  final MaxLengthEnforcement? maxLengthEnforcement;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final bool? enabled;
  final double cursorWidth;
  final double? cursorHeight;
  final Radius? cursorRadius;
  final Color? cursorColor;
  final Brightness? keyboardAppearance;
  final EdgeInsets scrollPadding;
  final DragStartBehavior dragStartBehavior;
  final bool enableInteractiveSelection;
  final GestureTapCallback? onTap;
  final bool onTapAlwaysCalled;
  final TapRegionCallback? onTapOutside;
  final MouseCursor? mouseCursor;
  final InputCounterWidgetBuilder? buildCounter;
  final ScrollController? scrollController;
  final ScrollPhysics? scrollPhysics;
  final Iterable<String>? autofillHints;
  final Clip clipBehavior;
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final bool canRequestFocus;
  final bool enableIMEPersonalizedLearning;

  @override
  State<TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<TextField>
    implements TextSelectionGestureDetectorBuilderDelegate, AutofillClient {
  TextEditingController? _controller;
  FocusNode? _focusNode;
  late final _gestures = _SelectionGestures(this);
  // EditableText drops its selection overlay, and the loupe in it, whenever this
  // changes identity. An empty native field shows a loupe on iOS, not on Android.
  late final _loupeConfiguration = TextMagnifierConfiguration(
    magnifierBuilder: (context, controller, info) =>
        defaultTargetPlatform == TargetPlatform.android &&
            _effectiveController.text.isEmpty
        ? null
        : textLoupeConfiguration.magnifierBuilder(context, controller, info),
  );
  bool _isHovering = false;
  bool _showSelectionHandles = false;

  TextEditingController get _effectiveController =>
      widget.controller ?? _controller!;

  FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? (_focusNode ??= FocusNode());

  @override
  late bool forcePressEnabled;

  @override
  final GlobalKey<EditableTextState> editableTextKey =
      GlobalKey<EditableTextState>();

  @override
  bool get selectionEnabled => widget.enableInteractiveSelection && _isEnabled;

  bool get _isEnabled => widget.enabled ?? widget.decoration?.enabled ?? true;

  int get _currentLength => _effectiveController.value.text.characters.length;

  bool get _hasIntrinsicError {
    final maxLength = widget.maxLength;
    return maxLength != null && maxLength > 0 && _currentLength > maxLength;
  }

  bool get _hasError =>
      widget.decoration?.errorText != null ||
      widget.decoration?.error != null ||
      _hasIntrinsicError;

  EditableTextState? get _editableText => editableTextKey.currentState;

  MaxLengthEnforcement get _effectiveMaxLengthEnforcement =>
      widget.maxLengthEnforcement ??
      LengthLimitingTextInputFormatter.getDefaultMaxLengthEnforcement(
        defaultTargetPlatform,
      );

  bool get _canRequestFocus =>
      switch (MediaQuery.maybeNavigationModeOf(context) ??
      NavigationMode.traditional) {
        NavigationMode.traditional => widget.canRequestFocus && _isEnabled,
        NavigationMode.directional => true,
      };

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _controller = TextEditingController();
    }
    _effectiveFocusNode.canRequestFocus = widget.canRequestFocus && _isEnabled;
    _effectiveFocusNode.addListener(_handleFocusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _effectiveFocusNode.canRequestFocus = _canRequestFocus;
  }

  @override
  void didUpdateWidget(TextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == null && oldWidget.controller != null) {
      _controller = TextEditingController.fromValue(
        oldWidget.controller!.value,
      );
    } else if (widget.controller != null && oldWidget.controller == null) {
      _controller?.dispose();
      _controller = null;
    }
    if (widget.focusNode != oldWidget.focusNode) {
      (oldWidget.focusNode ?? _focusNode)?.removeListener(_handleFocusChanged);
      (widget.focusNode ?? _focusNode)?.addListener(_handleFocusChanged);
    }
    _effectiveFocusNode.canRequestFocus = _canRequestFocus;
    if (_effectiveFocusNode.hasFocus &&
        widget.readOnly != oldWidget.readOnly &&
        _isEnabled &&
        _effectiveController.selection.isCollapsed) {
      _showSelectionHandles = !widget.readOnly;
    }
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChanged);
    _focusNode?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _handleFocusChanged() => setState(() {});

  bool _shouldShowSelectionHandles(SelectionChangedCause? cause) {
    if (!_gestures.shouldShowSelectionToolbar ||
        !_gestures.shouldShowSelectionHandles ||
        cause == SelectionChangedCause.keyboard ||
        (widget.readOnly && _effectiveController.selection.isCollapsed) ||
        !_isEnabled) {
      return false;
    }
    return cause == SelectionChangedCause.longPress ||
        cause == SelectionChangedCause.stylusHandwriting ||
        _effectiveController.text.isNotEmpty;
  }

  void _handleSelectionChanged(
    TextSelection selection,
    SelectionChangedCause? cause,
  ) {
    final show = _shouldShowSelectionHandles(cause);
    if (show != _showSelectionHandles) {
      setState(() => _showSelectionHandles = show);
    }
    if (cause == SelectionChangedCause.longPress) {
      _editableText?.bringIntoView(selection.extent);
    }
    if (cause == SelectionChangedCause.drag && isDesktopPlatform) {
      _editableText?.hideToolbar();
    }
  }

  void _handleSelectionHandleTapped() {
    if (_effectiveController.selection.isCollapsed) {
      _editableText!.toggleToolbar();
    }
  }

  void _handleHover(bool hovering) {
    if (hovering != _isHovering) {
      setState(() => _isHovering = hovering);
    }
  }

  @override
  String get autofillId => _editableText!.autofillId;

  @override
  void autofill(TextEditingValue newEditingValue) =>
      _editableText!.autofill(newEditingValue);

  @override
  TextInputConfiguration get textInputConfiguration {
    final autofillHints = widget.autofillHints?.toList(growable: false);
    return _editableText!.textInputConfiguration.copyWith(
      autofillConfiguration: autofillHints == null
          ? AutofillConfiguration.disabled
          : AutofillConfiguration(
              uniqueIdentifier: autofillId,
              autofillHints: autofillHints,
              currentEditingValue: _effectiveController.value,
              hintText: widget.decoration?.hintText,
            ),
    );
  }

  InputDecoration _effectiveDecoration() {
    final decoration = (widget.decoration ?? const InputDecoration()).copyWith(
      enabled: _isEnabled,
      hintMaxLines: widget.decoration?.hintMaxLines ?? widget.maxLines,
    );
    if (decoration.counter != null || decoration.counterText != null) {
      return decoration;
    }
    final currentLength = _currentLength;
    final builder = widget.buildCounter;
    if (builder != null) {
      final isFocused = _effectiveFocusNode.hasFocus;
      final built = builder(
        context,
        currentLength: currentLength,
        maxLength: widget.maxLength,
        isFocused: isFocused,
      );
      return built == null
          ? decoration
          : decoration.copyWith(
              counter: Semantics(
                container: true,
                liveRegion: isFocused,
                child: built,
              ),
            );
    }
    final maxLength = widget.maxLength;
    if (maxLength == null) {
      return decoration;
    }
    final counterText = maxLength > 0
        ? '$currentLength/$maxLength'
        : '$currentLength';
    if (_hasIntrinsicError) {
      return decoration.copyWith(
        errorText: decoration.errorText ?? '',
        counterStyle:
            decoration.errorStyle ??
            TextStyle(color: context.colorScheme.error),
        counterText: counterText,
      );
    }
    return decoration.copyWith(counterText: counterText);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final platform = defaultTargetPlatform;
    final apple =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    forcePressEnabled = platform == TargetPlatform.iOS;
    final selectionStyle = DefaultSelectionStyle.of(context);
    final style = AppTextStyle.body
        .of(context)
        .copyWith(
          color: _isEnabled
              ? colorScheme.onSurface
              : colorScheme.onSurface.withValues(alpha: 0.38),
        )
        .merge(widget.style);
    final controller = _effectiveController;
    final focusNode = _effectiveFocusNode;
    final selectionColor =
        selectionStyle.selectionColor ?? textSelectionColorOf(colorScheme);
    VoidCallback? gainAccessibilityFocus;
    VoidCallback? loseAccessibilityFocus;
    if (isDesktopPlatform) {
      gainAccessibilityFocus = () {
        if (!focusNode.hasFocus && focusNode.canRequestFocus) {
          focusNode.requestFocus();
        }
      };
      loseAccessibilityFocus = focusNode.unfocus;
    }

    Widget child = RepaintBoundary(
      child: EditableText(
        key: editableTextKey,
        readOnly: widget.readOnly || !_isEnabled,
        showCursor: widget.showCursor,
        showSelectionHandles: _showSelectionHandles,
        controller: controller,
        focusNode: focusNode,
        undoController: widget.undoController,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        textCapitalization: widget.textCapitalization,
        style: style,
        strutStyle: widget.strutStyle,
        textAlign: widget.textAlign,
        textDirection: widget.textDirection,
        autofocus: widget.autofocus,
        obscuringCharacter: widget.obscuringCharacter,
        obscureText: widget.obscureText,
        autocorrect: widget.autocorrect,
        smartDashesType: widget.smartDashesType,
        smartQuotesType: widget.smartQuotesType,
        enableSuggestions: widget.enableSuggestions,
        maxLines: widget.maxLines,
        minLines: widget.minLines,
        expands: widget.expands,
        selectionColor: focusNode.hasFocus ? selectionColor : null,
        selectionControls: widget.enableInteractiveSelection
            ? textSelectionControlsFor(platform)
            : null,
        onChanged: widget.onChanged,
        onSelectionChanged: _handleSelectionChanged,
        onEditingComplete: widget.onEditingComplete,
        onSubmitted: widget.onSubmitted,
        onSelectionHandleTapped: _handleSelectionHandleTapped,
        onTapOutside: widget.onTapOutside,
        inputFormatters: [
          ...?widget.inputFormatters,
          if (widget.maxLength != null)
            LengthLimitingTextInputFormatter(
              widget.maxLength,
              maxLengthEnforcement: _effectiveMaxLengthEnforcement,
            ),
        ],
        rendererIgnoresPointer: true,
        mouseCursor: MouseCursor.defer,
        cursorWidth: widget.cursorWidth,
        cursorHeight: widget.cursorHeight,
        cursorRadius: widget.cursorRadius,
        cursorColor: _hasError
            ? colorScheme.error
            : widget.cursorColor ??
                  selectionStyle.cursorColor ??
                  colorScheme.primary,
        cursorOpacityAnimates: !isDesktopPlatform,
        cursorOffset: apple
            ? Offset(
                _appleCursorOffset / MediaQuery.devicePixelRatioOf(context),
                0,
              )
            : null,
        paintCursorAboveText: apple,
        backgroundCursorColor: _backgroundCursorColor,
        scrollPadding: widget.scrollPadding,
        keyboardAppearance: widget.keyboardAppearance ?? colorScheme.brightness,
        enableInteractiveSelection: widget.enableInteractiveSelection,
        dragStartBehavior: widget.dragStartBehavior,
        scrollController: widget.scrollController,
        scrollPhysics: widget.scrollPhysics,
        autofillHints: widget.autofillHints,
        autofillClient: this,
        autocorrectionTextRectColor: platform == TargetPlatform.iOS
            ? selectionColor
            : null,
        clipBehavior: widget.clipBehavior,
        enableIMEPersonalizedLearning: widget.enableIMEPersonalizedLearning,
        contextMenuBuilder: widget.contextMenuBuilder,
        magnifierConfiguration: _loupeConfiguration,
        scrollBehavior: ScrollConfiguration.of(context).copyWith(
          scrollbars: widget.maxLines != 1,
          overscroll: false,
          dragDevices: _fieldDragDevices,
        ),
      ),
    );

    if (widget.decoration != null) {
      child = AnimatedBuilder(
        animation: Listenable.merge([focusNode, controller]),
        builder: (context, child) => InputDecorator(
          decoration: _effectiveDecoration(),
          baseStyle: widget.style,
          textAlign: widget.textAlign,
          textAlignVertical: widget.textAlignVertical,
          isHovering: _isHovering,
          isFocused: focusNode.hasFocus,
          isEmpty: controller.value.text.isEmpty,
          expands: widget.expands,
          child: child,
        ),
        child: child,
      );
    }

    final maxLength = widget.maxLength;
    final semanticsMaxLength =
        _effectiveMaxLengthEnforcement != MaxLengthEnforcement.none &&
            maxLength != null &&
            maxLength > 0
        ? maxLength
        : null;
    return MouseRegion(
      cursor:
          widget.mouseCursor ??
          (_isEnabled ? SystemMouseCursors.text : SystemMouseCursors.basic),
      onEnter: (_) => _handleHover(true),
      onExit: (_) => _handleHover(false),
      child: TextFieldTapRegion(
        child: IgnorePointer(
          ignoring: !_isEnabled,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, child) => Semantics(
              enabled: _isEnabled,
              maxValueLength: semanticsMaxLength,
              currentValueLength: _currentLength,
              onTap: widget.readOnly
                  ? null
                  : () {
                      if (!controller.selection.isValid) {
                        controller.selection = TextSelection.collapsed(
                          offset: controller.text.length,
                        );
                      }
                      _editableText?.requestKeyboard();
                    },
              onDidGainAccessibilityFocus: gainAccessibilityFocus,
              onDidLoseAccessibilityFocus: loseAccessibilityFocus,
              onFocus: _isEnabled
                  ? () {
                      if (focusNode.canRequestFocus && !focusNode.hasFocus) {
                        focusNode.requestFocus();
                      } else if (!widget.readOnly) {
                        _editableText?.requestKeyboard();
                      }
                    }
                  : null,
              child: child,
            ),
            child: _gestures.buildGestureDetector(
              behavior: HitTestBehavior.translucent,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

// PrismApp's scroll behavior drags with a mouse too, which here would take the
// drag from selecting text wider than the field.
const _fieldDragDevices = {
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.trackpad,
  PointerDeviceKind.unknown,
};
const _appleCursorOffset = -2;
const _backgroundCursorColor = Color(0x99999999);

class TextFormField extends FormField<String> {
  TextFormField({
    super.key,
    this.controller,
    String? initialValue,
    FocusNode? focusNode,
    InputDecoration? decoration = const InputDecoration(),
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputAction? textInputAction,
    TextStyle? style,
    StrutStyle? strutStyle,
    TextDirection? textDirection,
    TextAlign textAlign = TextAlign.start,
    TextAlignVertical? textAlignVertical,
    bool autofocus = false,
    bool readOnly = false,
    bool? showCursor,
    String obscuringCharacter = '•',
    bool obscureText = false,
    bool autocorrect = true,
    SmartDashesType? smartDashesType,
    SmartQuotesType? smartQuotesType,
    bool enableSuggestions = true,
    MaxLengthEnforcement? maxLengthEnforcement,
    int? maxLines = 1,
    int? minLines,
    bool expands = false,
    int? maxLength,
    this.onChanged,
    GestureTapCallback? onTap,
    bool onTapAlwaysCalled = false,
    TapRegionCallback? onTapOutside,
    VoidCallback? onEditingComplete,
    ValueChanged<String>? onFieldSubmitted,
    super.onSaved,
    super.validator,
    super.errorBuilder,
    List<TextInputFormatter>? inputFormatters,
    bool? enabled,
    double cursorWidth = 2,
    double? cursorHeight,
    Radius? cursorRadius,
    Color? cursorColor,
    Brightness? keyboardAppearance,
    EdgeInsets scrollPadding = const EdgeInsets.all(20),
    bool? enableInteractiveSelection,
    InputCounterWidgetBuilder? buildCounter,
    ScrollPhysics? scrollPhysics,
    Iterable<String>? autofillHints,
    AutovalidateMode? autovalidateMode,
    ScrollController? scrollController,
    MouseCursor? mouseCursor,
    EditableTextContextMenuBuilder? contextMenuBuilder =
        TextSelectionMenu.editableText,
    bool enableIMEPersonalizedLearning = true,
    bool canRequestFocus = true,
  }) : super(
         initialValue: controller != null
             ? controller.text
             : (initialValue ?? ''),
         enabled: enabled ?? decoration?.enabled ?? true,
         autovalidateMode: autovalidateMode ?? AutovalidateMode.disabled,
         builder: (field) {
           final state = field as _TextFormFieldState;
           var effective = decoration ?? const InputDecoration();
           final errorText = field.errorText;
           if (errorText != null) {
             final errorBuilder = state.widget.errorBuilder;
             effective = errorBuilder != null
                 ? effective.copyWith(
                     error: errorBuilder(state.context, errorText),
                   )
                 : effective.copyWith(errorText: errorText);
           }
           return TextField(
             controller: state._effectiveController,
             focusNode: focusNode,
             decoration: effective,
             keyboardType: keyboardType,
             textInputAction: textInputAction,
             style: style,
             strutStyle: strutStyle,
             textAlign: textAlign,
             textAlignVertical: textAlignVertical,
             textDirection: textDirection,
             textCapitalization: textCapitalization,
             autofocus: autofocus,
             readOnly: readOnly,
             showCursor: showCursor,
             obscuringCharacter: obscuringCharacter,
             obscureText: obscureText,
             autocorrect: autocorrect,
             smartDashesType:
                 smartDashesType ??
                 (obscureText
                     ? SmartDashesType.disabled
                     : SmartDashesType.enabled),
             smartQuotesType:
                 smartQuotesType ??
                 (obscureText
                     ? SmartQuotesType.disabled
                     : SmartQuotesType.enabled),
             enableSuggestions: enableSuggestions,
             maxLengthEnforcement: maxLengthEnforcement,
             maxLines: maxLines,
             minLines: minLines,
             expands: expands,
             maxLength: maxLength,
             onChanged: (value) {
               field.didChange(value);
               onChanged?.call(value);
             },
             onTap: onTap,
             onTapAlwaysCalled: onTapAlwaysCalled,
             onTapOutside: onTapOutside,
             onEditingComplete: onEditingComplete,
             onSubmitted: onFieldSubmitted,
             inputFormatters: inputFormatters,
             enabled: enabled ?? decoration?.enabled ?? true,
             cursorWidth: cursorWidth,
             cursorHeight: cursorHeight,
             cursorRadius: cursorRadius,
             cursorColor: cursorColor,
             scrollPadding: scrollPadding,
             scrollPhysics: scrollPhysics,
             keyboardAppearance: keyboardAppearance,
             enableInteractiveSelection:
                 enableInteractiveSelection ?? (!obscureText || !readOnly),
             buildCounter: buildCounter,
             autofillHints: autofillHints,
             scrollController: scrollController,
             enableIMEPersonalizedLearning: enableIMEPersonalizedLearning,
             mouseCursor: mouseCursor,
             contextMenuBuilder: contextMenuBuilder,
             canRequestFocus: canRequestFocus,
           );
         },
       );

  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  FormFieldState<String> createState() => _TextFormFieldState();
}

class _TextFormFieldState extends FormFieldState<String> {
  TextEditingController? _controller;
  late final String? _initialValue;

  TextFormField get _textFormField => super.widget as TextFormField;

  TextEditingController get _effectiveController =>
      _textFormField.controller ?? _controller!;

  @override
  void initState() {
    super.initState();
    final controller = _textFormField.controller;
    if (controller == null) {
      _controller = TextEditingController(text: widget.initialValue);
    } else {
      controller.addListener(_handleControllerChanged);
    }
    _initialValue = widget.initialValue ?? controller?.text;
  }

  @override
  void didUpdateWidget(TextFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _textFormField.controller;
    if (controller == oldWidget.controller) {
      return;
    }
    oldWidget.controller?.removeListener(_handleControllerChanged);
    controller?.addListener(_handleControllerChanged);
    if (oldWidget.controller != null && controller == null) {
      _controller = TextEditingController.fromValue(
        oldWidget.controller!.value,
      );
    }
    if (controller != null) {
      setValue(controller.text);
      if (oldWidget.controller == null) {
        _controller?.dispose();
        _controller = null;
      }
    }
  }

  @override
  void dispose() {
    _textFormField.controller?.removeListener(_handleControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChange(String? value) {
    super.didChange(value);
    if (_effectiveController.text != value) {
      _effectiveController.value = TextEditingValue(text: value ?? '');
    }
  }

  @override
  void reset() {
    // The value goes first so _handleControllerChanged has nothing to report.
    _effectiveController.value = TextEditingValue(text: _initialValue ?? '');
    super.reset();
    _textFormField.onChanged?.call(_effectiveController.text);
  }

  void _handleControllerChanged() {
    if (_effectiveController.text != value) {
      didChange(_effectiveController.text);
    }
  }
}
