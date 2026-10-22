enum OnlineCollectionKind {
  playlist('歌单'),
  leaderboard('榜单'),
  artist('艺人'),
  album('专辑');

  const OnlineCollectionKind(this.label);
  final String label;
  bool get isCatalog => this == artist || this == album;
}
