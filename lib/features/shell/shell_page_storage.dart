import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App-lifetime [PageStorageBucket] shared by every shell route.
///
/// Tab switches keep their navigators alive. A route that is actually closed
/// or replaced still loses its own `ModalRoute` bucket; this shared bucket lets
/// its `PageStorageKey` restore the offset if that route is opened again.
///
/// The bucket lives in Riverpod (not a module-level static) so widget tests
/// get a fresh bucket per ProviderScope.
final shellPageStorageBucketProvider = Provider<PageStorageBucket>(
  (ref) => PageStorageBucket(),
);

class ShellPageStorage extends ConsumerWidget {
  const ShellPageStorage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PageStorage(
      bucket: ref.watch(shellPageStorageBucketProvider),
      child: child,
    );
  }
}
