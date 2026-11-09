import 'package:flutter/widgets.dart';
import 'package:prism_ui/context.dart';

/// The hairline that separates what sits on one surface.
class Divider extends StatelessWidget {
  const Divider({super.key, this.height = 16, this.thickness = 0});

  final double height;
  final double thickness;

  static Color colorOf(BuildContext context) =>
      context.colorScheme.onSurface.withValues(alpha: 0.14);

  static BorderSide createBorderSide(BuildContext context) =>
      BorderSide(color: colorOf(context), width: 0);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: Container(
          height: thickness,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colorOf(context), width: thickness),
            ),
          ),
        ),
      ),
    );
  }
}
