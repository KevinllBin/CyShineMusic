import 'dart:convert' show LineSplitter;

import '../../models/lyric_info.dart';

/// Qishui supplies plain KRC text; word offsets are relative to each line.
class QsLyric {
  const QsLyric._();

  static final _lineHead = RegExp(r'^\[(\d+),(\d+)\]');
  static final _wordTime = RegExp(r'<(\d+),(\d+)(?:,\d+)?>');
  static final _lrcHead = RegExp(
    r'^\[\d{1,3}(?::\d{1,3}){0,2}(?:\.\d{1,3})?\]',
  );

  static LyricInfo parse(Map data) {
    final main = _parseContent(data['content']);
    final translations = data['translations'];
    final translated = translations is Map
        ? _parseContent(translations['cn']).lyric
        : '';
    return LyricInfo(
      lyric: main.lyric,
      lxlyric: main.lxlyric,
      tlyric: translated.isEmpty ? null : translated,
    );
  }

  static LyricInfo _parseContent(Object? content) {
    if (content is! String || content.trim().isEmpty) {
      return const LyricInfo(lyric: '');
    }
    final plain = <String>[];
    final timed = <String>[];
    var hasWords = false;
    for (final raw in const LineSplitter().convert(content)) {
      final line = raw.trim();
      final head = _lineHead.firstMatch(line);
      if (head == null) {
        if (_lrcHead.hasMatch(line)) {
          plain.add(line);
          timed.add(line);
        }
        continue;
      }
      final startMs = int.parse(head.group(1)!);
      final body = line.substring(head.end);
      final text = body.replaceAll(_wordTime, '');
      if (text.trim().isEmpty) continue;
      final stamp = _timestamp(startMs);
      plain.add('$stamp$text');
      hasWords = hasWords || _wordTime.hasMatch(body);
      final words = body.replaceAllMapped(
        _wordTime,
        (match) => '<${match.group(1)},${match.group(2)}>',
      );
      timed.add('$stamp$words');
    }
    return LyricInfo(
      lyric: plain.join('\n'),
      lxlyric: hasWords ? timed.join('\n') : null,
    );
  }

  static String _timestamp(int ms) {
    final minutes = (ms ~/ 60000).toString().padLeft(2, '0');
    final seconds = (ms ~/ 1000 % 60).toString().padLeft(2, '0');
    final millis = (ms % 1000).toString().padLeft(3, '0');
    return '[$minutes:$seconds.$millis]';
  }
}
