import 'package:cy_shine_music/core/app_info.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  test('app version label uses package version', () async {
    PackageInfo.setMockInitialValues(
      appName: appDisplayName,
      packageName: 'com.cyshine.music',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(packageInfoProvider.future);

    expect(container.read(appVersionLabelProvider), '栖弦 1.0.0');
  });
}
