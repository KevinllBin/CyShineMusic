import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cy_shine_music/features/shell/shell_route_utils.dart';
import 'package:cy_shine_music/features/shell/widgets/shell_header.dart';
import 'package:cy_shine_music/features/shell/widgets/toolbar_metrics.dart';

void main() {
  testWidgets('standard section headers have no visible back arrow', (
    tester,
  ) async {
    for (final entry in <String, String>{
      '/settings/sources': '音源管理',
      '/playlists': '歌单管理',
      '/downloads': '下载',
      '/songs/search': '搜索本地歌曲',
    }.entries) {
      await _pumpHeader(tester, entry.key);
      expect(find.text(entry.value), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
      expect(find.byTooltip('返回上一页'), findsNothing);
      expect(find.byTooltip('返回歌曲列表'), findsNothing);
    }
  });

  test('playlist detail routes own their immersive chrome', () {
    expect(isImmersivePlaylistDetailLocation('/playlists/example'), isTrue);
    expect(
      isImmersivePlaylistDetailLocation('/discover/playlists/kw/example'),
      isTrue,
    );
    expect(isImmersivePlaylistDetailLocation('/playlists/import'), isFalse);
    expect(isImmersivePlaylistDetailLocation('/songs'), isFalse);
  });

  testWidgets('playlist import retains its parent-navigation arrow', (
    tester,
  ) async {
    await _pumpHeader(tester, '/playlists/import');

    expect(find.text('导入歌单'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    expect(find.byTooltip('返回上一页'), findsOneWidget);
  });

  test('toolbar highlights logical parent sections for child routes', () {
    expect(toolbarIndexFor('/settings/sources'), 3);
    expect(toolbarIndexFor('/songs/search'), 1);
    expect(toolbarIndexFor('/playlists/example'), 1);
  });
}

Future<void> _pumpHeader(
  WidgetTester tester,
  String location, {
  List<Override> overrides = const [],
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Scaffold(
          body: ShellHeader(
            location: location,
            playlistBackLocation: '/playlists',
          ),
        ),
      ),
    ),
  );
}
