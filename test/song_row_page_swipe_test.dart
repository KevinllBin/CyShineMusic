import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cy_shine_music/features/downloads/download_history_entry.dart';
import 'package:cy_shine_music/features/songs/widgets/song_row.dart';

void main() {
  testWidgets('song row slide actions open and close', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SongRow(
              entry: _entry(),
              artworkVersion: null,
              playing: false,
              batchMode: false,
              selected: false,
              onToggleSelected: () {},
              onAddNext: () {},
              onAddToPlaylist: () {},
              onPlay: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );

    final row = find.byKey(const ValueKey('song-slide-song-swipe-test'));
    await tester.drag(row, const Offset(-180, 0));
    await tester.pumpAndSettle();

    expect(find.text('歌单'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    await tester.drag(row, const Offset(180, 0));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

DownloadHistoryEntry _entry() {
  return DownloadHistoryEntry(
    id: 'song-swipe-test',
    musicId: 'song-swipe-test',
    name: '手势测试歌曲',
    singer: '测试歌手',
    albumName: '测试专辑',
    sourceCode: 'wy',
    qualityCode: 'flac',
    status: DownloadHistoryStatus.completed,
    createdAt: DateTime.utc(2026, 8, 5),
  );
}
