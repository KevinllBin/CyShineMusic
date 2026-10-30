import 'package:flutter_test/flutter_test.dart';
import 'package:cy_shine_music/core/services/log_policy.dart';

void main() {
  test('compacts long and multi-line output and hides URL credentials', () {
    final result = compactLogMessage(
      'GET https://name:pass@audio.test/a?token=secret\npassword=hidden',
    );
    expect(result, isNot(contains('secret')));
    expect(result, isNot(contains('hidden')));
    expect(result, isNot(contains('name:pass')));
    expect(result, isNot(contains('\n')));
    expect(compactLogMessage('x' * 5000).length, lessThan(1250));
  });

  test('repeat summaries preserve omitted counts on flush', () {
    final policy = LogPolicy();
    final now = DateTime(2026, 10, 30);
    expect(policy.accept('player', 'same', now), ['same']);
    for (var i = 0; i < 25; i++) {
      expect(policy.accept('player', 'same', now), isEmpty);
    }
    expect(policy.drain()['player'], contains('repeated=25'));
    expect(policy.drain(), isEmpty);
    expect(policy.accept('player', 'new', now), ['new']);
  });

  test('script noise has a bounded budget while failures stay visible', () {
    final policy = LogPolicy();
    final now = DateTime(2026, 10, 30);
    var logged = 0;
    for (var i = 0; i < 30; i++) {
      logged += policy.accept('music-source', 'debug $i', now).length;
    }
    expect(logged, 5);
    expect(policy.accept('music-source', 'error source unavailable', now), [
      'error source unavailable',
    ]);
    expect(policy.drain()['music-source'], contains('script_lines_omitted=25'));
    expect(
      policy.accept(
        'music-source',
        'next',
        now.add(const Duration(seconds: 11)),
      ),
      ['next'],
    );
  });
}
