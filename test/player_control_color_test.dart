import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cy_shine_music/features/player/widgets/player_control_color.dart';
import 'package:cy_shine_music/features/player/widgets/player_palette.dart';
import 'package:cy_shine_music/theme/app_motion.dart';

final _artworkProvider = StateProvider<ImageProvider<Object>?>((ref) => null);

void main() {
  testWidgets('新封面加载期间保留旧色，并直接过渡到新色', (tester) async {
    final harness = await _pumpColor(tester, disableAnimations: false);
    final first = _Artwork();
    harness.setArtwork(first);
    await tester.pump();
    first.complete(_pixels(Colors.red));
    await tester.pumpAndSettle();
    final oldColor = harness.color;
    expect(oldColor, isNot(harness.fallback));

    final next = _Artwork();
    harness.setArtwork(next);
    await tester.pumpAndSettle();
    expect(harness.color, oldColor);

    next.complete(_pixels(Colors.blue));
    await tester.pump();
    expect(harness.color, oldColor);
    await tester.pump(const Duration(milliseconds: 100));
    final middleColor = harness.color;
    expect(middleColor, isNot(oldColor));
    await tester.pump(AppMotion.long);
    expect(harness.color, isNot(middleColor));
    expect(harness.color, isNot(harness.fallback));
  });

  testWidgets('新封面加载失败或确认无封面时恢复默认色', (tester) async {
    final harness = await _pumpColor(tester);
    final first = _Artwork();
    harness.setArtwork(first);
    await tester.pump();
    first.complete(_pixels(Colors.red));
    await tester.pumpAndSettle();
    expect(harness.color, isNot(harness.fallback));

    final failed = _Artwork();
    harness.setArtwork(failed);
    await tester.pump();
    failed.fail();
    await tester.pumpAndSettle();
    expect(harness.color, harness.fallback);
    expect(tester.takeException(), isNull);

    final next = _Artwork();
    harness.setArtwork(next);
    await tester.pump();
    next.complete(_pixels(Colors.blue));
    await tester.pumpAndSettle();
    expect(harness.color, isNot(harness.fallback));

    harness.setArtwork(null);
    await tester.pumpAndSettle();
    expect(harness.color, harness.fallback);
  });

  testWidgets('快速换曲后，旧封面的延迟取色不能覆盖新颜色', (tester) async {
    final harness = await _pumpColor(tester);
    final latePixels = Completer<ByteData?>();
    final first = _Artwork();
    harness.setArtwork(first);
    await tester.pump();
    first.complete(latePixels.future);
    await tester.pump();

    final next = _Artwork();
    harness.setArtwork(next);
    await tester.pump();
    next.complete(_pixels(Colors.green));
    await tester.pumpAndSettle();
    final newColor = harness.color;
    expect(newColor, isNot(harness.fallback));

    latePixels.complete(await _pixels(Colors.red));
    await tester.pumpAndSettle();
    expect(harness.color, newColor);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('$brightness 下黑白及灰阶封面保持中性', (tester) async {
      final harness = await _pumpColor(tester, brightness: brightness);
      for (final color in [Colors.black, Colors.grey, Colors.white]) {
        final artwork = _Artwork();
        harness.setArtwork(artwork);
        await tester.pump();
        artwork.complete(_pixels(color));
        await tester.pumpAndSettle();
        expect(harness.color, harness.fallback);
      }
    });

    testWidgets('$brightness 下边界色在基础背景上保持对比度', (tester) async {
      final harness = await _pumpColor(tester, brightness: brightness);
      for (final color in [
        const Color(0xFFFFFF00),
        const Color(0xFF00FF00),
        const Color(0xFF0000FF),
        Colors.lime,
      ]) {
        final artwork = _Artwork();
        harness.setArtwork(artwork);
        await tester.pump();
        artwork.complete(_pixels(color));
        await tester.pumpAndSettle();
        expect(harness.color, isNot(harness.fallback));
        expect(
          HSLColor.fromColor(harness.color).lightness,
          closeTo(brightness == Brightness.dark ? 0.82 : 0.23, 0.01),
        );
        // 这里只验证基础背景，流动背景的局部亮度仍需真机验收。
        final inkLuminance = harness.color.computeLuminance();
        final surfaceLuminance = harness.surface.computeLuminance();
        final ratio = inkLuminance > surfaceLuminance
            ? (inkLuminance + 0.05) / (surfaceLuminance + 0.05)
            : (surfaceLuminance + 0.05) / (inkLuminance + 0.05);
        expect(ratio, greaterThanOrEqualTo(4.5));
      }
    });
  }

  testWidgets('减少动画时，新颜色就绪后立即应用', (tester) async {
    final harness = await _pumpColor(tester);
    final artwork = _Artwork();
    harness.setArtwork(artwork);
    await tester.pump();
    artwork.complete(_pixels(Colors.red));
    await tester.pump();
    await tester.pump();
    expect(harness.color, isNot(harness.fallback));
    final color = harness.color;
    await tester.pump(AppMotion.long);
    expect(harness.color, color);
  });
}

Future<_ColorHarness> _pumpColor(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  bool disableAnimations = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      playerArtworkProvider.overrideWith((ref) => ref.watch(_artworkProvider)),
    ],
  );
  addTearDown(container.dispose);
  final harness = _ColorHarness(container);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: brightness,
          ),
        ),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: PlayerControlColor(
            builder: (context, color) {
              harness.color = color;
              harness.fallback = playerInk(context);
              harness.surface = playerSurface(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

class _ColorHarness {
  _ColorHarness(this.container);

  final ProviderContainer container;
  late Color color;
  late Color fallback;
  late Color surface;

  void setArtwork(ImageProvider<Object>? artwork) {
    container.read(_artworkProvider.notifier).state = artwork;
  }
}

class _Artwork extends ImageProvider<_Artwork> {
  _Artwork() {
    final handle = stream.keepAlive();
    addTearDown(handle.dispose);
  }

  final stream = _ArtworkStream();

  @override
  Future<_Artwork> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    _Artwork key,
    ImageErrorListener handleError,
  ) {
    stream.setCompleter(this.stream);
  }

  void complete(Future<ByteData?> pixels) => stream.complete(pixels);

  void fail() => stream.fail();
}

class _ArtworkStream extends ImageStreamCompleter {
  void complete(Future<ByteData?> pixels) {
    setImage(ImageInfo(image: _ArtworkImage(pixels)));
  }

  void fail() => reportError(exception: StateError('封面加载失败'));
}

// 仅提供取色所需像素，测试不访问网络或等待引擎解码。
class _ArtworkImage extends Fake implements ui.Image {
  _ArtworkImage(this.pixels);

  final Future<ByteData?> pixels;

  @override
  int get width => 4;

  @override
  int get height => 4;

  @override
  Future<ByteData?> toByteData({
    ui.ImageByteFormat format = ui.ImageByteFormat.rawRgba,
  }) => pixels;

  @override
  ui.Image clone() => _ArtworkImage(pixels);

  @override
  List<StackTrace>? debugGetOpenHandleStackTraces() => null;

  @override
  void dispose() {}
}

Future<ByteData?> _pixels(Color color) {
  final argb = color.toARGB32();
  final bytes = Uint8List.fromList([
    for (var i = 0; i < 16; i++) ...[
      (argb >> 16) & 0xff,
      (argb >> 8) & 0xff,
      argb & 0xff,
      (argb >> 24) & 0xff,
    ],
  ]);
  return Future.value(ByteData.sublistView(bytes));
}
