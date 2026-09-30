import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cy_shine_music/core/storage/settings_store.dart';
import 'package:cy_shine_music/features/player/player_audio_handler.dart';
import 'package:cy_shine_music/features/player/player_controller.dart';
import 'package:cy_shine_music/features/player/widgets/player_control_color.dart';
import 'package:cy_shine_music/features/player/widgets/player_palette.dart';
import 'package:cy_shine_music/features/player/widgets/player_slider_thumb_shape.dart';
import 'package:cy_shine_music/features/player/widgets/transport_bar.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('滑块始终预留相同布局尺寸', () {
    const shape = PlayerSliderThumbShape(disableAnimations: false);
    for (final enabled in [true, false]) {
      for (final discrete in [true, false]) {
        expect(
          shape.getPreferredSize(enabled, discrete),
          const Size.square(14),
        );
      }
    }
  });

  testWidgets('拖动时平滑放大，松手后不等待 seek 即可缩回', (tester) async {
    final controller = await _pumpTransport(tester);
    final sliderFinder = find.byType(Slider);
    final originalSize = tester.getSize(sliderFinder);
    expect(
      tester.renderObject(sliderFinder),
      _paintsThumbRadius((radius) => radius == 2.5),
    );

    final gesture = await tester.startGesture(tester.getCenter(sliderFinder));
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester.renderObject(sliderFinder),
      _paintsThumbRadius((radius) => radius > 2.5 && radius < 7),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      tester.renderObject(sliderFinder),
      _paintsThumbRadius((radius) => radius == 7),
    );
    expect(tester.getSize(sliderFinder), originalSize);
    expect(controller.requests, isEmpty);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.requests, hasLength(1));
    expect(controller.requests.single.completion.isCompleted, isFalse);
    expect(
      _slider(tester).value,
      closeTo(controller.requests.single.position.inMilliseconds, 1),
    );
    expect(
      tester.renderObject(sliderFinder),
      _paintsThumbRadius((radius) => radius == 2.5),
    );
    expect(tester.getSize(sliderFinder), originalSize);

    controller.completeSeek(0);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('减少动画时按压与松手立即切换滑块大小', (tester) async {
    final controller = await _pumpTransport(tester, disableAnimations: true);
    final sliderFinder = find.byType(Slider);
    final gesture = await tester.startGesture(tester.getCenter(sliderFinder));
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    expect(
      tester.renderObject(sliderFinder),
      _paintsThumbRadius((radius) => radius == 7),
    );

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 1));
    expect(
      tester.renderObject(sliderFinder),
      _paintsThumbRadius((radius) => radius == 2.5),
    );
    controller.completeSeek(0);
    await tester.pumpAndSettle();
  });

  testWidgets('旧 seek 完成不会清掉后一次拖动的目标进度', (tester) async {
    final controller = await _pumpTransport(tester);
    _startDrag(tester, 45000);
    final firstSeek = _releaseDrag(tester, 45000);
    await tester.pump();

    _startDrag(tester, 90000);
    await tester.pump();
    controller.completeSeek(0);
    await firstSeek;
    await tester.pump();
    expect(_slider(tester).value, 90000);
    expect(controller.requests, hasLength(1));

    final secondSeek = _releaseDrag(tester, 90000);
    controller.completeSeek(1);
    await secondSeek;
    await tester.pump();
    expect(_slider(tester).value, 90000);
  });

  testWidgets('seek 失败后清理目标进度，后续拖动仍可正常使用', (tester) async {
    final controller = await _pumpTransport(tester);
    _startDrag(tester, 45000);
    final seek = _releaseDrag(tester, 45000);
    await tester.pump();
    expect(_slider(tester).value, 45000);

    final assertion = expectLater(seek, throwsStateError);
    controller.requests.single.completion.completeError(StateError('seek 失败'));
    await assertion;
    await tester.pump();
    expect(_slider(tester).value, 20000);

    _startDrag(tester, 60000);
    final retry = _releaseDrag(tester, 60000);
    controller.completeSeek(1);
    await retry;
    await tester.pump();
    expect(_slider(tester).value, 60000);
  });

  testWidgets('换曲会清理旧交互，旧 seek 不影响新曲拖动', (tester) async {
    final controller = await _pumpTransport(tester);
    final originalKey = _slider(tester).key;
    _startDrag(tester, 45000);
    final seek = _releaseDrag(tester, 45000);
    await tester.pump();

    controller.seedTrack('second', position: const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(_slider(tester).value, 2000);
    expect(_slider(tester).key, isNot(originalKey));

    _startDrag(tester, 30000);
    await tester.pump();
    controller.completeSeek(0);
    await seek;
    await tester.pump();
    expect(_slider(tester).value, 30000);

    final newSeek = _releaseDrag(tester, 30000);
    controller.completeSeek(1);
    await newSeek;
    await tester.pump();
    expect(_slider(tester).value, 30000);
  });

  testWidgets('组件卸载后 seek 完成不会触发 setState', (tester) async {
    final controller = await _pumpTransport(tester);
    _startDrag(tester, 45000);
    final seek = _releaseDrag(tester, 45000);
    await tester.pumpWidget(const SizedBox());
    controller.completeSeek(0);
    await seek;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('保留拖动时间气泡与无障碍时间语义', (tester) async {
    await _pumpTransport(tester);
    _startDrag(tester, 65000);
    await tester.pump();
    final slider = _slider(tester);
    expect(slider.label, '01:05');
    expect(slider.semanticFormatterCallback!(65000), '01:05');
    expect(
      tester
          .widget<SliderTheme>(find.byType(SliderTheme))
          .data
          .showValueIndicator,
      ShowValueIndicator.onDrag,
    );
  });
}

PaintPattern _paintsThumbRadius(bool Function(double) matchesRadius) => paints
  ..something((method, args) {
    if (method != #drawCircle) return false;
    final color = (args[2] as Paint).color;
    return color.toARGB32() == kPlayerInk.toARGB32() &&
        matchesRadius(args[1] as double);
  });

Slider _slider(WidgetTester tester) =>
    tester.widget<Slider>(find.byType(Slider));

void _startDrag(WidgetTester tester, double target) {
  final slider = _slider(tester);
  slider.onChangeStart!(slider.value);
  slider.onChanged!(target);
}

Future<void> _releaseDrag(WidgetTester tester, double target) {
  // 保留异步回调返回值，以便测试能观察异常与 finally 清理。
  return Function.apply(_slider(tester).onChangeEnd!, [target]) as Future<void>;
}

Future<_TestPlayerController> _pumpTransport(
  WidgetTester tester, {
  bool disableAnimations = false,
}) async {
  final preferences = await SharedPreferences.getInstance();
  final audioHandler = PlayerAudioHandler();
  addTearDown(() => unawaited(audioHandler.disposeHandler()));
  late _TestPlayerController controller;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        playerAudioHandlerProvider.overrideWithValue(audioHandler),
        playerControllerProvider.overrideWith(
          (ref) => controller = _TestPlayerController(ref),
        ),
        playerArtworkProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: const Scaffold(
            body: Center(child: SizedBox(width: 360, child: TransportBar())),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  controller.seedTrack('first');
  await tester.pumpAndSettle();
  return controller;
}

class _TestPlayerController extends PlayerController {
  _TestPlayerController(super.ref);

  final requests =
      <({String? trackId, Duration position, Completer<void> completion})>[];

  void seedTrack(String id, {Duration position = const Duration(seconds: 20)}) {
    state = PlayerState(
      track: PlayerTrack(
        id: id,
        kind: PlayerTrackKind.localFile,
        title: '测试歌曲',
        artist: '测试歌手',
        album: '测试专辑',
        sourceLabel: '本地',
        qualityLabel: 'FLAC',
        localPath: '$id.flac',
      ),
      position: position,
      duration: const Duration(minutes: 3),
    );
  }

  @override
  Future<void> seek(Duration position) {
    final completion = Completer<void>();
    requests.add((
      trackId: state.track?.id,
      position: position,
      completion: completion,
    ));
    return completion.future;
  }

  void completeSeek(int index) {
    final request = requests[index];
    if (mounted && state.track?.id == request.trackId) {
      state = state.copyWith(position: request.position);
    }
    request.completion.complete();
  }
}
