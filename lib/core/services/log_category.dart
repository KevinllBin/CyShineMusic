enum AppLogCategory {
  smartTransition('智能过渡', '接歌规划、预加载、交接与过渡进度'),
  playback('播放', '加载、播放控制、缓冲、音频焦点与系统媒体控制'),
  download('下载', '下载队列、文件保存与音乐标签写入'),
  musicSource('音源', '音源脚本、播放地址解析与音源更新'),
  search('搜索', '平台搜索、搜索结果与封面加载'),
  application('应用运行', '启动、前后台切换、权限、主题与应用更新');

  const AppLogCategory(this.label, this.description);

  final String label;
  final String description;
}

Set<AppLogCategory> decodeLogCategories(List<String>? names) => {
  for (final category in AppLogCategory.values)
    if (names?.contains(category.name) ?? false) category,
};

AppLogCategory logCategoryForScope(String scope) {
  if (scope == 'groove-shift' || scope.startsWith('groove-shift-')) {
    return AppLogCategory.smartTransition;
  }
  if (scope == 'player' ||
      scope.startsWith('player-') ||
      scope == 'audio-session' ||
      scope == 'external-audio' ||
      scope == 'sleep-timer' ||
      scope == 'home-widget' ||
      scope == 'tx.lyric') {
    return AppLogCategory.playback;
  }
  if (scope == 'download' || scope == 'batch-download' || scope == 'tagger') {
    return AppLogCategory.download;
  }
  if (scope == 'music-source' || scope.startsWith('music-source-')) {
    return AppLogCategory.musicSource;
  }
  if (scope == 'search' || scope == 'cover') return AppLogCategory.search;
  return AppLogCategory.application;
}
