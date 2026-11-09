import 'package:bass_player/bass_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('test/bass-diagnostics/methods');
  const events = EventChannel('test/bass-diagnostics/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late BassPlayer player;
  late List<MethodCall> calls;

  Future<void> emit(Map<String, Object?> event) async {
    await messenger.handlePlatformMessage(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope(event),
      (_) {},
    );
  }

  Map<String, Object?> snapshot(String source, int sequence, int position) => {
    'event': 'snapshot',
    'sourceId': source,
    'snapshotSeq': sequence,
    'playing': false,
    'processingState': 'ready',
    'positionMs': position,
    'durationMs': 180000,
  };

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls = [];
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      return <String, Object?>{};
    });
    messenger.setMockMethodCallHandler(
      MethodChannel(events.name),
      (_) async => null,
    );
    player = BassPlayer(methodChannel: methods, eventChannel: events);
  });

  tearDown(() async {
    await player.dispose();
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(MethodChannel(events.name), null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('network state follows native events and snapshots', () async {
    await player.initialize();
    final flips = <bool>[];
    final subscription = player.networkUsableStream.listen(flips.add);
    addTearDown(subscription.cancel);
    expect(player.networkUsable, isTrue);
    expect(player.networkAvailable, isNull);

    await emit({...snapshot('load-1', 1, 0), 'networkAvailable': true});
    expect(player.networkAvailable, isTrue);
    expect(flips, isEmpty);

    await emit({'event': 'network', 'available': false});
    expect(player.networkAvailable, isFalse);
    expect(player.networkUsable, isFalse);
    expect(flips, [false]);

    await emit({'event': 'network', 'available': true});
    expect(flips, [false, true]);

    await emit({...snapshot('load-1', 2, 0), 'networkError': 'timeout'});
    expect(player.networkError, 'timeout');
    expect(player.networkUsable, isFalse);
    expect(flips, [false, true, false]);

    await emit(snapshot('load-1', 3, 0));
    expect(player.networkError, isNull);
    expect(player.networkAvailable, isTrue);
    expect(flips, [false, true, false, true]);
  });

  test(
    'saved recording choices reach native code before initialization',
    () async {
      await player.setDiagnosticRecording(
        playback: false,
        smartTransition: true,
      );
      expect(calls, isEmpty);
      await player.initialize();
      expect(calls.map((call) => call.method), [
        'setDiagnosticRecording',
        'initialize',
      ]);
      expect(calls.first.arguments, {
        'playback': false,
        'smartTransition': true,
      });

      await player.setDiagnosticRecording(
        playback: true,
        smartTransition: false,
      );
      expect(calls.last.method, 'setDiagnosticRecording');
      expect(calls.last.arguments, {
        'playback': true,
        'smartTransition': false,
      });
    },
  );

  test('GrooveShift controls use the renamed native channel methods', () async {
    await player.setGrooveShiftEnabled(true);
    await player.setGrooveShiftNext(
      id: 'next',
      uri: Uri.file('/music/next.flac'),
    );
    await player.confirmGrooveShift('next');
    await player.cancelGrooveShift();
    expect(calls.map((call) => call.method), [
      'setDiagnosticRecording',
      'initialize',
      'setGrooveShift',
      'setGrooveShiftNext',
      'confirmGrooveShift',
      'cancelGrooveShift',
    ]);
    expect(calls[2].arguments, {'enabled': true});
    expect(calls[3].arguments, {
      'id': 'next',
      'uri': 'file:///music/next.flac',
    });
    expect(calls[4].arguments, {'id': 'next'});
  });

  test(
    'diagnostic selection leaves playback and handoff events active',
    () async {
      final records = <Map<Object?, Object?>>[];
      final handoffs = <Map<Object?, Object?>>[];
      final diagnostics = player.diagnosticStream.listen(records.add);
      final transitions = player.grooveShiftStream.listen(handoffs.add);
      addTearDown(diagnostics.cancel);
      addTearDown(transitions.cancel);
      await player.initialize();
      expect(calls.first.arguments, {
        'playback': false,
        'smartTransition': false,
      });

      await emit(snapshot('load-1', 1, 1000));
      expect(records, isEmpty);
      expect(player.position, const Duration(seconds: 1));

      await player.setDiagnosticRecording(
        playback: false,
        smartTransition: true,
      );
      await emit({
        ...snapshot('local-2', 2, 3000),
        'event': 'groove-shift',
        'phase': 'handoff',
      });
      await emit({
        'event': 'diagnostic',
        'record': {'scope': 'player-trace', 'action': 'pause'},
      });
      await emit({
        'event': 'diagnostic',
        'record': {'scope': 'groove-shift-trace', 'action': 'clock'},
      });
      expect(handoffs.single['phase'], 'handoff');
      expect(records.map((record) => record['action']), [
        'dart_frame',
        'clock',
      ]);
      expect(
        records.every((record) => record['scope'] == 'groove-shift-trace'),
        isTrue,
      );

      records.clear();
      await player.setDiagnosticRecording(
        playback: true,
        smartTransition: false,
      );
      await emit(snapshot('load-3', 3, 5000));
      await emit({
        'event': 'diagnostic',
        'record': {'scope': 'player-trace', 'action': 'play'},
      });
      await emit({
        'event': 'diagnostic',
        'record': {'scope': 'groove-shift-trace', 'action': 'clock'},
      });
      expect(records.map((record) => record['action']), ['dart_frame', 'play']);
      expect(
        records.every((record) => record['scope'] == 'player-trace'),
        isTrue,
      );

      records.clear();
      await player.setDiagnosticRecording(
        playback: false,
        smartTransition: false,
      );
      await emit({
        ...snapshot('local-4', 4, 7000),
        'event': 'groove-shift',
        'phase': 'handoff',
      });
      expect(records, isEmpty);
      expect(handoffs, hasLength(2));
      expect(player.position, const Duration(seconds: 7));
    },
  );
}
