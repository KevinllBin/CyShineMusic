import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

const appDisplayName = '栖弦';
const fallbackAppVersion = '1.0.0';

final packageInfoProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});

final appVersionLabelProvider = Provider<String>((ref) {
  final version = ref
      .watch(packageInfoProvider)
      .maybeWhen(
        data: (info) {
          final value = info.version.trim();
          return value.isEmpty ? fallbackAppVersion : value;
        },
        orElse: () => fallbackAppVersion,
      );

  return '$appDisplayName $version';
});
