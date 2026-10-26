import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cy_shine_music/core/models/enums.dart';
import 'package:cy_shine_music/core/models/music_info.dart';
import 'package:cy_shine_music/core/sdk/internal/builders.dart';
import 'package:cy_shine_music/core/sdk/internal/kg_quality.dart';
import 'package:cy_shine_music/core/sdk/playlist_adapters/kg_playlist_adapter.dart';

void main() {
  const baseHash = '8141FAA45AAD5BCFF5FF9873B89709E3';

  test('builds the verified Kugou Android signature over the exact body', () {
    final body = encodeKgPrivilegeRequestBody(const [
      KgPrivilegeResource(hash: baseHash, albumId: 0),
    ]);
    final signature = buildKgPrivilegeSignature(const {
      'appid': '1005',
      'clienttime': '1785420000',
      'clientver': '20489',
      'dfid': '-',
      'mid': '0123456789abcdef0123456789abcdef',
      'uuid': '-',
    }, body);

    expect(signature, '5fae9924263c6d6aa7fcc1a02f8d85d1');
  });

  test('parses Kugou batch details with a distinct hash for each quality', () {
    final details = parseKgPrivilegeQualityDetails(
      jsonEncode({
        'status': 1,
        'error_code': 0,
        'data': [
          {
            'hash': baseHash.toLowerCase(),
            'relate_goods': [
              _good('128', 3843167, baseHash),
              _good('320', 9607864, 'HASH_320'),
              _good('flac', 26174554, 'HASH_FLAC'),
              _good('high', 50331648, 'HASH_HIRES'),
              _good('viper_atmos', 56288830, 'HASH_ATMOS'),
              _good('viper_clear', 102927104, 'HASH_MASTER'),
              _good('super', 200000000, 'IGNORED'),
            ],
          },
        ],
      }),
    );
    final options = details[baseHash]!;
    final byType = {for (final option in options) option.type: option};

    expect(options.map((option) => option.type), [
      Quality.master,
      Quality.atmos,
      Quality.hires,
      Quality.flac,
      Quality.k320,
      Quality.k128,
    ]);
    expect(byType[Quality.master]?.size, '98.16M');
    expect(byType[Quality.master]?.hash, 'HASH_MASTER');
    expect(byType[Quality.atmos]?.size, '53.68M');
    expect(byType[Quality.atmos]?.hash, 'HASH_ATMOS');
    expect(byType[Quality.hires]?.size, '48.00M');
    expect(byType[Quality.hires]?.hash, 'HASH_HIRES');
    expect(byType[Quality.flac]?.size, '24.96M');
    expect(byType[Quality.flac]?.hash, 'HASH_FLAC');
    expect(byType[Quality.k320]?.size, '9.16M');
    expect(byType[Quality.k320]?.hash, 'HASH_320');
    expect(byType[Quality.k128]?.size, '3.67M');
    expect(byType[Quality.k128]?.hash, baseHash);
  });

  test('parses a cover from the string response used by Kugou', () {
    final cover = parseKgPrivilegeCoverUrl(
      jsonEncode({
        'status': 1,
        'error_code': 0,
        'data': [
          {
            'info': {
              'image': 'http://imge.kugou.com/stdmusic/{size}/cover.png',
              'imgsize': [480, 400, 240],
            },
          },
        ],
      }),
    );

    expect(cover, 'http://imge.kugou.com/stdmusic/480/cover.png');
  });

  test('keeps Wo Bu Nan Guo master size and hash on viper_clear', () {
    // Live metadata from Sun Yanzi's studio recording, 2026-10-26. Tape has
    // a different hash from 320K but only 34 more bytes; clear is 133.72 MiB.
    const songHash = '3FD7E1EC51122C745C637735C8BDE716';
    const clearHash = 'DAEFA540E03EE3C70FFAFBC0BCFF252C';
    final goods = [
      _good('128', 5127719, songHash),
      _good('320', 12819004, 'C4F5F3EAB5EDDA7E150A02BBE9D4D2E3'),
      _good('flac', 35801703, '40652F6D57A19CC77E9E2416A5A4F8EE'),
      _good('high', 36507181, 'BBB4612A8CDADC66379213532AD01EAB'),
      _good('viper_atmos', 78662621, '8EEF9EA5C5642056B0B12041D6CCF4A2'),
      _good('viper_tape', 12819038, '8FE823EE6E30CD2CE8EA5FB1B6E49535'),
      _good('viper_clear', 140213422, clearHash),
    ];

    for (final orderedGoods in [goods, goods.reversed.toList()]) {
      final details = parseKgPrivilegeQualityDetails({
        'error_code': 0,
        'data': [
          {'hash': songHash, 'relate_goods': orderedGoods},
        ],
      });
      final music = KgPlaylistAdapter.parseTrack({
        'audio_id': 284977,
        'hash': songHash,
        'songname': '我不难过',
        'singername': '孙燕姿',
        'filesize': 5127719,
        '320filesize': 12819004,
        '320hash': 'C4F5F3EAB5EDDA7E150A02BBE9D4D2E3',
      }, qualityDetails: details[songHash])!;
      final byType = {
        for (final option in music.meta.qualitys) option.type: option,
      };

      expect(music.bestQuality, Quality.master);
      expect(byType[Quality.master]?.size, '133.72M');
      expect(byType[Quality.master]?.hash, clearHash);
      expect(byType[Quality.k320]?.size, '12.23M');
      final payload = toOldMusicInfoJson(music, quality: Quality.master);
      expect((payload['_types'] as Map)['master'], {
        'size': '133.72M',
        'hash': clearHash,
      });
    }
  });

  test('does not substitute tape for a missing viper_clear variant', () {
    final details = parseKgPrivilegeQualityDetails({
      'error_code': 0,
      'data': [
        {
          'hash': baseHash,
          'relate_goods': [
            _good('320', 12819004, 'MP3_HASH'),
            _good('viper_tape', 12819038, 'DIFFERENT_TAPE_HASH'),
          ],
        },
      ],
    });

    expect(details[baseHash]!.map((option) => option.type), [Quality.k320]);
  });

  test('merges detail results without dropping search-response fallbacks', () {
    final merged = mergeKgQualityOptions(
      const [
        QualityOption(type: Quality.k128, size: '3.67M', hash: 'BASE'),
        QualityOption(type: Quality.hires, size: '40.00M', hash: 'OLD_HIGH'),
      ],
      const [
        QualityOption(type: Quality.k128, size: '3.68M', hash: 'DETAIL'),
        QualityOption(type: Quality.master, size: '98.16M', hash: 'MASTER'),
      ],
    );
    final byType = {for (final option in merged) option.type: option};

    expect(byType[Quality.k128]?.hash, 'DETAIL');
    expect(byType[Quality.hires]?.hash, 'OLD_HIGH');
    expect(byType[Quality.master]?.hash, 'MASTER');
  });
}

Map<String, Object> _good(String quality, int filesize, String hash) => {
  'quality': quality,
  'hash': hash,
  'info': {'filesize': filesize, 'bitrate': 0, 'extname': ''},
};
