import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/banner.dart';
import 'package:prism_ui/focus.dart';
import 'package:prism_ui/liquid_glass.dart';
import 'package:prism_ui/measure.dart';
import 'package:prism_ui/navigator.dart';
import 'package:prism_ui/scroll_behavior.dart';
import 'package:prism_ui/text.dart';
import 'package:prism_ui/text_selection_controls.dart';
import 'package:prism_ui/theme_cross_fade.dart';
import 'package:prism_ui/theme_data.dart';

const _unstyledText = TextStyle(
  color: Color(0xD0FF0000),
  fontFamily: 'monospace',
  fontSize: 48,
  fontWeight: FontWeight.w900,
  decoration: TextDecoration.underline,
  decorationColor: Color(0xFFFFFF00),
  decorationStyle: TextDecorationStyle.double,
  debugLabel: 'fallback style; consider putting your text in a surface',
);

/// A [WidgetsApp] under the theme [themeMode] picks, with the selection
/// colors, hero controller and app-wide layers the components expect.
class PrismApp extends StatefulWidget {
  const PrismApp({
    super.key,
    this.navigatorKey,
    this.home,
    this.onGenerateRoute,
    this.onNavigationNotification,
    this.builder,
    this.title = '',
    this.theme,
    this.darkTheme,
    this.themeMode = ThemeMode.system,
    this.locale,
    this.localizationsDelegates,
    this.supportedLocales = const [Locale('en', 'US')],
    this.textScale,
    this.minTextScale = 0,
    this.maxTextScale = double.infinity,
    this.liquidGlass,
    this.emojiFont,
    this.stackedBanners = false,
    this.bannerTopInset = 0,
    this.remoteFocus = false,
    this.floatingKeyboard,
    this.debugShowCheckedModeBanner = true,
  });

  final GlobalKey<NavigatorState>? navigatorKey;
  final Widget? home;
  final RouteFactory? onGenerateRoute;
  final NotificationListenerCallback<NavigationNotification>?
  onNavigationNotification;
  final TransitionBuilder? builder;
  final String title;
  final ThemeData? theme;
  final ThemeData? darkTheme;
  final ThemeMode themeMode;
  final Locale? locale;
  final Iterable<LocalizationsDelegate<dynamic>>? localizationsDelegates;
  final Iterable<Locale> supportedLocales;

  /// Null follows the system's; either way it stays within the bounds below.
  final double? textScale;
  final double minTextScale;
  final double maxTextScale;

  /// Null draws no glass.
  final LiquidGlassQuality? liquidGlass;
  final ({String family, Pattern pattern})? emojiFont;
  final bool stackedBanners;
  final double bannerTopInset;
  final bool remoteFocus;
  final ValueListenable<bool>? floatingKeyboard;
  final bool debugShowCheckedModeBanner;

  @override
  State<PrismApp> createState() => _PrismAppState();
}

class _PrismAppState extends State<PrismApp> {
  final _heroController = HeroController();

  @override
  void dispose() {
    _heroController.dispose();
    super.dispose();
  }

  ThemeData _themeOf(BuildContext context) {
    final dark = switch (widget.themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
    final theme =
        (dark ? widget.darkTheme : null) ?? widget.theme ?? Theme.of(context);
    SystemChrome.setSystemUIOverlayStyle(
      theme.brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    );
    return theme;
  }

  Widget _build(BuildContext context, Widget? child) {
    final theme = _themeOf(context);
    final builder = widget.builder;
    final navigator = RemoteFocusAdapter(
      enabled: widget.remoteFocus,
      floatingKeyboard: widget.floatingKeyboard,
      child: Overlay.wrap(child: child ?? const SizedBox.shrink()),
    );
    final glass = widget.liquidGlass;
    final emojiFont = widget.emojiFont;
    Widget app = BannerHost(
      stacked: widget.stackedBanners,
      topInset: widget.bannerTopInset,
      child: builder == null
          ? navigator
          : Builder(builder: (context) => builder(context, navigator)),
    );
    if (emojiFont != null) {
      app = EmojiFont(
        family: emojiFont.family,
        pattern: emojiFont.pattern,
        child: app,
      );
    }
    return Theme(
      data: theme,
      child: DefaultSelectionStyle(
        selectionColor: textSelectionColorOf(theme.colorScheme),
        cursorColor: theme.colorScheme.primary,
        child: ThemeCrossFade(
          child: _TextScale(
            scale: widget.textScale,
            min: widget.minTextScale,
            max: widget.maxTextScale,
            child: LiquidGlassScope(
              enabled: glass != null,
              quality: glass ?? LiquidGlassQuality.standard,
              child: LiquidGlassHost(enabled: glass != null, child: app),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const BaseScrollBehavior(),
      // No page flies a Hero, but with a controller the navigator lays a
      // pushed route's first frame out offstage, which the routes' settle
      // checks in navigator.dart and OpenContainer wait out.
      child: HeroControllerScope(
        controller: _heroController,
        child: WidgetsApp(
          navigatorKey: widget.navigatorKey,
          home: widget.home,
          onGenerateRoute: widget.onGenerateRoute,
          onNavigationNotification: widget.onNavigationNotification,
          pageRouteBuilder: <T>(settings, builder) =>
              CardPageRoute<T>(settings: settings, builder: builder),
          builder: _build,
          title: widget.title,
          textStyle: _unstyledText,
          color: widget.theme?.colorScheme.primary ?? const Color(0xFF2196F3),
          locale: widget.locale,
          localizationsDelegates: widget.localizationsDelegates,
          supportedLocales: widget.supportedLocales,
          debugShowCheckedModeBanner: widget.debugShowCheckedModeBanner,
        ),
      ),
    );
  }
}

class _TextScale extends StatelessWidget {
  const _TextScale({
    required this.scale,
    required this.min,
    required this.max,
    required this.child,
  });

  final double? scale;
  final double min;
  final double max;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The platform's factor rather than the scaler's, which Android makes
    // nonlinear; reading the scaler still rebuilds this when it changes.
    MediaQuery.textScalerOf(context);
    final factor =
        (scale ?? WidgetsBinding.instance.platformDispatcher.textScaleFactor)
            .clamp(min, max);
    return MeasureScope(
      measure: Measure.of(context, factor),
      child: _TextScaler(factor: factor, child: child),
    );
  }
}

class _TextScaler extends StatelessWidget {
  const _TextScaler({required this.factor, required this.child});

  final double factor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(factor)),
      child: child,
    );
  }
}
