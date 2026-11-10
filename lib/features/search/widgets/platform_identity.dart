import 'package:flutter/material.dart';

import '../../../core/models/enums.dart';

extension MusicSourceBrand on MusicSource {
  String get shortName => switch (this) {
    MusicSource.all => '全部',
    MusicSource.wy => '网易',
    _ => label,
  };

  String get fullName => switch (this) {
    MusicSource.all => '全平台',
    MusicSource.wy => '网易云音乐',
    _ => '$label音乐',
  };

  Color? get brandColor => switch (this) {
    MusicSource.tx => const Color(0xFF00C568),
    MusicSource.wy => const Color(0xFFE53935),
    MusicSource.kg => const Color(0xFF0066FF),
    MusicSource.kw => const Color(0xFFFFC900),
    MusicSource.mg => const Color(0xFFF52879),
    MusicSource.all => null,
  };
}

class MusicPlatformIcon extends StatelessWidget {
  const MusicPlatformIcon({super.key, required this.source});

  final MusicSource source;

  @override
  Widget build(BuildContext context) {
    if (source == MusicSource.all) {
      return Icon(
        Icons.public_rounded,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.asset(
        'assets/platform_icons/${source.code}.png',
        width: 20,
        height: 20,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    );
  }
}
