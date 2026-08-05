import 'package:flutter/material.dart';
import 'package:progress_indicator_m3e/progress_indicator_m3e.dart';

/// The app-wide indeterminate loading indicator used by the startup screen
/// and page-level loading states.
class AppCircularLoadingIndicator extends StatelessWidget {
  const AppCircularLoadingIndicator({super.key, this.dimension = 42});

  final double dimension;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);

    return TickerMode(
      enabled: !animationsDisabled,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: dimension,
          child: CircularProgressIndicatorM3E(
            shape: ProgressM3EShape.wavy,
            size: CircularProgressM3ESize.m,
            activeColor: scheme.primary,
            trackColor: scheme.surfaceContainerHighest,
          ),
        ),
      ),
    );
  }
}
