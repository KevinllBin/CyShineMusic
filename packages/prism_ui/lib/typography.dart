import 'package:flutter/widgets.dart';
import 'package:prism_ui/theme_data.dart';

/// Apple's iOS Dynamic Type scale at its default size, a dp per point, with
/// two steps it lacks: [display] for a dashboard figure, [pageTitle] for an app
/// bar.
enum AppTextStyle {
  display(40, 44, emphasizedWeight: FontWeight.w700),
  largeTitle(34, 41, emphasizedWeight: FontWeight.w700),
  title1(28, 34, emphasizedWeight: FontWeight.w700),
  pageTitle(24, 30, weight: FontWeight.w600, emphasizedWeight: FontWeight.w700),
  title2(22, 28, emphasizedWeight: FontWeight.w700),
  title3(20, 25),
  headline(17, 22, weight: FontWeight.w600),
  body(17, 22),
  callout(16, 21),
  subheadline(15, 20),
  footnote(13, 18),
  caption1(12, 16),
  caption2(11, 13);

  const AppTextStyle(
    this.size,
    this.leading, {
    this.weight = FontWeight.w400,
    this.emphasizedWeight = FontWeight.w600,
  });

  final double size;
  final double leading;
  final FontWeight weight;
  final FontWeight emphasizedWeight;

  TextStyle of(BuildContext context, {bool emphasized = false}) {
    final theme = Theme.of(context);
    return _apply(
      size < title3.size ? theme.bodyTextStyle : theme.displayTextStyle,
      emphasized: emphasized,
    );
  }

  /// For text sized to the shape it marks, such as a letter in an icon.
  static TextStyle custom(
    BuildContext context, {
    required double size,
    required double leading,
    FontWeight weight = FontWeight.w400,
  }) {
    final theme = Theme.of(context);
    final base = size < title3.size
        ? theme.bodyTextStyle
        : theme.displayTextStyle;
    return base.copyWith(
      fontSize: size,
      height: leading / size,
      fontWeight: weight,
      letterSpacing: 0,
    );
  }

  TextStyle _apply(TextStyle base, {required bool emphasized}) => base.copyWith(
    fontSize: size,
    height: leading / size,
    fontWeight: emphasized ? emphasizedWeight : weight,
    letterSpacing: 0,
  );
}
