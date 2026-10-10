import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'music_source_models.dart';

class MusicSourceUpdateNotice {
  const MusicSourceUpdateNotice({
    required this.sourceId,
    required this.sourceKey,
    required this.log,
    required this.updateUrl,
  });

  final String sourceId;
  final String sourceKey;
  final String log;
  final String updateUrl;

  bool matches(MusicSourceRecord record) =>
      sourceId == record.id && sourceKey == record.runtimeKey;

  static MusicSourceUpdateNotice? fromEvent(Map<String, dynamic> event) {
    final sourceId = event['sourceId'];
    final sourceKey = event['sourceKey'];
    final updateUrl = event['updateUrl'];
    if (sourceId is! String ||
        sourceId.isEmpty ||
        sourceKey is! String ||
        sourceKey.isEmpty ||
        updateUrl is! String ||
        updateUrl.length > 4096) {
      return null;
    }
    final url = updateUrl.trim();
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    final rawLog = event['log'];
    final log = rawLog is String ? rawLog.trim() : '';
    return MusicSourceUpdateNotice(
      sourceId: sourceId,
      sourceKey: sourceKey,
      log: log.length > 16384 ? log.substring(0, 16384) : log,
      updateUrl: url,
    );
  }
}

class MusicSourceUpdates extends StateNotifier<List<MusicSourceUpdateNotice>> {
  MusicSourceUpdates() : super(const []);

  // Keep dismissal scoped to this app session and this imported script revision.
  final Set<String> _received = {};
  final Map<String, MusicSourceUpdateNotice> _known = {};

  void receive(MusicSourceUpdateNotice notice) {
    _known[notice.sourceId] = notice;
    final identity =
        '${notice.sourceKey}\u0000${notice.updateUrl}\u0000${notice.log}';
    if (!_received.add(identity)) return;
    state = List.unmodifiable([...state, notice]);
  }

  MusicSourceUpdateNotice? latestFor(MusicSourceRecord record) {
    final notice = _known[record.id];
    return notice != null && notice.matches(record) ? notice : null;
  }

  void showAgain(MusicSourceUpdateNotice notice) {
    state = List.unmodifiable([
      notice,
      ...state.where((item) => item.sourceId != notice.sourceId),
    ]);
  }

  void dismiss(MusicSourceUpdateNotice notice) {
    state = List.unmodifiable(state.where((item) => item != notice));
  }
}

final musicSourceUpdatesProvider =
    StateNotifierProvider<MusicSourceUpdates, List<MusicSourceUpdateNotice>>(
      (ref) => MusicSourceUpdates(),
    );
